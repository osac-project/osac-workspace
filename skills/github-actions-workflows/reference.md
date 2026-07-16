# Reference: GitHub Actions Gotchas

Detailed backup for [SKILL.md](SKILL.md)'s checklist. Read this when you hit
the specific situation, not proactively.

## Semver regex

Official semver.org grammar, adapted with a required `v` prefix. Rejects
leading zeros (`v01.2.3`, `v1.2.3-01`) and accepts hyphenated
prerelease/build identifiers (`v5.0.0-rc-1`, `v1.2.3-alpha.1`):

```bash
semver_re='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(\.((0|[1-9][0-9]*)|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
```

If the tag is later used verbatim as a **container image tag**, drop the
trailing `(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?` group entirely - Docker/OCI
tags cannot contain `+`, so a tag like `v1.2.3+build.1` would pass this regex
but produce an unusable image reference downstream. Use the same grammar
without the `v` prefix when validating an already-stripped version string.

## Documented endpoints

"Empirically works" and "officially documented" aren't the same thing, and
only the second is guaranteed to keep working. Example that actually bit us:
GitHub's "Get a reference" endpoint is documented as **singular**
`GET /repos/{owner}/{repo}/git/ref/{ref}`; the **plural** form
(`git/refs/{ref}`) is only documented for `PATCH`/`DELETE`. Both currently
return identical data for `GET` - but verify against the actual docs
(`https://docs.github.com/en/rest/git/refs`) before relying on undocumented
behavior, empirical testing alone isn't enough.

## Dereferencing annotated tags

`GET git/ref/tags/<tag>` returns the tag *object's* SHA for annotated tags,
not the commit SHA - comparing it directly against a commit SHA will always
mismatch. Peel it with a second call:

```bash
ref_json="$(gh api "repos/${REPO}/git/ref/tags/${TAG}" --jq '[.object.type, .object.sha] | @tsv')"
read -r current_type current_sha <<< "$ref_json"
if [[ "$current_type" == "tag" ]]; then
  current_sha="$(gh api "repos/${REPO}/git/tags/${current_sha}" --jq .object.sha)"
fi
```

Note `ref_json` is captured *before* `read` - see the checklist item on
`gh api`-into-`read` masking.

## Tag immutability

Re-checking a tag's SHA right before publishing (see the `workflow_run` gate
template in [SKILL.md](SKILL.md)) is defense in depth, not a guarantee -
there's still a window between the last check and the actual publish/release
call where a tag could be force-moved. `gh release create --verify-tag` does
not close that window either: it only confirms the tag *exists* at
release-creation time, it does not re-check *which commit* it points at.

The structural fix is to make the tag unable to move in the first place:

- **Tag-protection ruleset**: a repository ruleset targeting tags (e.g.
  `v*`) that blocks force-pushes/deletions on matching refs. Configured via
  repo Settings -> Rules -> Rulesets, no workflow-side change needed.
- **Immutable releases** (GitHub feature, currently rolling out): once a
  release is marked immutable, its underlying tag is locked to that commit
  for the release's lifetime - it can't be force-moved even by someone with
  push access, unlike a ruleset which is more broadly bypassable by anyone
  with ruleset-bypass permissions.

If neither is enabled on a repo, say so explicitly when proposing this gate
pattern - don't let the SHA re-checks imply a stronger guarantee than they
actually provide.

## workflow_run privilege escalation

