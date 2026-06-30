#!/usr/bin/env bash
set -euo pipefail

GITHUB_ORG="osac-project"
NO_FORK=false

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--no-fork]

Sets up the OSAC workspace by cloning all component repos.

By default, each repo is forked to your GitHub account and cloned with:
  origin = osac-project/<repo>  (upstream source, PR target)
  fork   = <your-username>/<repo>  (push target for feature branches)

Options:
  --no-fork    Clone directly from osac-project without forking.
               Useful for read-only access or CI environments.
  --help       Show this help message.

Prerequisites:
  - gh CLI installed and authenticated (gh auth login)
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
  if ! gh auth status; then
    echo "❌ Error: gh CLI is not authenticated."
    echo "Run 'gh auth login' or use --no-fork for read-only clone."
    exit 1
  fi
  GH_USER=$(gh api user -q .login)
  GIT_PROTOCOL=$(gh config get git_protocol 2>/dev/null || echo "https")
  echo "🚀 Setting up OSAC workspace for GitHub user: $GH_USER"
else
  echo "🚀 Setting up OSAC workspace (read-only, no forks)..."
fi

get_fork_url() {
  local repo="$1"
  if [ "$GIT_PROTOCOL" = "ssh" ]; then
    echo "git@github.com:${GH_USER}/${repo}.git"
  else
    echo "https://github.com/${GH_USER}/${repo}.git"
  fi
}

confirm_continue() {
  local prompt="$1"
   if ! [ -t 0 ]; then
    echo "❌ $prompt Non-interactive session, cannot prompt for confirmation. Aborting." >&2
    exit 1
  fi
  read -r -p "$prompt Continue? [y/N] " reply </dev/tty
  [[ "$reply" =~ ^[Yy]$ ]]
}

ensure_fork_remote() {
  local repo="$1"
  local dir="$2"
  # Ensure fork exists on GitHub, then verify it
  if ! gh repo fork "${GITHUB_ORG}/${repo}" --clone=false --default-branch-only; then
    if ! gh repo view "${GH_USER}/${repo}"; then
      echo "❌ Failed to fork ${GITHUB_ORG}/${repo}. Skipping fork remote."
      return 1
    fi
  fi
  local url
  url=$(get_fork_url "$repo")
  git -C "$dir" remote add fork "$url"
  git -C "$dir" fetch fork
}

REPOS=(
  "fulfillment-service"
  "osac-operator"
  "osac-aap"
  "osac-installer"
  "osac-test-infra"
  "osac-ui"
  "enhancement-proposals"
  "docs:osac-docs"
  "host-management-openstack"
  "bare-metal-fulfillment-operator"
)

UPDATE_WARNINGS=0

is_expected_clone() {
  local dir="$1" repo="$2"
  local expected_suffix="${GITHUB_ORG}/${repo}"
  local origin_url
  origin_url=$(git -C "$dir" remote get-url origin 2>/dev/null) || return 1
  [[ "${origin_url%.git}" == *"$expected_suffix" ]]
}

for entry in "${REPOS[@]}"; do
  repo="${entry%%:*}"
  dir="${entry#*:}"
  if [ -d "$dir" ] && is_expected_clone "$dir" "$repo"; then
    echo "📦 Updating $dir..."
    if ! (cd "$dir" && git fetch origin); then
      echo "⚠️  Fetch failed for $dir. Skipping update."
      UPDATE_WARNINGS=1
    elif ! (cd "$dir" && git rebase origin/main --autostash); then
      (cd "$dir" && git rebase --abort 2>/dev/null || true)
      echo "⚠️  Rebase failed for $dir (likely local commits conflict with upstream)."
      echo "   Skipping update — resolve manually with: cd $dir && git rebase origin/main"
      UPDATE_WARNINGS=1
    fi
    if [ "$NO_FORK" = false ] && ! git -C "$dir" remote get-url fork &>/dev/null; then
      echo "🍴 Adding fork remote for existing repo $dir..."
      ensure_fork_remote "$repo" "$dir" || confirm_continue "Fork remote for $repo failed."
    fi
  elif [ -d "$dir" ]; then
    echo "⚠️  Skipping $dir — directory exists but is not a clone of ${GITHUB_ORG}/${repo}."
    echo "   Remove or rename the directory and re-run bootstrap.sh to clone it."
    UPDATE_WARNINGS=1
  else
    echo "📥 Cloning $repo into $dir..."
    git clone "https://github.com/${GITHUB_ORG}/${repo}.git" "$dir"

    if [ "$NO_FORK" = false ]; then
      echo "🍴 Adding fork remote for $repo..."
      ensure_fork_remote "$repo" "$dir" || confirm_continue "Fork remote for $repo failed."
    fi
  fi
