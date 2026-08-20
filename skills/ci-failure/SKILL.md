---
name: ci-failure
description: Analyze GitHub Actions CI failures on an OSAC PR — fetches check statuses, reads failure logs, identifies root causes, and suggests fix commands. Delegates Prow E2E failures to /debug-e2e. Use when the user says 'why did CI fail', 'CI is red', 'check CI', or provides a PR with failing checks.
---

# CI Failure Analysis

Investigate why CI checks failed on an OSAC pull request. Fetches GitHub Actions check results, reads failure logs, classifies root causes, and suggests the exact command to fix each failure. Delegates Prow E2E failures to `/debug-e2e`.

## When to Use

- User asks "why did CI fail?" or "CI is red" and provides a PR
- User shares a PR URL with failing checks
- User wants to know what to fix before CI will pass

## Step 1: Parse PR Input

The user provides one of:
- A full GitHub PR URL: `https://github.com/osac-project/fulfillment-service/pull/123`
- A shorthand: `fulfillment-service#123` or `fulfillment-service 123`
- A PR number — if no repo specified, ask which repo

Extract the owner/repo and PR number:

```bash
# From URL: https://github.com/osac-project/fulfillment-service/pull/123
# REPO=osac-project/fulfillment-service  PR_NUMBER=123

# From shorthand: fulfillment-service#123
# REPO=osac-project/fulfillment-service  PR_NUMBER=123
```

The org is always `osac-project` unless the URL says otherwise.

## Step 2: Fetch Check Status

```bash
gh pr checks $PR_NUMBER --repo $REPO --json name,state,bucket,link,description,workflow,startedAt,completedAt
```

Parse the JSON output. Categorize checks by `bucket`:
- `pass` — check succeeded
- `fail` — check failed
- `pending` — check still running
- `skipping` — check skipped
- `cancel` — check cancelled

**Edge cases — handle before continuing:**

| Condition | Action |
|-----------|--------|
| All checks pass | Report "All CI checks are passing on `$REPO#$PR_NUMBER`." and stop. |
| Checks still running | Report which are pending (with elapsed time) and which have passed/failed so far. Analyze any failures that are already complete. |
| No checks found | Report "No CI checks found. Verify the PR URL and that workflows are enabled." and stop. |

## Step 3: Identify Failed Checks

Filter to checks where `bucket` equals `fail`. For each, classify as **GitHub Actions** or **Prow**:

**Prow check detection** — a check is a Prow job if ANY of:
- Name matches `pull-ci-osac-project-*`
- Name matches `rehearse-*-pull-ci-osac-project-*`
- Link contains `prow.ci.openshift.org`

All other failed checks are GitHub Actions checks.

If there are no GitHub Actions failures (only Prow), skip to Step 6.

## Step 4: Fetch GitHub Actions Failure Logs

For each failed GitHub Actions check, extract the workflow run ID from the `link` field:

```bash
# link format: https://github.com/osac-project/<repo>/actions/runs/<RUN_ID>/job/<JOB_ID>
RUN_ID=$(echo "$LINK" | grep -oE 'runs/[0-9]+' | cut -d/ -f2)
```

**Important:** Multiple failed checks may share the same run ID (they are jobs in the same workflow). Group by run ID to avoid fetching logs twice.

For each unique run ID, fetch the failed step logs:

```bash
gh run view $RUN_ID --repo $REPO --log-failed 2>&1 | tail -200
```

If the output is very long, focus on the last 100-200 lines per failed job — the actual error is almost always at the end. Look for error markers: `FAIL`, `Error`, `error:`, `panic:`, `fatal:`, `FAILED`, `exit code`.

If `--log-failed` returns nothing useful, try the verbose view:

```bash
gh run view $RUN_ID --repo $REPO -v
```

## Step 5: Analyze and Classify Failures

For each failed check, identify the root cause using the logs and this reference table:

