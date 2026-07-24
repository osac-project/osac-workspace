# Investigation Steps

## Step 0: Differential Analysis (Mandatory First Step)

Before reading any logs, check whether this failure is unique to this PR or widespread. This step directs your entire investigation.

```bash
# Recent runs for this workflow — look at conclusion column
gh run list -R osac-project/<repo> -w e2e-vmaas-full-install-caller.yml -L 20 --json databaseId,conclusion,startedAt,headBranch

# Compare: how many recent runs failed vs succeeded?
gh run list -R osac-project/<repo> -w e2e-vmaas-full-install-caller.yml -L 20 --json conclusion --jq 'group_by(.conclusion) | map({conclusion: .[0].conclusion, count: length})'
```

## Step 1: Identify the Failing Job

The user will provide one of:
- A GitHub Actions run URL (e.g., `https://github.com/osac-project/<repo>/actions/runs/<run-id>`)
- A PR number where tests failed

**If given a PR number:**
```bash
gh pr checks <PR> --repo osac-project/<repo> | grep -i fail
```

## Step 2: Fetch Build Status and Identify the Failed Step

```bash
gh run view <run-id> -R osac-project/<repo>
```

This shows all jobs and steps with their status. Identify which step failed and its timing.

For detailed step info:
```bash
gh run view <run-id> -R osac-project/<repo> --json jobs --jq '.jobs[] | select(.conclusion == "failure") | {name, conclusion, steps: [.steps[] | select(.conclusion == "failure") | {name, conclusion}]}'
```

## Step 3: Read the Build Log

Fetch the full job log:
```bash
gh api /repos/osac-project/<repo>/actions/jobs/<job-id>/logs > /tmp/debug/build-log.txt
```

Or view the log for a specific run:
```bash
gh run view <run-id> -R osac-project/<repo> --log > /tmp/debug/build-log.txt
```

Look for:
- Which step failed (step name and exit code)
- Timing information
- Whether failure was in boot, refresh, test, or gather phase

## Step 4: Download and Read Gathered Artifacts

Download the osac-logs artifact from the GitHub Actions run:

```bash
mkdir -p /tmp/debug/<run-id>/fail
gh run download <run-id> -R osac-project/<repo> -D /tmp/debug/<run-id>/fail
```

Artifact names follow this pattern:
- VMaaS full-install: `osac-logs-full-install-<run-id>`
- CaaS: `caas-netris-artifacts`

For differential analysis, find a passing run and download its artifacts too:
```bash
# Find a recent passing run
gh run list -R osac-project/<repo> -w e2e-vmaas-full-install-caller.yml --status success -L 1 --json databaseId --jq '.[0].databaseId'

mkdir -p /tmp/debug/<run-id>/pass
gh run download <passing-run-id> -R osac-project/<repo> -D /tmp/debug/<run-id>/pass

# Compare
diff /tmp/debug/<run-id>/fail/osac-logs*/events.txt /tmp/debug/<run-id>/pass/osac-logs*/events.txt
```

Then use grep/find/cat on the local files. The artifact directory structure contains pod logs, events, deployments, CRs, and sub-directories for keycloak, ansible-aap, aap-jobs, caas, cnv, and storage.

**AAP job stdout files may be redacted.** If redacted, find the failure reason in operator logs, events, or AAP playbook source code.

## Step 5: Deep Investigation — Fan Out If Needed

When gathered artifacts don't tell the full story:
- Clone repos and read source code to understand expected behavior
- Cross-reference with passing jobs — find a passing run and compare the same files
- Use sub-agents for parallel investigation across pod logs, test code, and operator code

## Step 6: Classify and Suggest Fix

When suggesting fixes, prefer changes that work on top of existing snapshots — refresh script, Helm values, CI workflow steps, or component code fixes. Re-snapshotting is expensive (~2 hours manual work). Only suggest it when the snapshot is fundamentally broken OR when the alternative fixes would be hacky workarounds — if re-snapshotting is the clean, correct long-term solution, say so.

## Step 7: Report

Present findings with **evidence, not speculation**. Every claim needs a log line, a timestamp, or a code reference backing it.

If you cannot determine the root cause with certainty, say so explicitly and list what you investigated, what you ruled out, and what additional information would be needed.