done

# Install ai-workflows (bugfix, implement, etc.)
AI_WORKFLOWS_REPO="flightctl/ai-workflows"
AI_WORKFLOWS_DIR=""
# Prefer existing ~/.ai-workflows if present; otherwise clone locally
if [ -d "${HOME}/.ai-workflows" ]; then
  AI_WORKFLOWS_DIR="$(readlink -f "${HOME}/.ai-workflows")"
  echo "📦 Updating ai-workflows (${AI_WORKFLOWS_DIR})..."
  if ! (cd "$AI_WORKFLOWS_DIR" && git fetch origin); then
    echo "⚠️  Fetch failed for ai-workflows. Skipping update."
    UPDATE_WARNINGS=1
  elif ! (cd "$AI_WORKFLOWS_DIR" && git rebase origin/main --autostash); then
    (cd "$AI_WORKFLOWS_DIR" && git rebase --abort 2>/dev/null || true)
    echo "⚠️  Rebase failed for ai-workflows. Resolve manually: cd $AI_WORKFLOWS_DIR && git rebase origin/main"
    UPDATE_WARNINGS=1
  fi
elif [ -d ".ai-workflows" ]; then
  AI_WORKFLOWS_DIR="$(pwd)/.ai-workflows"
  echo "📦 Updating ai-workflows (.ai-workflows)..."
  if ! (cd "$AI_WORKFLOWS_DIR" && git fetch origin); then
    echo "⚠️  Fetch failed for ai-workflows. Skipping update."
    UPDATE_WARNINGS=1
  elif ! (cd "$AI_WORKFLOWS_DIR" && git rebase origin/main --autostash); then
    (cd "$AI_WORKFLOWS_DIR" && git rebase --abort 2>/dev/null || true)
    echo "⚠️  Rebase failed for ai-workflows. Resolve manually: cd $AI_WORKFLOWS_DIR && git rebase origin/main"
    UPDATE_WARNINGS=1
  fi
else
  AI_WORKFLOWS_DIR="$(pwd)/.ai-workflows"
  echo "📥 Cloning ai-workflows..."
  git clone "https://github.com/${AI_WORKFLOWS_REPO}.git" ".ai-workflows"
fi
echo "🔧 Installing ai-workflows skills..."
"$AI_WORKFLOWS_DIR/install.sh" claude --project . --workflows bugfix,implement,prd,design,e2e
"$AI_WORKFLOWS_DIR/install.sh" cursor --project . --workflows bugfix,implement,prd,design,e2e

if command -v rh-multi-pre-commit &>/dev/null; then
  echo ""
  echo "🔒 Installing rh-pre-commit hooks..."
  for entry in "${REPOS[@]}"; do
    dir="${entry#*:}"
    if [ -d "$dir" ]; then
      if rh-multi-pre-commit install --path "$dir" 2>&1; then
        echo "   ✅ $dir"
      else
        echo "   ⚠️  $dir (failed to install hooks)"
      fi
    fi
  done
elif command -v pre-commit &>/dev/null; then
  echo ""
  echo "🔒 Installing pre-commit hooks..."
  for entry in "${REPOS[@]}"; do
    dir="${entry#*:}"
    if [ -d "$dir" ] && [ -f "$dir/.pre-commit-config.yaml" ]; then
      if (cd "$dir" && pre-commit install 2>&1); then
        echo "   ✅ $dir"
      else
        echo "   ⚠️  $dir (failed to install hooks)"
      fi
    fi
  done
else
  echo ""
  echo "⚠️  pre-commit not found — skipping hook installation."
  echo "   Install it with: pip install pre-commit"
  echo "   Red Hat employees: install rh-pre-commit for enhanced secret scanning"
  echo "   Then re-run bootstrap.sh to install hooks in all repos."
fi

echo ""
if [ "$UPDATE_WARNINGS" -eq 0 ]; then
  echo "✅ Workspace ready! All repos are on their latest main branch."
else
  echo "⚠️  Workspace ready with warnings. Some repos were not updated — see messages above."
fi
echo ""
echo "📂 Available repos:"
for entry in "${REPOS[@]}"; do
  dir="${entry#*:}"
  if [ -d "$dir" ]; then
    branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "unknown")
    origin_url=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "not set")
    fork_url=$(git -C "$dir" remote get-url fork 2>/dev/null || echo "not set")
    echo "   $dir (branch: $branch)"
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
  echo "   cd <repo> && git remote add fork \$(gh config get git_protocol | grep -q ssh && echo git@github.com: || echo https://github.com/)\$(gh api user -q .login)/<repo>.git"
fi