| Check Name Pattern | Category | Common Root Cause | Fix Command |
|---|---|---|---|
| `pre-commit` / `Check pre-commit` | Lint/Format | Whitespace, trailing newline, YAML lint, file size | `pre-commit run --all-files` |
| `Check Python code` / `ruff` | Python Lint | Import order, unused import, style violation | `uv run ruff check --fix` |
| `Check Go code` / `golangci-lint` | Go Lint | Lint violations, unused vars, error handling | `make lint` or `golangci-lint run` |
| `Check generated code` / `check-generated-code` | Code Gen Drift | Proto changed without regenerating Go code | `buf generate && git diff --exit-code` |
| `Run unit tests` | Test Failure | Assertion failure, panic, timeout | Read test output for failing test name |
| `Build binaries` / `build` / `make build` | Build Failure | Compilation error, missing dependency | Read compiler error message |
| `Run integration tests` | Integration Test | Service startup failure, test assertion | Check uploaded workflow artifacts |
| `Kustomize Build` | Manifest Validation | Invalid kustomization, missing resource | `bash scripts/kustomize-build-all.sh` |
| `Check image tags` | Image Tag Drift | Image tag doesn't match submodule commit | `bash scripts/sync-image-tags.sh --fix` |
| `Check AuthConfig Rego` | Rego Policy Drift | Overlay Rego doesn't match base | `python3 scripts/sync-authconfig-rego.py --fix` |
| `Helm Lint` / `helm-crds-sync` | Helm Validation | CRD template out of sync, chart lint error | `make check-helm-crds` or `helm lint charts/...` |
| `ansible-lint` | Ansible Lint | FQCN missing, task name missing, YAML style | `ansible-lint` |
| `Lint` (osac-ui) | Frontend Lint | ESLint/Prettier violations, i18n sync | `pnpm lint` |
| `build-image` | Image Build | Dockerfile error, missing dependency | Read docker build error |
| `execution-environment` | EE Build | Ansible EE build failure | Check EE definition and dependencies |

For each failed check, extract:
1. The specific error lines from the logs (not the full log — just the relevant error)
2. The category from the table above
3. The fix command

## Step 6: Handle Prow Failures

If any Prow checks were identified in Step 3, automatically investigate them using the `/debug-e2e` skill.

For each failed Prow check, invoke the skill:

```
Skill tool call:
  skill: debug-e2e
  args: <prow-link>
```

Where `<prow-link>` is the Prow job URL from the check's `link` field (e.g., `https://prow.ci.openshift.org/view/gs/...`).

Include the `/debug-e2e` findings in the final report under a "Prow E2E Failures" section. Do **not** duplicate the Prow log-reading logic — let the skill handle artifact fetching, log reading, and failure classification, then incorporate its results.

## Step 7: Report

Present a structured summary:

```markdown
## CI Failure Analysis: <repo>#<PR>

### Summary
- Total checks: N
- Passed: N | Failed: N | Pending: N

### Failed Checks

#### 1. <Check Name> — <Category>
**Workflow:** <workflow name>
**Root cause:** <one-line description>
**Error:**
\```
<key error lines from logs — 5-15 lines max>
\```
**Fix:** `<command to run>`

#### 2. <Check Name> — <Category>
...

### Prow E2E Failures
<if any — include /debug-e2e findings: failed step, root cause, evidence, recommendation>

### Next Steps
1. <ordered list of fix actions, most impactful first>
```

Order the next steps so that upstream fixes come first (e.g., fix compilation before worrying about lint).

## Quick Reference

| Step | Action | Gate |
|------|--------|------|
| 1 | Parse PR input | Valid repo + PR number |
| 2 | Fetch check status | Handle all-pass / pending / empty |
| 3 | Identify failed checks | Classify GH Actions vs Prow |
| 4 | Fetch failure logs | Group by run ID, tail output |
| 5 | Analyze failures | Classify root cause, suggest fix |
| 6 | Handle Prow failures | Delegate to /debug-e2e |
| 7 | Report | Structured summary with fix commands |

## Common Issues

### `gh` not authenticated

```bash
gh auth status
gh auth login
```

### PR from a personal fork

If the PR is on a fork, use the full repo path:

```bash
gh pr checks $PR --repo <fork-owner>/<repo> ...
```

### Log output is too large

Use `tail` to limit output. The actual error is almost always in the last 100 lines. If needed, fetch a specific job's log:

```bash
gh run view $RUN_ID --repo $REPO --log-failed -j <JOB_ID>
```

### Check appears failed but has no logs

Some checks (like required status contexts from external systems) don't have GitHub Actions logs. Report the check name and status, and note that logs are not available via `gh`.
