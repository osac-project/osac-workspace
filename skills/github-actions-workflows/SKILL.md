---
name: github-actions-workflows
description: Create or edit GitHub Actions workflow files (.github/workflows/*.yaml) with security and maintainability best practices applied from the start, instead of discovering them one CodeRabbit review round at a time. Covers least-privilege permissions, SHA-pinned actions, injection-safe env-var handling, semver/tag validation, force-push-safe release gating, and extracting shared bash into scripts. Use when creating a new workflow, adding a job/step to an existing one, wiring up a workflow_run gate, or setting up any tag/release automation.
---

# GitHub Actions Workflows

Every checklist item below came from an actual multi-round CodeRabbit review
cycle on OSAC-2185 (5 repos, 4 review rounds each). Apply them proactively -
don't wait for a reviewer to find them.

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
