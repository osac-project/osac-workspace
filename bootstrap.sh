#!/bin/bash
set -euo pipefail

GITHUB_ORG="osac-project"
NO_FORK=false

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--no-fork]

Sets up the OSAC workspace by cloning all component repos.

By default, each repo is forked to your GitHub account and cloned with:
  origin = osac-project/<repo>  (push target for PRs)
  fork   = <your-username>/<repo>  (your fork)

Options:
  --no-fork    Clone directly from osac-project without forking.
               Useful for read-only access or CI environments.
  --help       Show this help message.

Prerequisites:
  - gh CLI installed and authenticated (gh auth login)
  - SSH access to GitHub (for fork workflow)
EOF
}

for arg in "$@"; do
  case "$arg" in
    --no-fork) NO_FORK=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

# Verify gh CLI for fork workflow
if [ "$NO_FORK" = false ]; then
  if ! command -v gh &>/dev/null; then
    echo "❌ Error: gh CLI is not installed."
    echo "Install it (https://cli.github.com/) or use --no-fork for read-only clone."
    exit 1
  fi
  if ! gh auth status &>/dev/null; then
    echo "❌ Error: gh CLI is not authenticated."
    echo "Run 'gh auth login' or use --no-fork for read-only clone."
    exit 1
  fi
  GH_USER=$(gh api user -q .login)
  echo "🚀 Setting up OSAC workspace for GitHub user: $GH_USER"
else
  echo "🚀 Setting up OSAC workspace (read-only, no forks)..."
fi

REPOS=(
  "fulfillment-service"
  "osac-operator"
  "osac-aap"
  "osac-installer"
  "osac-test-infra"
  "enhancement-proposals"
  "docs"
)

for repo in "${REPOS[@]}"; do
  if [ -d "$repo" ]; then
    echo "📦 Updating $repo..."
    (cd "$repo" && git fetch origin && git rebase origin/main --autostash)
  else
    echo "📥 Cloning $repo..."
    git clone "https://github.com/${GITHUB_ORG}/${repo}.git"

    if [ "$NO_FORK" = false ]; then
      echo "🍴 Adding fork remote for $repo..."
      # Ensure fork exists on GitHub (no-op if already forked)
      gh repo fork "${GITHUB_ORG}/${repo}" --clone=false 2>/dev/null || true
      # Add fork as 'fork' remote
      (cd "$repo" && git remote add fork "git@github.com:${GH_USER}/${repo}.git" && git fetch fork)
    fi
  fi
done

echo ""
echo "✅ Workspace ready! All repos are on their latest main branch."
echo ""
echo "📂 Available repos:"
for repo in "${REPOS[@]}"; do
  if [ -d "$repo" ]; then
    branch=$(git -C "$repo" branch --show-current 2>/dev/null || echo "unknown")
    origin_url=$(git -C "$repo" remote get-url origin 2>/dev/null || echo "not set")
    fork_url=$(git -C "$repo" remote get-url fork 2>/dev/null || echo "not set")
    echo "   $repo (branch: $branch)"
    echo "     origin: $origin_url"
    if [ "$fork_url" != "not set" ]; then
      echo "     fork:   $fork_url"
    fi
  fi
done

if [ "$NO_FORK" = true ]; then
  echo ""
  echo "💡 Cloned in read-only mode. To contribute, re-run without --no-fork"
  echo "   or add your fork manually:"
  echo "   cd <repo> && git remote add fork git@github.com:\$(gh api user -q .login)/<repo>.git"
fi
