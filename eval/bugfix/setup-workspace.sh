#!/bin/bash
# setup-workspace.sh — Generic workspace setup for bugfix eval cases
#
# Usage: ./setup-workspace.sh <input.yaml> [workspace_root]
#
# All repo SHAs are pinned in input.yaml — no runtime lookups.
#
# 1. Clones all OSAC repos to a shared cache (fast on repeat runs).
# 2. Copies repos into the workspace and checks out the pinned SHA.
# 3. Renders task.md from template using case metadata.
# 4. Creates .ai-bot/ directory for workflow artifacts.

set -euo pipefail

INPUT_FILE="${1:?Usage: setup-workspace.sh <input.yaml> [workspace_root]}"
WORKSPACE_ROOT="${2:-.}"
CACHE_DIR="${REPO_CACHE:-/tmp/osac-eval-repos}"
OSAC_ORG="osac-project"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_TEMPLATE="${TASK_TEMPLATE:-$SCRIPT_DIR/task.md.tmpl}"

# --- Step 1: Clone repos to cache (shared across cases) ---

REPOS=$(python3 -c "
import yaml
with open('$INPUT_FILE') as f:
    d = yaml.safe_load(f)
for name, sha in d.get('repos', {}).items():
    print(f'{name} {sha}')
")

REPO_NAMES=$(echo "$REPOS" | awk '{print $1}' | sort -u)

mkdir -p "$CACHE_DIR"
for repo in $REPO_NAMES; do
    if [ ! -d "$CACHE_DIR/$repo" ]; then
        echo "Cloning $OSAC_ORG/$repo to cache..."
        git clone --quiet "https://github.com/$OSAC_ORG/$repo.git" "$CACHE_DIR/$repo"
    else
        git -C "$CACHE_DIR/$repo" fetch origin --quiet 2>/dev/null || true
    fi
done

# --- Step 2: Copy repos and checkout pinned SHAs ---

while IFS=' ' read -r repo sha; do
    [ -z "$repo" ] && continue
    echo "Setting up $repo at ${sha:0:8}..."
    rm -rf "${WORKSPACE_ROOT:?}/$repo"
    cp -a "$CACHE_DIR/$repo" "$WORKSPACE_ROOT/$repo"
    git -C "$WORKSPACE_ROOT/$repo" checkout "$sha" --quiet || {
        echo "ERROR: Could not checkout $sha in $repo"
        exit 1
    }
done <<< "$REPOS"

# --- Step 3: Render task.md from template ---

if [ -f "$TASK_TEMPLATE" ]; then
    python3 -c "
import yaml
with open('$INPUT_FILE') as f:
    d = yaml.safe_load(f)
jira_key = d.get('jira_key', 'UNKNOWN')
# Extract summary from first line of prompt after 'Fix bug MGMT-XXXXX:'
prompt = d.get('prompt', '')
summary = prompt.split('\n')[0]
# Clean up common prefixes
for prefix in ['Fix bug ' + jira_key + ':', 'Fix bug ' + jira_key + ' —', 'Fix bug ' + jira_key + ' -']:
    if summary.startswith(prefix):
        summary = summary[len(prefix):].strip()
        break
with open('$TASK_TEMPLATE') as f:
    template = f.read()
rendered = template.replace('{jira_key}', jira_key).replace('{summary}', summary)
with open('$WORKSPACE_ROOT/task.md', 'w') as f:
    f.write(rendered)
"
    echo "  Rendered task.md"
fi

# --- Step 4: Create output directories ---

mkdir -p "$WORKSPACE_ROOT/.ai-bot"
mkdir -p "$WORKSPACE_ROOT/.eval-ref"
if [ -f "$WORKSPACE_ROOT/reference.md" ]; then
    cp "$WORKSPACE_ROOT/reference.md" "$WORKSPACE_ROOT/.eval-ref/reference.md"
fi

# --- Done ---

echo ""
echo "Workspace ready at $WORKSPACE_ROOT"
echo "  Repos: $(echo "$REPO_NAMES" | tr '\n' ', ' | sed 's/,$//')"
