#!/bin/bash
set -euo pipefail

echo "🚀 Setting up OSAC Workspace..."

# Base URL for all repos
GITHUB_ORG="https://github.com/osac-project"

# List of repos to clone
REPOS=(
  "fulfillment-service"
  "osac-operator"
  "osac-aap"
  "osac-installer"
  "osac-test-infra"
  "enhancement-proposals"
  "docs"
)

# Clone or update each repo
for repo in "${REPOS[@]}"; do
  if [ -d "$repo" ]; then
    echo "📦 Updating $repo..."
    # --autostash hides local changes, rebases, then brings them back
    (cd "$repo" && git fetch origin && git rebase origin/main --autostash)
  else
    echo "📥 Cloning $repo..."
    git clone "${GITHUB_ORG}/${repo}.git"
    (cd "$repo" && git checkout main)
  fi
done

echo ""
echo "✅ Workspace ready! All repos are on their latest main branch."
echo ""
echo "📂 Available repos:"
for repo in "${REPOS[@]}"; do
  echo "   - $repo"
done

echo ""
echo "💡 To contribute, add your fork remote:"
echo "   cd <repo> && git remote add fork https://github.com/\$(gh api user -q .login)/<repo>.git"
