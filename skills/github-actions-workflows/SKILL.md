---
name: github-actions-workflows
description: Create or edit GitHub Actions workflow files (.github/workflows/*.yaml) with security and maintainability best practices applied from the start, instead of discovering them one CodeRabbit review round at a time. Covers least-privilege permissions, SHA-pinned actions, injection-safe env-var handling, semver/tag validation, force-push-safe release gating, and extracting shared bash into scripts. Use when creating a new workflow, adding a job/step to an existing one, wiring up a workflow_run gate, or setting up any tag/release automation.
globs:
  - ".github/workflows/*.yaml"
  - ".github/workflows/*.yml"
metadata:
  version: "0.1.0"
---

# GitHub Actions Workflows

Checklist items below came from multi-round CodeRabbit reviews of release
gating and credential-scanning workflows. Apply proactively. **Read the
linked [reference.md](reference.md) section before implementing** — detail
lives there so this file stays under the skillsaw context budget.

## Checklist

- [ ] **`permissions:`** least privilege on every job; metadata-only →
      `permissions: {}`. Put zizmor rationale on the **same line** as each
      scope (`contents: read  # checkout only`) — see
      [reference.md](reference.md#zizmor-permission-comments).
- [ ] **No `${{ }}` in `run:` blocks.** Route via `env:` / `"$VAR"`. OK in
      `outputs:` / `if:` / `with:`.
- [ ] **Pin every action to a full commit SHA** (+ update mechanism for
      reusable workflows). Never `@main`. See
      [reference.md](reference.md#stale-reusable-workflow-pins).
- [ ] **`persist-credentials: false`** on checkout unless the job pushes.
- [ ] **Validate tags with real semver** (reject `v01.2.3`, and `+build` if
      used as image tags). Regex:
      [reference.md](reference.md#semver-regex).
- [ ] **Gate release/publish on upstream success** with `workflow_run` +
      guard job — full template:
      [reference.md](reference.md#workflow_run-gate-pattern).
- [ ] **Use documented REST endpoint forms.** See
      [reference.md](reference.md#documented-endpoints).
- [ ] **Capture command-substitution before `read`** under `set -e`.
- [ ] **Extract repeated bash into `.github/scripts/`** (`chmod +x`). See
      [reference.md](reference.md#shared-scripts).
- [ ] **`concurrency` + `cancel-in-progress: true`** on PR workflows
      (`group: …-${{ github.event.pull_request.number || github.ref }}`).
- [ ] **PR-checkout enforcement scripts are not tamper-proof.** Prefer
      base-branch trusted copy / CODEOWNERS / protected reusable + required
      check; fail closed. See
      [reference.md](reference.md#pr-controlled-enforcement-scripts).
- [ ] **Validate before commit:** `actionlint` (0 errors) + `shellcheck`
      (or `bash -n`); test regex/scripts locally (Verification below).
- [ ] **Lint exemptions:** match markers on the *raw* line if a stripper
      removes comments; prefer YAML-aware parsing for security exemptions.
- [ ] **`[]},[:space:]]` is valid ERE** — CodeRabbit false-positive; test
      before "fixing."
- [ ] **Sigstore/cosign** out of scope for the current change → tell the
      user; don't silently skip.
- [ ] **Alert/notify/`upload-artifact` steps need `always()` (or
      `failure()`), not bare `if:`** — bare conditions AND `success()` and
      skip after hard fail. See
      [reference.md](reference.md#always-for-notify-and-evidence).
- [ ] **Don't collapse "couldn't check" into "clean."** Separate
      `SCAN_OK` / `LEAKS_FOUND` (and similar); validate jq shapes /
      completeness fields. See
      [reference.md](reference.md#incomplete-must-not-look-clean).
- [ ] **Aggregate with `steps.<id>.outcome`**, not only `.outputs.*`
      (skipped step outputs look clean via `|| 'false'`).
- [ ] **Validate untrusted numerics** before `date`/arithmetic; cap against
      API pagination limits.
- [ ] **`curl`:** handle 4xx/5xx *and* transport errors; retry 429/5xx;
      treat idempotent DELETE `404` as success. See
      [reference.md](reference.md#curl-failure-handling).
- [ ] **Composite steps: use `steps.<id>.outputs`, not `$GITHUB_ENV`.**
- [ ] **Composite cross-repo paths: use `GITHUB_ACTION_PATH`**, never
      `$GITHUB_WORKSPACE`, for sibling scripts/jq. See
      [reference.md](reference.md#composite-action-path-resolution).
- [ ] **Markdown tables/PR comments:** strip `\r`/`\n`, HTML-escape `&<>`,
      escape `|`; prefer one shared jq module. See
      [reference.md](reference.md#markdown-cell-sanitization).
- [ ] **Best-effort side effects** (PR comment after purge) must warn, not
      fail the job. See
      [reference.md](reference.md#best-effort-side-effects).
- [ ] **`trap ... EXIT` for local secrets** (incl. derived gitleaks JSON);
      never point summaries at raw reports — sanitized copy only.
- [ ] **Atomic writes** for `status.env` / `findings.json` (`mktemp` +
      `mv`) so a failed jq/trap path never clobbers good output. See
      [reference.md](reference.md#atomic-status-writes).
- [ ] **Fail loud on per-item batch failures** when a later upload trusts
      the whole tree. See
      [reference.md](reference.md#fail-loud-on-per-item-batch-failures).
- [ ] **Scan Actions artifacts as well as run logs** when hunting leaks;
      stage → redact → `mv` into the evidence tree. See
      [reference.md](reference.md#scan-logs-and-artifacts).
- [ ] **Track detection vs remediation** (`LEAKS_FOUND` / `PURGE_OK`); only
      claim uploads when `steps.upload.outcome == 'success'`. See
      [reference.md](reference.md#detection-vs-remediation-status).
- [ ] **Notify status ≠ e2e conclusion.** Credential-found + purge-ok →
      Slack `warning`, not `failure` that blocks blessing. See
      [reference.md](reference.md#detection-vs-remediation-status).
- [ ] **Never re-echo diagnostics** into the job console; redact every
      encoding. See
      [reference.md](reference.md#dont-re-echo-redacted-diagnostics).
- [ ] **`workflow_dispatch` branch locks:** GitHub Environment deployment
      branches, not `if: github.ref == 'refs/heads/main'`. See
      [reference.md](reference.md#workflow_dispatch-branch-restriction).

## The workflow_run gate pattern

Highest-value release pattern: gate publish on a sibling build's
`workflow_run` success + SHA re-check, not independent `push: tags:`.
**Read and copy the full template from**
[reference.md](reference.md#workflow_run-gate-pattern). Also install
[scripts/verify-tag-matches-sha.sh](scripts/verify-tag-matches-sha.sh)
(`chmod +x`). For untrusted contributors see
[reference.md](reference.md#workflow_run-privilege-escalation); for tag
moves see [reference.md](reference.md#tag-immutability).

## Verification before committing

1. `actionlint path/to/workflow.yaml` — 0 errors.
2. `shellcheck path/to/script.sh` (or `bash -n`).
3. Test new regexes locally (match/reject matrix).
4. `workflow_run` / tag-release changes need a live fork e2e — see
   [reference.md](reference.md#live-testing-gotchas).

Editing *this skill*? Run [scripts/self-check.sh](scripts/self-check.sh).
Missing `actionlint` or unauthenticated `gh` prints `skip` for those
checks; the script can still exit 0 — treat skips as incomplete coverage,
not a full pass.

## Also applies (enforced automatically, not just for workflows)

Branch from latest upstream main (resolve with `tools/resolve-remotes.sh`),
rebase before pushing with `--force-with-lease`, and add `Assisted-by:`
trailers to AI-assisted commits (never `Co-Authored-By` for AI tools). See
root `AGENTS.md` for the full fork/branch/attribution conventions.

## Additional resources

- [reference.md](reference.md) — full templates, curl/retry, markdown
  sanitization, composite paths, redaction, live-testing traps, niche bash.
- Component-repo standing rules (`.claude/rules/`, `.cursor/rules/`, etc.).
