---
name: create-pr
description: Create a PR on an OSAC component repo (including the osac mono-repo, which may need per-component validation for multiple touched components in one pass) using the fork-based workflow. Runs repo-specific validation (build, test, lint), pushes to the developer's push remote, and opens a PR against the upstream repo with proper title format. Use when the user says 'create PR', 'open PR', 'submit for review', 'push and create PR', or when finishing a feature branch.
metadata:
  version: "0.1.0"
---

# Create Pull Request

Create a PR on an OSAC component repo using the fork-based workflow.

**Announce at start:** "Using the create-pr skill to validate and submit a PR."

## Prerequisites

- `gh` CLI authenticated (`gh auth status`)
- A push remote configured (developer's personal repo — the push target)
- Commits on a feature branch, not `main`
- `tools/resolve-remotes.sh` available (run from `osac-workspace`)

## Step 1: Detect Context

Determine which component repo you're in and gather branch state.

```bash
REPO_DIR=$(git rev-parse --show-toplevel)
BRANCH=$(git branch --show-current)
```

**Resolve remote names** before deriving the repo name or running gate checks:

```bash
WORKSPACE_ROOT=$(cd "$REPO_DIR/.." && git rev-parse --show-toplevel 2>/dev/null || echo "$REPO_DIR/..")
_resolve_out=$("${WORKSPACE_ROOT}/tools/resolve-remotes.sh" "$REPO_DIR") || {
  echo "Failed to resolve remotes. Run tools/resolve-remotes.sh --print to diagnose."
  exit 1
}
eval "$_resolve_out"
```

This sets `$UPSTREAM_REMOTE` (the osac-project remote) and `$PUSH_REMOTE` (developer's push target). Run `tools/resolve-remotes.sh --print` to see current detection.

```bash
# Derive from the resolved upstream remote, not $(basename "$REPO_DIR") -- a
# worktree's directory name (e.g. ../osac-feature-branch, per
# cross-repo-workflow.md) doesn't match the repo name, which would silently
# skip mono-repo component detection below. Also not remote.origin.url
# directly -- resolve-remotes.sh already found the real upstream remote by
# URL/org, not by assuming it's named "origin".
REPO_NAME=$(git -C "$REPO_DIR" remote get-url "$UPSTREAM_REMOTE")
REPO_NAME="${REPO_NAME##*/}"
REPO_NAME="${REPO_NAME%.git}"
```

**Gate checks — stop if any fail:**

| Check | Command | Fail action |
|-------|---------|-------------|
| Not on main | `[[ "$BRANCH" != "main" ]]` | Stop: "You're on main. Create a feature branch first." |
| Push remote exists | `git remote get-url "$PUSH_REMOTE"` | Stop: "No push remote detected. Run `tools/resolve-remotes.sh --print` to diagnose. You may need to add one: `git remote add fork git@github.com:<user>/\<repo>.git`" |
| Has commits ahead of main | `git log main..HEAD --oneline` | Stop: "No commits ahead of main. Nothing to submit." |
| Clean working tree | `git status --porcelain` | Stop: "Uncommitted changes detected. Commit or stash before proceeding." |

### Mono-repo component detection

`osac` is a mono-repo containing `fulfillment-service`, `osac-operator`,
`osac-aap`, `osac-installer`, `bare-metal-fulfillment-operator`, and
`osac-csi-driver` as subdirectories — a single PR can touch more than one of
them. When `$REPO_NAME` is `osac`, detect which subdirectories this branch
actually touches instead of assuming a single component:

```bash
# Keep the (fulfillment-service|osac-operator|osac-aap|osac-installer|
# bare-metal-fulfillment-operator|osac-csi-driver) list in sync with
# bootstrap.sh's MERGED_COMPONENTS array and Step 3's File Classification
# table below if a future component merges into osac or one of these splits
# out.
if [[ "$REPO_NAME" == "osac" ]]; then
  # Split the diff and the filter into two steps: a `git diff` failure must
  # still propagate under `set -e`/`pipefail`, but "no merged-component
  # subdirectory touched" is a valid, empty-string-producing outcome — awk
  # exits 0 on zero matching lines, so no trailing `|| true` is needed (which
  # would otherwise mask a genuine `git diff` failure too).
  CHANGED_PATHS=$(git diff main..HEAD --name-only)
  TOUCHED_COMPONENTS=$(printf '%s\n' "$CHANGED_PATHS" \
    | awk -F/ '$1 ~ /^(fulfillment-service|osac-operator|osac-aap|osac-installer|bare-metal-fulfillment-operator|osac-csi-driver)$/ { print $1 }' \
    | sort -u)
else
  TOUCHED_COMPONENTS="$REPO_NAME"
fi
```

`$TOUCHED_COMPONENTS` may list zero, one, or multiple names. Use it in Steps 2
and 3 to select which per-component block(s) apply — run every matching block,
not just the first. If it's empty because the change is purely doc/config
outside all six subdirectories (e.g. `osac/README.md`), skip the
component-specific parts of Steps 2 and 3. If it's empty but the change
touches root-level files that affect multiple components' builds (e.g.
`osac/go.work`, a root `Makefile`, `.github/workflows/`), don't skip
validation entirely — read `osac`'s own `AGENTS.md`/`CLAUDE.md` for the
correct root-level check (a broken `go.work` can break both
`fulfillment-service` and `osac-operator` builds without either
component's own validation block catching it).

## Step 2: Run Validation

Run the checks for every component in `$TOUCHED_COMPONENTS` **before** pushing
— if it lists more than one, run **every** matching block below in the same
pass; that's the point of one PR covering multiple mono-repo components. Read
the component's CLAUDE.md if unsure which commands apply.

### fulfillment-service

```bash
cd "$REPO_DIR/fulfillment-service"
gofmt -s -w . && git diff --exit-code
buf generate && git diff --exit-code
go build ./...
ginkgo run -r internal
uv run dev.py lint
```

### osac-operator

```bash
cd "$REPO_DIR/osac-operator"
make fmt && git diff --exit-code
make lint
make build
make test
make manifests generate && git diff --exit-code
```

### osac-aap

```bash
cd "$REPO_DIR/osac-aap"
make test
uv run ansible-lint
```

### osac-installer

```bash
cd "$REPO_DIR/osac-installer"
helm dependency build charts/osac/
helm lint charts/osac-operators/
helm lint charts/osac-prereqs/
for f in values/*/values.yaml; do
  helm template osac charts/osac/ --values "$f" \
    --set service.externalHostname=fulfillment-api.example.com \
    --set service.internalHostname=fulfillment-internal-api.example.com \
    > /dev/null
done
```

Reproduces the environment-values templating step of the `helm-lint-installer` job in
`osac`'s `.github/workflows/helm-lint.yaml` — not full CI parity (that job also runs
`ct lint --all --config ct.yaml`, templates `charts/osac/ci/*-values.yaml`, and validates
`values.schema.json` is well-formed JSON; see the workflow for those). `charts/osac/`'s
values schema requires `service.externalHostname`/`internalHostname`, which every real
values file leaves blank for runtime injection, so linting/templating the umbrella chart
needs the same placeholder `--set` overrides CI uses — a bare `helm lint charts/osac/`
(e.g. via `make helm-lint`) fails on schema validation regardless of what the PR actually
changes.

Image tags in `values/*/values.yaml` are unpinned (`latest`) for every mono-repo
component, including `osac-csi-driver` — `scripts/sync-image-tags.sh` was removed
upstream (`OSAC-3367`); there is no sync step to run. Real release tags are set
automatically by `osac`'s own CI at release time, not by a feature PR.

### bare-metal-fulfillment-operator

```bash
cd "$REPO_DIR/bare-metal-fulfillment-operator"
make fmt && git diff --exit-code
make lint
make build
make test
make manifests generate && git diff --exit-code
```

### osac-csi-driver

```bash
cd "$REPO_DIR/osac-csi-driver"
make fmt && git diff --exit-code
make lint
make build
make test
```

No CRDs, so no `make manifests`/`generate` step (unlike `osac-operator` and
`bare-metal-fulfillment-operator`).

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

Classify each changed file using the component-specific rules below — for
`osac`, only apply the row(s) matching `$TOUCHED_COMPONENTS` (path patterns
below already carry the mono-repo subdirectory prefix):

### File Classification

| Component | Production files | Test files | Excluded (skip) |
|------|-----------------|------------|-----------------|
| **fulfillment-service** | `fulfillment-service/**/*.go` not `_test.go` | `fulfillment-service/**/*_test.go` | `fulfillment-service/internal/api/`, `fulfillment-service/**/*.pb.go`, `fulfillment-service/**/migrations/` |
| **osac-operator** | `osac-operator/**/*.go` not `_test.go` | `osac-operator/**/*_test.go` | `osac-operator/api/v1alpha1/zz_generated*`, `osac-operator/config/` |
| **osac-aap** | `osac-aap/collections/ansible_collections/osac/**/roles/**/tasks/*.yml`, `osac-aap/collections/ansible_collections/osac/**/plugins/**/*.py` | `osac-aap/tests/unit/**`, `osac-aap/tests/integration/targets/**` | `osac-aap/collections/ansible_collections/osac/**/meta/`, `osac-aap/docs/` |
| **osac-installer** | Skip this check entirely — Helm charts/values, no unit-testable production/test file split | — | — |
| **bare-metal-fulfillment-operator** | `bare-metal-fulfillment-operator/**/*.go` not `_test.go` | `bare-metal-fulfillment-operator/**/*_test.go` | `bare-metal-fulfillment-operator/api/v1alpha1/zz_generated*`, `bare-metal-fulfillment-operator/config/` |
| **osac-csi-driver** | `osac-csi-driver/**/*.go` not `_test.go` | `osac-csi-driver/**/*_test.go` | None — no generated code |

For each production file in the diff, check if a corresponding test file also appears in the diff. Matching rules:

- **Go:** `foo.go` → `foo_test.go` in the same directory
- **Ansible:** `collections/ansible_collections/osac/<ns>/roles/<role>/tasks/*.yml` → `osac-aap/tests/integration/targets/<role>/` has changes
- **Python:** `osac-aap/collections/ansible_collections/osac/**/plugins/**/*.py` → `osac-aap/tests/unit/**` has changes

**If gaps exist**, print a warning and continue:

```
⚠️  Test coverage gaps detected:

| Production file changed | Expected test file |
|------------------------|--------------------|
| fulfillment-service/internal/servers/foo_server.go | fulfillment-service/internal/servers/foo_server_test.go |

These files were added or modified without corresponding test changes.
This is a warning — proceeding with PR creation.
```

**If no gaps**, print: "✅ Test coverage looks good — all changed production files have corresponding test changes."

**Always continue to Step 4** regardless of the result.

## Step 4: Push to Push Remote

Always push to `$PUSH_REMOTE`, never to `$UPSTREAM_REMOTE`.

```bash
git push -u "$PUSH_REMOTE" "$BRANCH"
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

`fulfillment-service`, `osac-operator`, `osac-aap`, `osac-installer`,
`bare-metal-fulfillment-operator`, and `osac-csi-driver` share one remote pair
— the `osac` mono-repo — so this step creates a single PR covering every
component touched in `$TOUCHED_COMPONENTS`, not one PR per component.

Determine the upstream repo and push remote owner from the resolved remotes:

```bash
UPSTREAM=$(gh repo view $(git remote get-url "$UPSTREAM_REMOTE") --json nameWithOwner -q .nameWithOwner)
FORK_OWNER=$(gh repo view $(git remote get-url "$PUSH_REMOTE") --json owner -q .owner.login)
```

Construct the title from the ticket key and a short description (ask the user if unclear):

```bash
PR_TITLE="${TICKET:+$TICKET: }<short description>"
```

Create the PR from `$PUSH_REMOTE` to upstream:

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

If PRs in genuinely separate repos exist (e.g. `osac` + `osac-test-infra` — not
just multiple components within `osac`, which is one PR), remind: "Link
related PRs in the description (e.g., 'Depends on osac-project/osac#123')."

## Quick Reference

| Step | What | Gate |
|------|------|------|
| 1 | Detect context, resolve remotes | Not on main, push remote exists, commits ahead |
| 2 | Run validation | All checks pass |
| 3 | Check test coverage | Advisory warning (does not block) |
| 4 | Push branch | Push to `$PUSH_REMOTE` succeeds |
| 5 | Determine title | Jira key included if available |
| 6 | Create PR | PR created against upstream repo |
| 7 | Report | Show PR URL |

## Common Issues

### No push remote detected

Run `tools/resolve-remotes.sh --print` to see which remotes were detected. If no push remote was found, add one:

```bash
git remote add <name> git@github.com:<your-username>/<repo>.git
```

The name can be anything (`fork`, `myfork`, your username) — `resolve-remotes.sh` detects it by URL, not by name.

### `gh pr create` fails with "not authenticated"

```bash
gh auth status
gh auth login
```

### Push rejected (branch already exists on remote)

Do not force-push automatically. Show the push error to the user and ask them for explicit instructions on how to proceed.

### PR already exists

```bash
gh pr list --repo <upstream> --head <push-remote-owner>:<branch>
```

If a PR already exists, show its URL instead of creating a duplicate.

## Red Flags

**Never:**
- Push to `$UPSTREAM_REMOTE` — always use `$PUSH_REMOTE`
- Create a PR from `main`
- Skip validation checks
- Force-push without user confirmation
- Create a PR with failing tests

**Always:**
- Resolve remotes with `tools/resolve-remotes.sh` before pushing
- Run repo-specific validation first
- Push to `$PUSH_REMOTE`
- Include Jira ticket key in title when available
- Check for existing PRs before creating duplicates
