---
name: github-actions-workflows
description: Create or edit GitHub Actions workflow files (.github/workflows/*.yaml) with security and maintainability best practices applied from the start, instead of discovering them one CodeRabbit review round at a time. Covers least-privilege permissions, SHA-pinned actions, injection-safe env-var handling, semver/tag validation, force-push-safe release gating, and extracting shared bash into scripts. Use when creating a new workflow, adding a job/step to an existing one, wiring up a workflow_run gate, or setting up any tag/release automation.
globs:
  - ".github/workflows/*.yaml"
  - ".github/workflows/*.yml"
---

# GitHub Actions Workflows

Every checklist item below came from an actual multi-round CodeRabbit review
cycle - most from OSAC-2185 (5 repos, 4 review rounds each), the notification/
status-aggregation/secret-handling/branch-restriction items from OSAC-1684
(`osac-test-infra` PR #182, a credential-scanning workflow, 3 separate review
cycles across the initial round, a rebase, and a follow-up fix commit - each
triggering its own fresh CodeRabbit pass), and the log-redaction /
notify-status lessons from follow-up work on credential scanning (gather
scripts echoing "redacted" diagnostics back into the job console, and Slack
treating credential-only findings as FAILED). Apply them proactively -
don't wait for a reviewer to find them.

## Checklist

Run through this for every new or edited workflow file:

- [ ] **`permissions:`** set explicitly on every job (least privilege). A job
      that only reads event metadata (no checkout, no API calls) gets
      `permissions: {}`. Never rely on the inherited/default `GITHUB_TOKEN` scope.
- [ ] **No `${{ }}` in `run:` blocks.** Route through `env:` and reference
      as `"$VAR"` - applies to `secrets.*`, `github.*`, `workflow_run.*`
      alike. Workflow-level `env:` is already injected into every `run:`
      step; don't re-map via step-level `env: VAR: ${{ env.VAR }}`.
      This rule is for `run:` only - `${{ }}` in `outputs:`, `if:`, `with:`
      is correct and required.

- [ ] **Pin *every* action to a full commit SHA**, not just well-known ones:
      `actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0  # v7.0.0`
- [ ] **A SHA pin needs an update *mechanism*.** Especially for pinned
      **reusable workflows** - Dependabot resolves against tags/releases; if
      the repo publishes none, retain the SHA pin and use a scheduled or
      explicitly maintained bump process. Never fall back to a mutable ref
      such as `@main`. See
      [reference.md](reference.md#stale-reusable-workflow-pins).
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
      fetch needs its own status distinct from pass/fail (e.g. `SCAN_OK`
      vs `LEAKS_FOUND`). Validate response shape: `jq -e '.items | type ==
      "array"'` before trusting "empty"; check `type == "number"` on count
      fields before `<=` (null passes). Some endpoints also return
      `incomplete_results: true` on timeout - check API-specific
      completeness fields. See
      [reference.md](reference.md#documented-endpoints).
- [ ] **Check `steps.<id>.outcome`, not just `.outputs.*`, when aggregating
      status.** A skipped step's outputs are empty; `|| 'false'` fallbacks
      on empty outputs read as clean. Revisit the gate every time a new
      step is added between detection and notification.
- [ ] **Validate untrusted numeric input before use in date/arithmetic.**
      `0`, negative, or non-numeric text in `date -d "${N} hours ago"`
      silently produces wrong results. Cap upper bounds too when the scale
      interacts with known limits (e.g. unpaginated `per_page=100`).
- [ ] **`curl` exits `0` on 4xx/5xx by default**, and manual HTTP-code
      checking doesn't cover transport failures (DNS, TLS). Both gaps need
      closing. See [reference.md](reference.md#curl-failure-handling).
- [ ] **Inside a composite action, pass data between its own steps via
      `steps.<id>.outputs`, not `$GITHUB_ENV`.** An env var written there
      leaks into every later step of the *calling* job (not just this
      action's own steps) and collides if the action runs more than once in
      the same job.
- [ ] **Escape `|` when interpolating dynamic data (log paths, rule IDs,
      etc.) into a Markdown table** built via `jq`/`echo` for a job summary
      or issue body - an unescaped pipe in the data breaks the rendered
      table.
- [ ] **Clean up local secrets via `trap ... EXIT`**, not just remote
      deletion - includes *derived* files (e.g. gitleaks JSON embeds
      matched values). Never point downstream reporting at raw reports;
      produce a sanitized copy for summaries/issue bodies.
- [ ] **A per-item batch failure must abort, not skip-and-continue**, when a
      later step trusts the entire result. See
      [reference.md](reference.md#fail-loud-on-per-item-batch-failures).
- [ ] **Track detection and remediation as separate outcomes**
      (e.g. `PURGE_OK` alongside `LEAKS_FOUND`). See
      [reference.md](reference.md#detection-vs-remediation-status).
- [ ] **Don't equate "credential found" with "workflow failed" in
      notifications.** A post-run log scanner (or similar) can find secrets
      in an otherwise-green e2e run; posting Slack/`notify-slack` as
      `status: failure` makes the *e2e* look FAILED even when
      `github.event.workflow_run.conclusion` was `success`, which blocks
      blessing. Keep real failures (scan hard-fail, purge failed, couldn't
      fetch logs) as `failure` in the Slack notification payload, and use a
      distinct `warning` (or equivalent) in that payload when detection
      succeeded *and* remediation succeeded - GitHub Actions step
      conclusions don't have a native `warning` state, so this applies to
      the notification content, not the step outcome. Same spirit as
      detection-vs-remediation - the notify status is yet another axis.
- [ ] **Never re-echo diagnostics into the job console.** `grep -C` /
      `cat` / `$GITHUB_STEP_SUMMARY` on gathered artifacts re-exposes
      secrets into *workflow run logs*. Write only a **redacted/sanitized**
      dump to the artifact (never raw secret-bearing content); print a
      count/pointer in the job log. See
      [reference.md](reference.md#dont-re-echo-redacted-diagnostics).
- [ ] **Redact every encoding of a secret.** Base64-encoded payloads
      survive plaintext JSON redaction. Decode each quoted candidate
      (standard + URL-safe) and check for the key; when found, replace the
      original encoded blob with a redaction marker. Prefer JSON parsing
      for structured values; if using regex, `[^"]+` is a starting point
      for double-quoted JSON but misses escaped quotes (`\"`). Avoid
      overly narrow classes like `[A-Za-z0-9+/=]` that miss punctuation.
      Adapt the approach for other contexts (single-quoted, URL-embedded,
      etc.). See
      [reference.md](reference.md#dont-re-echo-redacted-diagnostics).
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

**This checkout is the repo's own tagged source**, not untrusted PR code, so
the classic `workflow_run` privilege-escalation risk doesn't directly apply.
If you adapt this pattern for a workflow triggered by untrusted contributions
(e.g. `pull_request` from forks), never check out or execute contributor code
in the privileged `publish` job. See
[reference.md](reference.md#workflow-run-privilege-escalation).

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

Editing *this skill itself*? Run
[scripts/self-check.sh](scripts/self-check.sh) - it validates embedded
templates/scripts/regexes plus a live `verify-tag-matches-sha.sh` test.
Requires `actionlint` and authenticated `gh` for full coverage (missing
either degrades to a printed `skip`).

## Also applies (enforced automatically, not just for workflows)

Branch from latest upstream main (resolve with `tools/resolve-remotes.sh`),
rebase before pushing with `--force-with-lease`, and add `Assisted-by:`
trailers to AI-assisted commits (never `Co-Authored-By` for AI tools). See
root `AGENTS.md` for the full fork/branch/attribution conventions.

## Additional resources

- [reference.md](reference.md) - semver regex, documented-endpoint gotchas,
  live-testing traps, log-redaction / re-echo pitfalls, and niche
  bash-script pitfalls (IFS joins, shallow submodule clones, run-attempt
  collisions).
- Each component repo's standing rules directory (e.g. `.claude/rules/`,
  `.cursor/rules/` - whichever your agent uses) for the full GitHub Actions
  security/maintainability/bash-safety rules this skill was distilled from.
