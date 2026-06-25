---
name: create-pr
description: Create a pull request on an OSAC component repo using the fork-based workflow. Runs repo-specific validation (build, test, lint), pushes to the developer's fork remote, and opens a PR against origin/main with proper title format. Use when the user says 'create PR', 'open PR', 'submit for review', 'push and create PR', or when finishing a feature branch.
---

# Create Pull Request

Create a pull request on an OSAC component repository using the fork-based workflow.

**Announce at start:** "Using the create-pr skill to validate and submit a PR."

## Prerequisites

- `gh` CLI authenticated (`gh auth status`)
- A `fork` remote configured (developer's fork — the push target)
- Commits on a feature branch, not `main`

## Step 1: Detect Context

Determine which component repo you're in and gather branch state.

```bash
REPO_DIR=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_DIR")
BRANCH=$(git branch --show-current)
```

**Gate checks — stop if any fail:**

| Check | Command | Fail action |
|-------|---------|-------------|
| Not on main | `[[ "$BRANCH" != "main" ]]` | Stop: "You're on main. Create a feature branch first." |
| Fork remote exists | `git remote get-url fork` | Stop: "No `fork` remote. Add one: `git remote add fork git@github.com:<user>/\<repo>.git`" |
| Has commits ahead of main | `git log main..HEAD --oneline` | Stop: "No commits ahead of main. Nothing to submit." |
| Clean working tree | `git status --porcelain` | Stop: "Uncommitted changes detected. Commit or stash before proceeding." |

## Step 2: Run Validation

Run the repo-specific checks **before** pushing. Read the component's CLAUDE.md if unsure which commands apply.

### fulfillment-service

```bash
gofmt -s -w . && git diff --exit-code
buf generate && git diff --exit-code
go build ./...
ginkgo run -r internal
```

### osac-operator

```bash
make fmt && git diff --exit-code
make lint
make build
make test
make manifests generate && git diff --exit-code
```

### osac-aap

```bash
ansible-lint
```

### osac-installer

```bash
# Always run:
bash scripts/kustomize-build-all.sh
```

If submodules changed (`git diff main --submodule | grep -q Submodule`), also run:

```bash
bash scripts/sync-image-tags.sh
python3 scripts/sync-authconfig-rego.py
```

The sync scripts support `--fix` to auto-correct drift. All scripts require submodules to be initialized (`git submodule update --init --recursive`).

### Other repos

Read the component's CLAUDE.md or Makefile for the correct validation sequence.

**If any check fails:** Stop. Show the failure output. Do not proceed to push.

**If all checks pass:** Continue to Step 3.

## Step 3: Check Test Coverage

Analyze the diff to detect production code changes that lack corresponding test changes. This is **advisory only** — it warns but does not block PR creation.

Run:

```bash
git diff main..HEAD --name-only --diff-filter=AMR
```

Classify each changed file using the repo-specific rules below:

### File Classification

| Repo | Production files | Test files | Excluded (skip) |
|------|-----------------|------------|-----------------|
| **fulfillment-service** | `*.go` not `_test.go` | `*_test.go` | `internal/api/`, `*.pb.go`, `migrations/` |
| **osac-operator** | `*.go` not `_test.go` | `*_test.go` | `api/v1alpha1/zz_generated*`, `config/` |
| **osac-aap** | `roles/*/tasks/*.yml`, `plugins/**/*.py` | `molecule/*/`, `tests/`, `test_*.py` | `meta/`, `docs/` |
| **osac-installer** | Skip this check entirely | — | — |

For each production file in the diff, check if a corresponding test file also appears in the diff. Matching rules:

- **Go:** `foo.go` → `foo_test.go` in the same directory
- **Ansible:** `roles/<role>/tasks/*.yml` → `molecule/<role>/` or `tests/` directory has changes

**If gaps exist**, print a warning and continue:

```
⚠️  Test coverage gaps detected:

| Production file changed | Expected test file |
|------------------------|--------------------|
| internal/servers/foo_server.go | internal/servers/foo_server_test.go |

These files were added or modified without corresponding test changes.
This is a warning — proceeding with PR creation.
```

**If no gaps**, print: "✅ Test coverage looks good — all changed production files have corresponding test changes."

**Always continue to Step 4** regardless of the result.

## Step 4: Push to Fork

Always push to `fork`, never to `origin`.

```bash
git push -u fork "$BRANCH"
```

If push fails due to diverged history, do not force-push automatically. Show the push error to the user and ask them for explicit instructions on how to proceed.

## Step 5: Determine PR Title

The PR title must include the Jira ticket key if one exists.

**Format:** `<TICKET-KEY>: <short description>`

Examples:
- `OSAC-853: add AAP presubmit e2e-vmaas job`
- `MGMT-24256: add E2E test skill stubs`

Extract the ticket key from the branch name if it follows the convention (`feat/OSAC-123`, `fix/MGMT-456`):

```bash
TICKET=$(echo "$BRANCH" | grep -oE '(OSAC|MGMT)-[0-9]+' || true)
```

If no ticket key is found, ask: "Is there a Jira ticket for this work? (e.g., OSAC-123)"

If none, omit the prefix — just use a descriptive title.

## Step 6: Create PR

Determine the upstream repo from the `origin` remote:

```bash
UPSTREAM=$(gh repo view $(git remote get-url origin) --json nameWithOwner -q .nameWithOwner)
FORK_OWNER=$(gh repo view $(git remote get-url fork) --json owner -q .owner.login)
```

Construct the title from the ticket key and a short description (ask the user if unclear):

```bash
PR_TITLE="${TICKET:+$TICKET: }<short description>"
```

Create the PR from the fork to upstream:

```bash
gh pr create \
  --repo "$UPSTREAM" \
  --head "$FORK_OWNER:$BRANCH" \
  --base main \
  --title "$PR_TITLE" \
  --body "$(cat <<'EOF'
## Summary
<1-3 bullet points describing what changed and why>

## Jira
<link to Jira ticket, or "N/A">

## Test plan
- [ ] <verification steps taken>
- [ ] Unit tests pass
- [ ] Lint/format checks pass

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

## Step 7: Report Result

Display the PR URL as a clickable markdown link:

```text
PR created: [#<number>](<url>)
```

If cross-repo PRs exist, remind: "Link related PRs in the description (e.g., 'Depends on fulfillment-service#123')."

## Quick Reference

| Step | What | Gate |
|------|------|------|
| 1 | Detect context | Not on main, fork exists, commits ahead |
| 2 | Run validation | All checks pass |
| 3 | Check test coverage | Advisory warning (does not block) |
| 4 | Push to fork | Push succeeds |
| 5 | Determine title | Jira key included if available |
| 6 | Create PR | PR created against origin/main |
| 7 | Report | Show PR URL |

## Common Issues

### No `fork` remote

```bash
git remote add fork git@github.com:<your-username>/<repo>.git
```

### `gh pr create` fails with "not authenticated"

```bash
gh auth status
gh auth login
```

### Push rejected (branch exists on fork)

Do not force-push automatically. Show the push error to the user and ask them for explicit instructions on how to proceed.

### PR already exists

```bash
gh pr list --repo <upstream> --head <fork-owner>:<branch>
```

If a PR already exists, show its URL instead of creating a duplicate.

## Red Flags

**Never:**
- Push to `origin` — always use `fork`
- Create a PR from `main`
- Skip validation checks
- Force-push without user confirmation
- Create a PR with failing tests

**Always:**
- Run repo-specific validation first
- Push to `fork` remote
- Include Jira ticket key in title when available
- Check for existing PRs before creating duplicates
