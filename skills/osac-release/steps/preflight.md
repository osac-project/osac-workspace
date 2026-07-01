# Pre-flight Steps (0 -- 0.8)

## Step 0: Pre-flight Checks

**Gate checks -- stop if any fail:**

| Check | Command | Fail action |
|-------|---------|-------------|
| `gh` CLI authenticated | `gh auth status` | Stop: "gh CLI not authenticated. Run `gh auth login`." |
| `helm` CLI available | `helm version` | Stop: "helm CLI not found. Install helm." |

**Parse user message** for optional flags:

```text
/osac-release                              # patch bump all components
/osac-release v0.1.0                       # set all components to v0.1.0
/osac-release --only fulfillment-service   # publish only one component
/osac-release --skip osac-aap              # skip a specific component
```

`--only` and `--skip` are mutually exclusive -- error if both are supplied.
Version overrides must match `v[0-9]+\.[0-9]+\.[0-9]+` (strict semver).

## Step 0.5: Component Selection (AskUserQuestion)

Use AskUserQuestion with **exactly** this structure. Do NOT improvise the
format -- use the exact questions, headers, options, and descriptions below.

The default release includes ALL components. Present two multi-select questions
so the user sees three tabs: `☐ Components`, `☐ More`, `✔ Submit`.

**Question 1** (header: `Components`, multiSelect: true):

| label | description |
|-------|-------------|
| `fulfillment-service` | `Tags fulfillment-service repo, publishes fulfillment-service chart` |
| `osac-operator` | `Tags osac-operator repo, publishes osac-operator + osac-operator-crds charts` |
| `bare-metal-fulfillment-operator` | `Tags bare-metal-fulfillment-operator repo, publishes bmf + bmf-crds charts` |
| `osac-aap` | `Tags osac-aap repo, publishes osac-aap chart` |

**Question 2** (header: `More`, multiSelect: true):

| label | description |
|-------|-------------|
| `osac-ui` | `Tags osac-ui repo, publishes osac-ui chart` |
| `osac (umbrella)` | `Publishes umbrella chart via workflow_dispatch with all component versions` |

Both questions use: `question: "Which components should be included in this release?"`

If `--only` or `--skip` flags were parsed from the user's message, pre-filter
the selection accordingly (omit deselected components from the options).

If the user deselects a component, warn: "Deselected components will NOT be
re-tagged. The umbrella chart will use their current published version."

If the user deselects the umbrella, warn: "The umbrella chart will not be
published. Only component charts will be tagged and published."

Only discover/clone repos and fetch tags for the selected components in the
following steps.

## Step 0.6: Recent Release Check

Check if any release activity happened in the last 24 hours for the **selected
components only**. This uses the GitHub API directly -- no local repos needed.

```bash
SINCE=$(python3 -c "from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)-timedelta(hours=24)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
gh run list --repo osac-project/<repo> -w publish-charts.yaml --limit 3 \
  --json status,conclusion,createdAt,headBranch \
  --jq "[.[] | select(.createdAt > \"$SINCE\")]"
```

Also check for in-progress runs:

```bash
gh run list --repo osac-project/<repo> -w publish-charts.yaml --status in_progress \
  --json databaseId,headBranch --jq '.'
```

**If any in-progress runs are found**, show a warning:

```text
⚠️  Active release detected!

  🔄 osac-operator → publish-charts in_progress (run #12345, tag v0.0.3)

  A release workflow is currently running. Proceeding may cause conflicts.
```

Then ask (AskUserQuestion):
- A) Abort -- wait for the current release to finish
- B) Proceed anyway -- I know what I'm doing

**If completed runs found in the last 24 hours** (no in-progress), show an
informational notice and continue without blocking:

```text
ℹ️  Recent releases in the last 24 hours:

  🏷️  fulfillment-service → v0.0.69 (completed 3h ago)
```

## Step 0.7: Release Coordination Gate (AskUserQuestion)

Ask the user two things before proceeding:

1. **Release reason** (AskUserQuestion with options): "What is the reason for
   this release?"
   - A) Routine release (scheduled version bump)
   - B) Bug fix
   - C) New feature
   - D) Dependency update
   The user can also type a custom reason via "Other".

2. **Infra team coordination** (confirmation): "Have you reached out to the OSAC
   Infra team to let them know about this release and the reason for it?"
   - A) Yes, the Infra team is aware and has approved
   - B) No, I haven't contacted them yet

If B, stop and tell the user: "Please coordinate with the OSAC Infra team
before proceeding. Let them know the release reason and get their
acknowledgment. Then re-run `/osac-release`."

Record the release reason -- include it in the Step 9 release summary.

## Step 0.8: Repo Discovery

Discover and validate repos **only for the selected components** from Step 0.5.

```bash
WORKSPACE_ROOT=$(git rev-parse --show-toplevel)
PARENT_DIR=$(dirname "$WORKSPACE_ROOT")

for repo in <selected repos>; do
  path="${PARENT_DIR}/${repo}"
  if [ -d "$path" ]; then
    upstream_url=$(git -C "$path" remote get-url upstream 2>/dev/null || true)
    if [ -z "$upstream_url" ]; then
      echo "ERROR: ${repo} has no upstream remote. Run:"
      echo "  git -C $path remote add upstream git@github.com:osac-project/${repo}.git"
      # Stop or prompt user
    elif echo "$upstream_url" | grep -qE "osac-project/${repo}(\.git)?$"; then
      # OK -- upstream points to the correct repo
    else
      echo "WARNING: ${repo} upstream remote points to ${upstream_url}, expected osac-project/${repo}"
    fi
  fi
done
```

If a selected repo is not found, clone it automatically via SSH without asking:

```bash
git clone git@github.com:osac-project/<repo>.git "${PARENT_DIR}/${repo}"
git -C "${PARENT_DIR}/${repo}" remote rename origin upstream
```

**Always use SSH** (`git@github.com:`) for cloning -- HTTPS clones cannot push
tags. If the SSH clone fails, then ask the user (AskUserQuestion):
- A) Provide an explicit path to an existing checkout
- B) Skip this component (the umbrella chart will use the component's current
  published version)

**Pre-flight warnings (non-blocking):**

For each discovered repo, check for uncommitted changes:

```bash
if [ -n "$(git -C "$path" status --porcelain)" ]; then
  echo "WARNING: ${repo} has uncommitted changes"
fi
```

Warn the user but do not block. Tags are created on `upstream/main`, not the
local working tree.
