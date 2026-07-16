---
name: github-actions-workflows
description: Create or edit GitHub Actions workflow files (.github/workflows/*.yaml) with security and maintainability best practices applied from the start, instead of discovering them one CodeRabbit review round at a time. Covers least-privilege permissions, SHA-pinned actions, injection-safe env-var handling, semver/tag validation, force-push-safe release gating, and extracting shared bash into scripts. Use when creating a new workflow, adding a job/step to an existing one, wiring up a workflow_run gate, or setting up any tag/release automation.
---

# GitHub Actions Workflows

Every checklist item below came from an actual multi-round CodeRabbit review
cycle - most from OSAC-2185 (5 repos, 4 review rounds each), the notification/
status-aggregation/secret-handling/branch-restriction items from OSAC-1684
(`osac-test-infra` PR #182, a credential-scanning workflow, 3 separate review
cycles across the initial round, a rebase, and a follow-up fix commit - each
triggering its own fresh CodeRabbit pass). Apply them proactively - don't
wait for a reviewer to find them.

## Checklist

Run through this for every new or edited workflow file:

- [ ] **`permissions:`** set explicitly on every job (least privilege). A job
      that only reads event metadata (no checkout, no API calls) gets
      `permissions: {}`. Never rely on the inherited/default `GITHUB_TOKEN` scope.
- [ ] **No `${{ }}` spliced directly into a `run:` shell script.** Route
      through `env:` and reference as `"$VAR"` instead - this applies to
      `secrets.*`, `github.*`, and `workflow_run.*` alike, even ones that feel
      "static" (e.g. a workflow-level `env:` constant, or `github.repository`).
      A workflow-level `env:` block is already auto-injected as a real shell
      var into every `run:` step - reference it as `"$VAR"` directly, don't
      redundantly re-map it via a step-level `env: VAR: ${{ env.VAR }}`.
- [ ] **Pin *every* action to a full commit SHA**, not just the well-known
      ones. `actions/checkout` gets fixed first and often the last one in the
      same job (e.g. `azure/setup-helm@v5`) gets missed:
      `actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0  # v7.0.0`
- [ ] **`persist-credentials: false`** on every `actions/checkout` step unless
      that job explicitly pushes back to the repo.
- [ ] **Validate tags with a real semver grammar**, not `startsWith(ref, 'v')`
      alone. Reject leading zeros (`v01.2.3`) and, if the tag gets used
      verbatim as a container image tag downstream, reject `+build` metadata
      too (Docker/OCI tags can't contain `+`). See the regex in
      [reference.md](reference.md#semver-regex).
- [ ] **If gating a release/publish on an upstream workflow's success**, use
      the `workflow_run` + guard-job pattern below - don't just trust
      `push: tags:` on both workflows independently.
- [ ] **Use officially documented REST endpoint forms**, not ones that merely
      happen to also work. Check the actual docs, not just empirical testing
      - see [reference.md](reference.md#documented-endpoints).
- [ ] **Capture a `gh api`/command-substitution result in a variable before**
      parsing with `read -r a b <<< "$result"` - piping a failing command
      straight into `read`'s here-string under `set -e` only checks `read`'s
      exit status, silently swallowing the real failure.
- [ ] **Extract bash logic repeated across steps/jobs into a checked-in,
      `chmod +x`'d script** under `.github/scripts/` instead of copy-pasting -
      see [reference.md](reference.md#shared-scripts).
- [ ] **Validate before committing**: `actionlint` (0 errors) and `bash -n`
      on any script, then actually test the regex/script logic locally (see
      Verification below) - don't just eyeball it.
- [ ] If a Sigstore/cosign signing requirement is flagged and it's a bigger
      effort than the current change, don't silently skip it - tell the user
      it's out of scope and ask if it should be a follow-up.
- [ ] **Alert/notify steps need explicit failure semantics, not the implicit
      `success()` AND.** A bare `if: <condition>` (no `success()`/`failure()`/
      `always()`) implicitly ANDs with `success()`, so a hard failure in an
      *earlier* step - exactly the case most worth alerting on - silently
      skips the very notification meant to catch it:
      ```
      # BAD - skipped entirely if the "scan" step hard-fails (not just sets
      # leaks-found=false)
      - if: steps.scan.outputs.leaks-found == 'true'
        run: notify-slack ...

      # GOOD
      - if: >
          always() &&
          (steps.scan.outcome == 'failure' || steps.scan.outputs.leaks-found == 'true')
        run: notify-slack ...
      ```
- [ ] **Don't let "couldn't check" collapse into "checked, clean."** A failed
      fetch/download/list needs its own distinct status, separate from the
      actual pass/fail result (e.g. `SCAN_OK=false` vs `LEAKS_FOUND=false`) -
      otherwise an auth/permission failure silently masquerades as a clean
      scan to every downstream consumer. This includes the HTTP status
      *and* the response shape: a 200 doesn't guarantee the body has the
      field you expect - `jq`'s `.items[]?` turns a missing/wrong-typed
      field into empty output just as readily as a genuinely-empty result,
      so validate the field is actually an array (`jq -e '.items | type ==
      "array"'`) before trusting "empty" as a real answer - and if you're
      also bounds-checking a count field (e.g. `total_count <= 100`), check
      its *type* too: a missing/null field passes a bare `<=` comparison in
      `jq` (null compares less than any number), so `type == "number"` has
      to come first. Some GitHub
      endpoints add a *third* way to be wrong on a 200: code search can
      return `incomplete_results: true` on a server-side timeout with an
      otherwise well-formed `.items` array - check API-specific
      completeness fields too, not just the shape.
- [ ] **When aggregating several steps' status into one summary/notification,
      check `steps.<id>.outcome`, not just `steps.<id>.outputs.*`.** A step
      skipped because an earlier one failed leaves its outputs empty; an
      `|| '0'`/`|| 'false'` fallback on that empty output then reads as a
      clean pass instead of the incomplete result it actually is. Revisit
      this OR-list every time a new step gets added between detection and
      the notification - a gate written before that step existed won't
      automatically cover its failure too.
- [ ] **Validate untrusted numeric/string input (e.g. a `workflow_dispatch`
      input) before using it in date/arithmetic logic**, not after. `0`, a
      negative number, or non-numeric text flowing into something like
      `date -d "${N} hours ago"` produces a wrong or empty result *silently*
      - the job still reports success, having checked the wrong window (or
      nothing at all). If the input's scale interacts with another already-
      known limitation (e.g. an unpaginated `per_page=100` fetch), cap the
      upper bound too, not just the lower one - document it as a sanity
      bound against a bad input, not a guarantee, if it can't be derived
      precisely.
- [ ] **`curl` exits `0` on 4xx/5xx by default**, and a manually-checked
      `CODE=$(curl -w '%{http_code}' ...)` is separately *not* exempt from
      `set -e` on a *transport*-level failure (DNS, connection reset, TLS) -
      two different gaps, both need closing on any `curl` call whose success
      matters. See [reference.md](reference.md#curl-failure-handling).
- [ ] **Inside a composite action, pass data between its own steps via
      `steps.<id>.outputs`, not `$GITHUB_ENV`.** An env var written there
      leaks into every later step of the *calling* job (not just this
      action's own steps) and collides if the action runs more than once in
      the same job.
- [ ] **Escape `|` when interpolating dynamic data (log paths, rule IDs,
      etc.) into a Markdown table** built via `jq`/`echo` for a job summary
      or issue body - an unescaped pipe in the data breaks the rendered
      table.
- [ ] **If a script handles raw secrets locally** (downloaded logs, decrypted
      files), **clean up the local copy via `trap ... EXIT`**, not just
      deleting the remote/authoritative copy - otherwise the raw secret
      still sits on disk, especially relevant on persistent self-hosted
      runners. This includes *derived* files, not just the original input -
      a scanning tool's own report (e.g. gitleaks' JSON output) embeds the
      actual matched secret value just as much as the logs it scanned, and
      is easy to forget in the trap since it's a byproduct, not something
      you explicitly downloaded. Never point downstream reporting (job
      summaries, issue bodies) at that raw report directly either - produce
      a sanitized copy (drop the secret-value field, keep only what
      reporting needs) for anything outside the redact/mask/purge steps to
      read.
- [ ] **A per-item failure in a batch/loop must abort, not skip-and-continue**,
      whenever a later step trusts the *entire* result (e.g. uploading a
      "redacted" directory as an artifact, assuming every file in it really
      was redacted) - skipping one bad item ships it downstream with
      whatever the batch was supposed to fix still intact. See
      [reference.md](reference.md#fail-loud-on-per-item-batch-failures).
- [ ] **Track detection and remediation as separate outcomes**
      (e.g. `PURGE_OK` alongside `LEAKS_FOUND`) - don't fold "found a
      problem" and "successfully fixed it" into one status flag, or a
      failed fix silently reads as a successful one. See
      [reference.md](reference.md#detection-vs-remediation-status).
- [ ] **A same-file `if:` conditional is not a security boundary against ref
      selection.** For `workflow_dispatch` (or anything else where the
      invoker picks which ref's copy of the workflow runs), a check like
      `if: github.ref == 'refs/heads/main'` is trivially bypassed - the
      invoker controls the exact file being executed when dispatching
      against their own branch, and would just remove the check in their
      copy. Use a GitHub Environment's deployment-branch policy instead
      (`environment: <name>`, restricted to `main` in Settings ->
      Environments) - that's enforced server-side regardless of the
      dispatched ref's file content. See
      [reference.md](reference.md#workflow-dispatch-branch-restriction).

## The workflow_run gate pattern

The single highest-value pattern from this cycle: gating a chart/release
publish on a sibling image-build workflow's success, instead of both
triggering independently off the same tag push (which lets a chart "publish"
even when the matching image never got built).

```yaml
name: Publish something

on:
  workflow_run:
    workflows: ["Build container image"]  # must match the *name:* field, not the filename
    types: [completed]

jobs:
  guard:
    name: Verify image build succeeded
    runs-on: ubuntu-latest
    permissions: {}
    if: >
      github.event.workflow_run.event == 'push' &&
      startsWith(github.event.workflow_run.head_branch, 'v')
    outputs:
      tag: ${{ github.event.workflow_run.head_branch }}
      sha: ${{ github.event.workflow_run.head_sha }}
    steps:
    - name: Check image build result
      env:
        CONCLUSION: ${{ github.event.workflow_run.conclusion }}
        HEAD_BRANCH: ${{ github.event.workflow_run.head_branch }}
      run: |
        semver_re='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(\.((0|[1-9][0-9]*)|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?$'
        if ! [[ "$HEAD_BRANCH" =~ $semver_re ]]; then
          echo "::error::Tag '$HEAD_BRANCH' is not a valid semver release tag"
          exit 1
        fi
        if [[ "$CONCLUSION" != "success" ]]; then
          echo "::error::Image build for tag $HEAD_BRANCH did not succeed (conclusion: $CONCLUSION). Refusing to publish."
          exit 1
        fi
        echo "Image build succeeded for tag $HEAD_BRANCH"

  publish:
    needs: guard
    runs-on: ubuntu-latest
    permissions:
      contents: write
      packages: write
    steps:
    - name: Checkout repository
      uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0  # v7.0.0
      with:
        ref: ${{ needs.guard.outputs.sha }}
        persist-credentials: false

    # Re-verify right after checkout (before packaging/pushing anything) so a
    # force-push/retag race is caught before an artifact is uploaded - not
    # just once, right before the release. See scripts/verify-tag-matches-sha.sh.
    - name: Verify tag still points at the guarded commit
      env:
        GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        TAG: ${{ needs.guard.outputs.tag }}
        GUARDED_SHA: ${{ needs.guard.outputs.sha }}
        REPO: ${{ github.repository }}
      run: .github/scripts/verify-tag-matches-sha.sh

    # ... package/publish steps here, using needs.guard.outputs.tag ...

    # Re-verify again immediately before the release call. This - and
    # --verify-tag below - are defense in depth, not a guarantee: a tag
    # can still be moved in the instant between this check and the API
    # call. The structural fix is a tag-protection ruleset or immutable
    # releases on the repo (see reference.md#tag-immutability) so tags
    # can't be moved after creation in the first place.
    - name: Verify tag still points at the guarded commit
      env:
        GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        TAG: ${{ needs.guard.outputs.tag }}
        GUARDED_SHA: ${{ needs.guard.outputs.sha }}
        REPO: ${{ github.repository }}
      run: .github/scripts/verify-tag-matches-sha.sh

    # --verify-tag only confirms the tag still exists at release-creation
    # time - it does NOT re-check which commit it points at, so it can't
    # by itself catch a retag that happened after the check above.
    - name: Create GitHub Release
      run: |
        gh release create "${TAG}" --repo "${REPO}" --generate-notes --verify-tag
      env:
        GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        TAG: ${{ needs.guard.outputs.tag }}
        REPO: ${{ github.repository }}
```

Copy [scripts/verify-tag-matches-sha.sh](scripts/verify-tag-matches-sha.sh)
into the target repo's `.github/scripts/` and `chmod +x` it - don't
reimplement the dereferencing/failure-masking logic inline.

**This checkout is the repo's own tagged source** (pushed by someone with
write access to create the tag), not an untrusted pull-request
contribution, so the classic `workflow_run` privilege-escalation risk - a
`pull_request`-triggered workflow chaining into a privileged `workflow_run`
job that then checks out and executes attacker-controlled code - doesn't
directly apply to this specific gate. If you adapt this pattern to gate on
a workflow that *can* be triggered by an untrusted contribution (e.g. one
that also runs on `pull_request` from forks), don't check out or execute
that contributor's code in the privileged `publish` job - treat anything
produced by the upstream run as untrusted data (verify/attest it) and keep
real build/compile steps confined to the unprivileged workflow. See
[reference.md](reference.md#workflow-run-privilege-escalation) for the
general pattern.

An immutability control isn't optional here - a tag-protection ruleset or
immutable release is what makes the SHA re-checks above actually mean
something - see [reference.md](reference.md#tag-immutability).

## Verification before committing

1. `actionlint path/to/workflow.yaml` - must be 0 errors.
2. `bash -n path/to/script.sh` on any new/edited script.
3. Test any new regex directly, don't just read it:

   ```bash
   semver_re='...'
   for t in "v1.2.3" "v01.2.3" "v1.2.3+build.1" "vfoo"; do
     [[ "$t" =~ $semver_re ]] && echo "MATCH: $t" || echo "REJECT: $t"
   done
   ```

4. If the change is a `workflow_run` trigger or anything tag/release-related,
   static checks aren't enough - it needs a real end-to-end test (push a real
   tag to a fork, watch the run, and also break something deliberately to
   confirm the negative path fails loudly instead of going green). See
   [reference.md](reference.md#live-testing-gotchas) for the traps found
   while doing this (concurrency-group collisions, GHCR package-linking
   chicken-and-egg, forked-repo Actions being disabled by default).

Editing *this skill itself* (not a workflow that uses it)? Run
[scripts/self-check.sh](scripts/self-check.sh) - it does steps 1-3 above
against the skill's own embedded template/script/regexes, plus a live
functional test of `verify-tag-matches-sha.sh` against a real tag, so a
content edit can't silently break an example without something catching it.
The full guarantee only holds when `actionlint` and an authenticated `gh`
are both installed - missing either degrades that specific check to a
printed `skip`, not a failure, so re-run with both available before
trusting an all-green result completely.

## Also applies (enforced automatically, not just for workflows)

These aren't workflow-specific but every commit touching a workflow will hit
them: branch from latest `origin/main` before starting (never reuse a stale
branch), rebase before pushing and use `--force-with-lease` not `--force`,
and add an `Assisted-by: <Tool Name> <tool-noreply-email>` trailer (e.g.
`Assisted-by: Claude Code <noreply@anthropic.com>`) to AI-assisted commits -
never `Co-Authored-By` for AI tools. See the root `AGENTS.md` ("Critical
Rules" / "Git Workflow") and the target repo's own `AGENTS.md`/`CLAUDE.md`
for the full fork/branch/attribution conventions.

## Additional resources

- [reference.md](reference.md) - semver regex, documented-endpoint gotchas,
  live-testing traps, and niche bash-script pitfalls (IFS joins, shallow
  submodule clones, run-attempt collisions).
- Each component repo's standing rules directory (e.g. `.claude/rules/`,
  `.cursor/rules/` - whichever your agent uses) for the full GitHub Actions
  security/maintainability/bash-safety rules this skill was distilled from.