The classic `workflow_run` risk (see GitHub's own
[Actions Security Lab writeups](https://securitylab.github.com/resources/github-actions-new-patterns-and-mitigations/)):
an unprivileged workflow triggered by `pull_request` (which can run on an
untrusted fork's code with a read-only token) completes, then a *privileged*
`workflow_run` job - with `contents: write`/`secrets` access - checks out
and executes that same untrusted code, effectively laundering it into a
privileged context.

The gate pattern in this skill checks out the repo's own tagged source
(pushed by someone who already had write access to create the tag), not an
untrusted contribution, so that specific escalation path doesn't apply to
it directly. But if you adapt the pattern to gate on a workflow that *can*
be triggered by an untrusted contribution (most commonly: one that also
runs on `pull_request` from forks), don't carry over the "just check out
and build in the privileged job" shape unchanged:

- Don't check out or execute the contributor's code in the privileged job.
- Treat anything the upstream (unprivileged) run produced - artifacts,
  outputs - as untrusted data; verify or attest it rather than trusting it.
- Keep real build/compile steps in the unprivileged workflow; let the
  privileged job do only release-specific work (tagging, publishing
  already-built/verified artifacts).

## workflow_dispatch branch restriction

A related but distinct escalation shape from the `workflow_run` one above,
found on `osac-test-infra` PR #182: `workflow_dispatch` lets anyone with
write access to the repo pick *any* branch or tag to run the workflow
against, and GitHub executes *that ref's own copy* of the workflow file -
not the default branch's. If the job being dispatched is privileged (Vault
secrets, an org-scoped token, `contents: write`, etc.), this lets that
person push a modified copy of the workflow to a throwaway branch - e.g.
with a same-file guard like `if: github.ref == 'refs/heads/main'` simply
deleted - and then dispatch against that branch to run their version with
the job's full privileges, bypassing whatever review gate protects the
default branch.

```yaml
# INSUFFICIENT - lives in the same file the invoker controls when
# dispatching against a branch other than main; they'd just remove this
# line in their own copy before dispatching
jobs:
  audit:
    if: github.ref == 'refs/heads/main'
    runs-on: self-hosted-with-vault-access
```

The fix isn't a workflow-file check at all, since *any* check living in the
dispatched file is subject to the same bypass. Use a GitHub Environment's
deployment-branch policy instead - it's enforced server-side by GitHub
based on the *ref being dispatched*, independent of what that ref's copy of
the workflow file contains:

```yaml
jobs:
  audit:
    environment: audit-privileged  # Settings -> Environments -> Deployment
                                    # branches and tags -> "Selected branches
                                    # and tags" -> main only (org-admin action,
                                    # can't be done from the workflow file)
    runs-on: self-hosted-with-vault-access
```

This requires an actual repo-admin step (creating the environment and
setting its branch policy) that can't be expressed in the workflow file
itself - call that out explicitly as a follow-up action item rather than
letting the `environment:` line imply protection that doesn't exist yet
(an `environment:` referencing a not-yet-created environment is not an
error and adds no restriction).

`schedule`-triggered runs are unaffected either way - they always run the
default branch's copy of the workflow regardless of this setting, so this
control only actually changes `workflow_dispatch` behavior.

## curl failure handling

Two distinct gaps in a script that calls `curl` and checks the result
itself, both found on `osac-test-infra` PR #182:

**Gap 1: curl exits `0` on HTTP 4xx/5xx by default.** If the call's success
matters, use `--fail-with-body` (fails the curl invocation itself, body
still captured for logging) or manually check `-w '%{http_code}'`.

**Gap 2 (separate from Gap 1): a manually-checked status code doesn't cover
transport failures.** Even after adding `-w '%{http_code}'` to handle Gap 1,
a plain assignment is *still* subject to `set -e` if curl fails at the
transport level (DNS resolution, connection refused/reset, TLS handshake) -
that's a curl exit-code failure, not an HTTP status, so checking the status
code afterward never happens; the script dies on the assignment itself
instead:

```bash
# BAD - transport failure here trips `set -e` before the status check below
# ever runs, so a network hiccup crashes the whole script instead of
# landing in the "delete failed" branch
HTTP_CODE=$(curl -sL -o /dev/null -w '%{http_code}' -X DELETE "$URL")
if [[ "${HTTP_CODE}" != "204" ]]; then ...

# GOOD - `if ! VAR=$(...)` is exempt from errexit (a plain assignment isn't);
# --connect-timeout/--max-time stop a hung connection from blocking the job
if ! HTTP_CODE=$(curl -sL -o /dev/null -w '%{http_code}' -X DELETE \
  --connect-timeout 10 --max-time 30 "$URL"); then
  HTTP_CODE="curl-transport-error"
fi
if [[ "${HTTP_CODE}" != "204" ]]; then ...
```

Apply this to *every* curl call in a script that manually checks status,
not just the one that happens to get flagged first - CodeRabbit caught this
on `scan-run-logs.sh`'s two calls in one review round, then flagged the
identical pattern in the sibling script `discover-e2e-runs.sh` (four more
calls) in the very next round once the diff included it, and the missing
`--connect-timeout`/`--max-time` half of it a *third* time after that, on
three more curl calls in `audit-workflow-logs.yml`. Three separate files,
three separate review rounds, same exact gap each time. Fix the pattern
everywhere it appears across a PR's changed files in one pass, rather than
waiting for each file to individually surface in its own review round.

## Fail loud on per-item batch failures

When a script loops over multiple files/items and a *later* step trusts the
*entire* result set (e.g. `actions/upload-artifact` on a "redacted" logs
directory, assuming every file in it was actually redacted), a per-item
failure must abort the whole operation - not log a warning and move on to
the next item. Found on `osac-test-infra` PR #182's `redact.py`:

```python
# BAD - looks like defensive error handling, but an unreadable file also
# couldn't be redacted, and it still ships in the "redacted" directory
# with its original secret intact
for path in redacted_dir.rglob("*"):
    try:
        text = path.read_text()
    except OSError:
        continue  # <- silently ships this file un-redacted

# GOOD - fail the whole script; let the caller's own set -e / status-file
# contract propagate this as a real failure, not a false "success"
for path in redacted_dir.rglob("*"):
    try:
        text = path.read_text()
    except OSError as exc:
        print(f"cannot read {path}, aborting: {exc}", file=sys.stderr)
        sys.exit(1)
```

The "skip and continue" instinct makes sense for a *reporting* loop (e.g.
the cross-repo audit skipping one target's listing failure and continuing
to the next) - the difference is whether skipping compromises a safety
guarantee the caller is relying on. Skipping an unscannable *target* just
means less coverage this run (and is tracked as such, per the fail-closed
status pattern below); skipping an unredactable *file* inside a batch
that's about to be uploaded as "the redacted copy" means shipping exactly
the thing the step exists to prevent.

## Detection vs. remediation status

Finding a problem and successfully acting on it are two operations that can
fail independently - don't fold them into one status flag. Found on
`osac-test-infra` PR #182's `scan-run-logs.sh`: gitleaks finding leaked
secrets (`LEAKS_FOUND=true`) and then successfully deleting the raw logs
that contained them (`PURGE_OK`) are separate outcomes; a delete-API call
can fail for reasons that have nothing to do with whether anything was
found (permissions, a transient 5xx, a transport error). Before this was
split out, a failed delete still got reported - in both the job summary and
the audit's tracking-issue body - as "the raw logs have been deleted",
which is simply false when the delete call failed.

Give remediation its own flag, meaningful only when detection actually
found something (a clean scan has nothing to remediate, so the flag is
vacuously `true` in that case - see the `SCAN_OK`/`LEAKS_FOUND`/`PURGE_OK`
three-way split in `scan-run-logs.sh` for a worked example), and make every
downstream summary/notification conditional on it rather than assuming the
remediation step that ran right after detection must have succeeded.

The same principle showed up again one review round later, in a different
shape: `audit-workflow-logs.yml`'s job summary and tracking-issue body both
unconditionally linked to an `audit-redacted-logs-*` artifact once findings
existed, regardless of whether the `actions/upload-artifact` step that was
supposed to produce it had actually succeeded. "Detection" (finding leaked
credentials) and "the artifact upload that's supposed to preserve evidence
of them" are just as independent as "detection" and "purge" were - give the
upload step an `id`, check `steps.<id>.outcome`, and only promise the
artifact link when it's actually there.

## Shared scripts

Copy-pasting the same bash logic into multiple `run:` blocks - especially
across separate jobs, which can't share in-memory state anyway - means every
future fix has to be applied everywhere, and it's easy to miss one:

```yaml
# BAD - same verification logic duplicated in 4+ steps across 2+ jobs
- run: |
    read -r current_type current_sha <<< "$(gh api ...)"
    if [[ "$current_type" == "tag" ]]; then ...

# GOOD - one script, invoked wherever needed
- run: .github/scripts/verify-tag-matches-sha.sh
```

Put it in `.github/scripts/`, `chmod +x` it, and have it read inputs from
already-exported `env:` vars rather than positional args. See
[scripts/verify-tag-matches-sha.sh](scripts/verify-tag-matches-sha.sh) for a
working example.

Don't let two jobs independently *recompute* the same result either (not
just similar logic - the literal same output) - a new tag could land between
two separate invocations, silently making a later step act on a different
value than what an earlier step already validated. Pass it forward instead:
- **Small scalar** (a version string, a SHA) -> job `outputs`.
- **File-based/structured data** -> `upload-artifact` from the producer,
  `download-artifact` in the consumer, instead of re-running the generator.

## Live-testing gotchas

Static checks (`actionlint`, `bash -n`) can't validate a `workflow_run`
trigger's actual runtime behavior. When testing on a personal fork:

- **Concurrency-group collisions**: if the test tag points at the same
  commit as a `push`-to-`main` build, and both workflows share a
  concurrency group keyed by the commit SHA, GitHub queues one behind the
  other - it looks stuck but isn't. On a `workflow_run` trigger, key the
  group off `github.event.workflow_run.head_sha`, not plain `github.sha` -
  the latter resolves to the default branch's latest commit on this event
  type, not the commit that triggered the run, so it silently fails to
  collide with the build it's supposed to be paired with.
- **GHCR "Manage Actions access" chicken-and-egg**: pushing a *new* OCI
  package under a nested path that doesn't match the repo name (e.g.
  `charts/<name>` vs. repo `<name>`) 403s on the very first push, even with
  a correctly-scoped `GITHUB_TOKEN` - the auto-link-package-to-repo behavior
  only reliably triggers when the package name matches the repo name. Fix:
  seed the package once via a personal-access-token push from outside
  Actions, then manually add the repo under the package's "Manage Actions
  access" with Write role (no API exists for this step, UI only).
