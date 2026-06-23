---
name: create
description: Validate, push, and open a pull request on a component repo.
---

# Create Pull Request Skill

You are a PR publisher. Your job is to validate a component repo's branch,
push it to the developer's fork, and open a pull request against upstream.

## Your Role

Run repo-specific validation (build, test, lint), push to the `fork` remote,
and create a PR with proper title format. This phase adapts the project's
fork-based workflow for multi-repo workspaces.

## Critical Rules

- **Never push to `origin`.** Always push to the `fork` remote.
- **All validation must pass** before pushing — repo-specific checks are non-skippable.
- **Force-push requires** explicit user confirmation.
- **Feature branch required** — PRs cannot be created from `main`.

## Process

### Step 1: Resolve Component

The controller provides the component directory. Change into it:

```bash
cd {component-dir}
```

Read the component's `CLAUDE.md` if it exists — it contains repo-specific
validation commands.

### Step 2: Gate Checks

Run these checks and stop if any fail:

| Check | Command | Fail action |
|-------|---------|-------------|
| Not on main | `git branch --show-current` | Stop: "You're on main. Create a feature branch first." |
| Fork remote exists | `git remote get-url fork` | Stop: "No `fork` remote. Add one: `git remote add fork git@github.com:<user>/<repo>.git`" |
| Commits ahead of main | `git log main..HEAD --oneline` | Stop: "No commits ahead of main." |
| Clean working tree | `git status --porcelain` | Stop: "Uncommitted changes. Commit or stash first." |

### Step 3: Run Validation

Run the repo-specific checks. Read the component's `CLAUDE.md` to determine
which commands apply. Common patterns:

**fulfillment-service:**

```bash
gofmt -s -w . && git diff --exit-code
buf generate && git diff --exit-code
go build ./...
ginkgo run -r internal
```

**osac-operator:**

```bash
make fmt && git diff --exit-code
make lint
make build
make test
make manifests generate && git diff --exit-code
```

**osac-aap:**

```bash
ansible-lint
```

**osac-installer:**

```bash
bash scripts/kustomize-build-all.sh
```

If submodules changed (`git diff main --submodule | grep -q Submodule`), also run:

```bash
git submodule update --init --recursive
bash scripts/sync-image-tags.sh
python3 scripts/sync-authconfig-rego.py
```

The sync scripts support `--fix` to auto-correct drift.

For other repos, read the component's `CLAUDE.md` or `Makefile`.

If any check fails, stop and show the failure output. Do not proceed to push.

### Step 4: Push to Fork

```bash
git push -u fork "$(git branch --show-current)"
```

If push fails due to diverged history, show the error and ask the user
how to proceed. Do not force-push automatically.

### Step 5: Determine PR Title

Extract the Jira ticket key from the branch name:

```bash
TICKET=$(git branch --show-current | grep -oE '(OSAC|MGMT)-[0-9]+' || true)
```

Format: `<TICKET-KEY>: <short description>`

If no ticket key is found, ask the user if there is a Jira ticket. If none,
use a descriptive title without a prefix.

### Step 6: Check for Existing PR

Extract the fork owner from the remote URL (works for both SSH and HTTPS):

```bash
FORK_URL=$(git remote get-url fork)
FORK_OWNER=$(echo "$FORK_URL" | sed -E 's|.*[:/]([^/]+)/[^/]+(\.git)?$|\1|')
UPSTREAM=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh pr list --repo "$UPSTREAM" --head "$FORK_OWNER:$(git branch --show-current)" --json number,url
```

If a PR already exists, show its URL instead of creating a duplicate.

### Step 7: Create PR

Use the `FORK_OWNER` and `UPSTREAM` values from Step 6:

```bash
gh pr create \
  --repo "$UPSTREAM" \
  --head "$FORK_OWNER:$(git branch --show-current)" \
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

### Step 8: Report to User

Display the PR URL:

```text
PR created: [#<number>](<url>)
```

If cross-repo PRs exist, remind: "Link related PRs in the description
(e.g., 'Depends on fulfillment-service#123')."

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

Do not force-push automatically. Show the push error and ask the user
how to proceed.

### PR already exists

Check before creating:

```bash
gh pr list --repo "$UPSTREAM" --head "$FORK_OWNER:$(git branch --show-current)" --json number,url
```

If a PR already exists, show its URL instead of creating a duplicate.

## Output

- A pull request on the upstream repository

## When This Phase Is Done

Report:
- The PR URL
- What validation was run
- The PR title used

Then **re-read the controller** (`controller.md`) for next-step guidance.
