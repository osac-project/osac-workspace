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
  concurrency group keyed by `github.sha`, GitHub queues one behind the
  other - it looks stuck but isn't.
- **GHCR "Manage Actions access" chicken-and-egg**: pushing a *new* OCI
  package under a nested path that doesn't match the repo name (e.g.
  `charts/<name>` vs. repo `<name>`) 403s on the very first push, even with
  a correctly-scoped `GITHUB_TOKEN` - the auto-link-package-to-repo behavior
  only reliably triggers when the package name matches the repo name. Fix:
  seed the package once via a personal-access-token push from outside
  Actions, then manually add the repo under the package's "Manage Actions
  access" with Write role (no API exists for this step, UI only).
- **Forked repos have Actions disabled by default** until the owner clicks
  through the one-time "I understand my workflows, go ahead and enable
  them" banner - `gh api repos/{owner}/{repo}/actions/runs --jq .total_count`
  returning `0` even after a push is the tell.
- **CodeRabbit auto-pauses reviews** after enough rapid-fire commits on one
  PR ("branch under active development") and silently stops posting
  anything - neither approve nor request-changes - until `@coderabbitai
  review` is commented to manually trigger a review of the pending commit.

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