- **A public fork's Actions are disabled by default** until the owner
  clicks through the one-time "I understand my workflows, go ahead and
  enable them" banner - `gh api repos/{owner}/{repo}/actions/runs --jq
  .total_count` returning `0` even after a direct push is the tell. This is
  scenario-specific, though: `schedule:`-triggered workflows stay disabled
  on a public fork even after that banner is clicked (no equivalent
  one-time unlock exists for cron), and pull-request runs *from* a fork are
  gated by a separate "approve and run" requirement on top of it. Private
  forks aren't affected by any of this the same way - don't apply this note
  there unchanged.
- **AI review bots can auto-pause** after enough rapid-fire commits on one
  PR ("branch under active development") and silently stop posting
  anything - neither approve nor request-changes. Check for this before
  assuming a stalled review means everything already passed; most bots
  (e.g. CodeRabbit via `@coderabbitai review`) need to be manually
  re-triggered with a PR comment to review the pending commits.

## Re-triggering a failed check

Don't assume every red check is a Prow `/retest` - check which system actually
owns the run first, by looking at the failed check's "Details" link URL:

- **Native GitHub Actions run** (URL is `github.com/<owner>/<repo>/actions/runs/...`):
  re-run via `gh run rerun <run-id> --repo <owner>/<repo> --failed` (CLI), or
  the "Re-run failed jobs" button on the Actions run page (UI). `--failed`
  only re-runs the failed job(s), not the whole matrix - faster than a full
  re-run, and preserves logs from the jobs that already passed.
- **Prow-orchestrated check** (URL is `prow.ci.openshift.org/...`, common for
  e2e/integration suites gated by `tide`): comment `/retest` on the PR
  instead - `gh run rerun` doesn't apply since GitHub Actions never owned
  the run.

## Self-check / test script hygiene

Found via review of this skill's own
[scripts/self-check.sh](scripts/self-check.sh) - the same scrutiny applies
to any test/verification script, not just the workflows it exercises:

- **Don't discard a subprocess's output on failure just because you only
  check its exit code.** `cmd &>/dev/null; then pass; else fail "should
  have succeeded"; fi` gives a real regression and a transient network
  hiccup an identical, contentless failure message. Capture combined
  output into a variable and include it in the failure message instead:
  `out="$(cmd 2>&1)" && pass || fail "should have succeeded: $out"`.
- **If a test exercises a real external resource** (a specific repo, tag,
  or endpoint), make it overridable via env vars with the current value as
  the default (`REPO="${SELF_CHECK_REPO:-osac-project/osac-operator}"`)
  rather than hardcoding it, and provide an explicit skip switch (e.g.
  `SELF_CHECK_SKIP_LIVE=1`) for offline/sandboxed runs. The test's own
  reliability shouldn't be permanently coupled to one third party's tag
  never disappearing or a network call always succeeding.
- **If any step degrades to "skip" rather than "fail" when an optional
  tool is missing, say so wherever the script's guarantee is described.**
  An all-green run with `actionlint`/`gh`/etc. absent is a materially
  weaker guarantee than one with everything present - don't let the
  wording imply otherwise.

## Niche bash pitfalls

- **`"${arr[*]}"` only honors the first character of a multi-character
  `IFS`.** `IFS=", "; echo "${arr[*]}"` joins with `,` only, silently
  dropping the space. Join explicitly instead:

  ```bash
  joined=$(printf ', %s' "${arr[@]}"); joined="${joined#, }"
  ```

- **Shallow submodule clones break `git describe --tags` inside them.**
  `actions/checkout` clones submodules at `--depth=1` even when the
  superproject uses `fetch-depth: 0` - that setting doesn't propagate to
  submodules. `git describe --tags` fails outright with no ancestor history;
  an `|| echo "<fallback>"` will silently swallow this every time in CI
  while working fine locally (where a full clone already exists). Unshallow
  first if needed: `git -C "$path" fetch --unshallow --tags --quiet`
  (guard with `git rev-parse --is-shallow-repository` since `--unshallow`
  errors on an already-complete repo).
- **`git describe --tags --abbrev=0` picks whichever tag is nearest HEAD**,
  including unrelated tag namespaces (e.g. a Go submodule's `api/vX.Y.Z`
  alongside chart releases' plain `vX.Y.Z`). Always pass `--match` with the
  exact expected pattern - and re-validate the result with a real regex
  afterward, since `--match` is glob (fnmatch), not regex, and can't express
  "digits only, then nothing else".
- **Re-running a failed workflow run only increments `GITHUB_RUN_ATTEMPT`**,
  not `GITHUB_RUN_ID`/`GITHUB_RUN_NUMBER`. A run-scoped identifier built from
  only the latter two will collide on "Re-run failed jobs" against the same
  base commit - include `GITHUB_RUN_ATTEMPT` too if the identifier needs to
  be unique per attempt, not just per run.
- **`git add -A -- pathA pathB` fails atomically (stages nothing) if *any*
  one pathspec doesn't exist in that repo** - e.g. reusing the same commit
  command across sibling repos where only some have a `build-image.yaml`.
  Stage each file individually (`git add -- pathA; git add -- pathB`) or
  filter to paths that actually exist first, rather than one combined
  command copy-pasted across repos with differing layouts.
- **A command's exit status inside process substitution (`done < <(cmd)`)
  is invisible to the surrounding shell, even under `set -e`.** If `cmd`
  fails partway through emitting output (e.g. `jq` hits a malformed item
  mid-stream), whatever it already flushed still reaches the loop as if
  nothing went wrong - the failure never trips `errexit` and the loop
  variable driving your success/failure tracking (e.g. `DISCOVERY_FAILED`)
  never finds out. Redirect to a file with its own explicitly-checked exit
  status first, then loop over the file, instead of piping straight into
  the loop:

  ```bash
  # BAD - a jq failure partway through leaves TARGETS silently partial,
  # with nothing here to notice
  while IFS= read -r TARGET; do
    TARGETS+=("${TARGET}")
  done < <(jq -r '.items[]? | ...' "${RESP}" | sort -u)

  # GOOD
  if ! jq -r '.items[]? | ...' "${RESP}" | sort -u > "${TARGETS_FILE}"; then
    DISCOVERY_FAILED=true
  else
    while IFS= read -r TARGET; do
      TARGETS+=("${TARGET}")
    done < "${TARGETS_FILE}"
  fi
  ```
