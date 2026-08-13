#!/usr/bin/env bash
set -euo pipefail

GITHUB_ORG="osac-project"
NO_FORK=false
FORK_REMOTE_NAME="fork"

declare -A FORK_OVERRIDES=()
if [[ -f "$(dirname "$0")/fork-overrides.sh" ]]; then
  source "$(dirname "$0")/fork-overrides.sh"
fi

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--no-fork] [--fork-name NAME]

Sets up the OSAC workspace by cloning all component repos.

By default, each repo is forked to your GitHub account and cloned with:
  origin     = osac-project/<repo>  (upstream source, PR target)
  <fork-name> = <your-username>/<repo>  (push target for feature branches)

Options:
  --no-fork          Clone directly from osac-project without forking.
                     Useful for read-only access or CI environments.
  --fork-name NAME   Name for the push remote (default: fork).
                     Use any name you prefer — the vendored osac-ai-skills
                     resolve-remotes.sh detects remotes by URL, not by name.
  --help             Show this help message.

Prerequisites:
  - gh CLI installed and authenticated (gh auth login)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-fork) NO_FORK=true; shift ;;
    --fork-name)
      [[ -n "${2:-}" ]] || { echo "Error: --fork-name requires a value"; usage; exit 1; }
      FORK_REMOTE_NAME="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
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
  local fork_repo="${FORK_OVERRIDES[$repo]:-$repo}"
  if [ "$GIT_PROTOCOL" = "ssh" ]; then
    echo "git@github.com:${GH_USER}/${fork_repo}.git"
  else
    echo "https://github.com/${GH_USER}/${fork_repo}.git"
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
  local fork_repo="${FORK_OVERRIDES[$repo]:-$repo}"
  local fork_name_args=()
  if [[ "$fork_repo" != "$repo" ]]; then
    fork_name_args=(--fork-name "$fork_repo")
  fi
  if ! gh repo fork "${GITHUB_ORG}/${repo}" --clone=false --default-branch-only "${fork_name_args[@]}"; then
    if ! gh repo view "${GH_USER}/${fork_repo}"; then
      echo "❌ Failed to fork ${GITHUB_ORG}/${repo}. Skipping fork remote."
      return 1
    fi
  fi
  local url
  url=$(get_fork_url "$repo")
  if git -C "$dir" remote get-url "$FORK_REMOTE_NAME" &>/dev/null; then
    # Remote name already taken (e.g., --fork-name origin on a fresh clone).
    # Rename the existing remote out of the way, then add the fork.
    local old_url target
    old_url=$(git -C "$dir" remote get-url "$FORK_REMOTE_NAME")
    target="upstream"
    while git -C "$dir" remote get-url "$target" &>/dev/null; do
      target="osac-${target}"
    done
    git -C "$dir" remote rename "$FORK_REMOTE_NAME" "$target"
    echo "   Renamed existing '$FORK_REMOTE_NAME' ($old_url) → '$target'"
  fi
  git -C "$dir" remote add "$FORK_REMOTE_NAME" "$url"
  git -C "$dir" fetch "$FORK_REMOTE_NAME"
}

REPOS=(
  "osac"
  "osac-test-infra"
  "osac-ui"
  "enhancement-proposals"
  "docs:osac-docs"
)

# Reference repos — cloned read-only from osac-project, no fork remote added.
# Used by AI agents for context during /design and /implement phases only.
# GITHUB_ORG resolves these to https://github.com/osac-project/<repo>.git
REFERENCE_REPOS=(
  "osac-ux"
)

# Components merged into osac-project/osac as of OSAC-1739. Old standalone
# top-level clones (if present) are no longer bootstrap-managed — quarantined
# to .legacy-repos/<name>/ via `mv` below (never deleted; all local git
# state, including uncommitted changes and unpushed commits, stays intact).
# Keep in sync with skills/create-pr/SKILL.md's merged-component detection
# (Step 1's TOUCHED_COMPONENTS regex and Step 3's File Classification table)
# if a future component merges into osac or one of these is later split out.
MERGED_COMPONENTS=(
  "fulfillment-service"
  "osac-operator"
  "osac-aap"
  "osac-installer"
  "bare-metal-fulfillment-operator"
  "osac-csi-driver"
)
LEGACY_REPOS_DIR=".legacy-repos"

# Self-update: pull latest osac-workspace before updating components
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [ "$CURRENT_BRANCH" = "main" ]; then
  echo "📦 Updating osac-workspace..."
  if ! git fetch origin -q; then
    echo "   ⚠️  Fetch failed for osac-workspace. Skipping self-update."
  elif ! git rebase origin/main --autostash -q; then
    git rebase --abort 2>/dev/null || true
    echo "   ⚠️  Rebase failed for osac-workspace — continuing with current version"
  else
    echo "   ✅ osac-workspace up to date"
  fi
else
  echo "ℹ️  osac-workspace on branch '$CURRENT_BRANCH', skipping self-update"
fi

UPDATE_WARNINGS=0

is_expected_clone() {
  local dir="$1" repo="$2"
  local expected_suffix="${GITHUB_ORG}/${repo}"
  local url
  for remote in $(git -C "$dir" remote 2>/dev/null); do
    url=$(git -C "$dir" remote get-url "$remote" 2>/dev/null) || continue
    if [[ "${url%.git}" == *"$expected_suffix" ]]; then
      return 0
    fi
  done
  return 1
}

# Prints the remote name whose URL matches osac-project/<repo> and returns 0,
# or returns 1 with no output if none match. Callers must check the exit
# status -- don't assume a match (e.g. "origin") when none was found, since a
# clone's origin can point to a fork or be missing entirely.
find_upstream_remote() {
  local dir="$1" repo="$2"
  local expected_suffix="${GITHUB_ORG}/${repo}"
  local url
  for remote in $(git -C "$dir" remote 2>/dev/null); do
    url=$(git -C "$dir" remote get-url "$remote" 2>/dev/null) || continue
    if [[ "${url%.git}" == *"$expected_suffix" ]]; then
      echo "$remote"
      return 0
    fi
  done
  return 1
}

# Returns 0 if every configured push URL for $remote in $dir end-anchor
# matches $expected_suffix, 1 otherwise (including if the remote doesn't
# exist or has no push URL at all). Checks push URLs specifically, not the
# fetch URL `git remote get-url` returns by default -- `git remote set-url
# --push` can point pushes at a completely different repo while the fetch
# URL still looks correct, so a fetch-URL-only check can't be trusted to
# mean "safe to push to as-is". Checks --all push URLs since `--push --add`
# allows configuring more than one.
fork_remote_push_matches() {
  local dir="$1" remote="$2" expected_suffix="$3"
  local push_urls
  push_urls=$(git -C "$dir" remote get-url --push --all "$remote" 2>/dev/null) || return 1
  [ -n "$push_urls" ] || return 1
  local push_url
  while IFS= read -r push_url; do
    [[ "${push_url%.git}" == *"$expected_suffix" ]] || return 1
  done <<< "$push_urls"
  return 0
}

# Moves (never deletes) a stale standalone clone of a now-merged component
# out from under its old top-level name. Only acts when the directory is
# confirmed to be a clone of the old osac-project/<name> repo (precise check,
# not a fuzzy name match) — anything else is left untouched. No-op if the
# directory doesn't exist (already migrated or never cloned) or has already
# been quarantined.
quarantine_merged_component() {
  local name="$1"
  [ -d "$name" ] || return 0
  is_expected_clone "$name" "$name" || return 0

  local dest="${LEGACY_REPOS_DIR}/${name}"
  if [ -e "$dest" ]; then
    echo "⚠️  ${dest} already exists — leaving $name/ in place. Resolve manually (compare and remove one of them)."
    UPDATE_WARNINGS=1
    return 0
  fi

  # mkdir and mv are both part of the `if` condition (not bare statements) so
  # a failure here — e.g. a read-only parent directory — degrades to the
  # warning below instead of tripping `set -e` and aborting the whole script.
  if mkdir -p "$LEGACY_REPOS_DIR" && mv "$name" "$dest"; then
    cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦➡️  $name/ is now part of osac-project/osac — moved to $dest/
   Nothing was deleted: uncommitted changes, stashes, and unpushed
   commits inside $dest/ are untouched. Use osac/$name/ going forward.
   Once you've confirmed you don't need it, remove it with:
     rm -rf $dest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
  else
    echo "⚠️  Could not move $name/ to $dest/ — see error above."
    echo "   It's superseded by osac/$name/; move or remove it manually when convenient."
    UPDATE_WARNINGS=1
  fi
}

for entry in "${REPOS[@]}"; do
  repo="${entry%%:*}"
  dir="${entry#*:}"
  if [ -d "$dir" ] && is_expected_clone "$dir" "$repo"; then
    if upstream_remote=$(find_upstream_remote "$dir" "$repo"); then
      echo "📦 Updating $dir..."
      if ! (cd "$dir" && git fetch "$upstream_remote"); then
        echo "⚠️  Fetch failed for $dir. Skipping update."
        UPDATE_WARNINGS=1
      elif ! (cd "$dir" && git rebase "$upstream_remote/main" --autostash); then
        (cd "$dir" && git rebase --abort 2>/dev/null || true)
        echo "⚠️  Rebase failed for $dir (likely local commits conflict with upstream)."
        echo "   Skipping update — resolve manually with: cd $dir && git rebase $upstream_remote/main"
        UPDATE_WARNINGS=1
      fi
    else
      # Unreachable in practice -- is_expected_clone above already confirmed a
      # matching remote exists, using the same matching logic. Guarded anyway
      # so a future refactor of either function can't silently reintroduce
      # the "origin" guess this replaced.
      echo "⚠️  Could not determine upstream remote for $dir despite passing is_expected_clone. Skipping update."
      UPDATE_WARNINGS=1
    fi
    if [ "$NO_FORK" = false ]; then
      # End-anchored, push-URL-aware, FORK_OVERRIDES-aware match (see
      # fork_remote_push_matches) -- a plain substring-anywhere match on the
      # fetch URL would both false-positive on any fork URL that merely
      # contains "$GH_USER/$repo" as part of a longer repo name (e.g.
      # $repo=osac matching a fork URL for osac-csi-driver) and miss a
      # diverged push URL, and ignoring FORK_OVERRIDES here (unlike
      # ensure_fork_remote) would compare against the wrong expected name
      # for any repo with an override.
      fork_repo="${FORK_OVERRIDES[$repo]:-$repo}"
      if ! fork_remote_push_matches "$dir" "$FORK_REMOTE_NAME" "${GH_USER}/${fork_repo}"; then
        echo "🍴 Adding $FORK_REMOTE_NAME remote for existing repo $dir..."
        ensure_fork_remote "$repo" "$dir" || confirm_continue "Fork remote for $repo failed."
      fi
    fi
  elif [ -d "$dir" ]; then
    echo "⚠️  Skipping $dir — directory exists but is not a clone of ${GITHUB_ORG}/${repo}."
    echo "   Remove or rename the directory and re-run bootstrap.sh to clone it."
    UPDATE_WARNINGS=1
  else
    echo "📥 Cloning $repo into $dir..."
    git clone "https://github.com/${GITHUB_ORG}/${repo}.git" "$dir"

    if [ "$NO_FORK" = false ]; then
      echo "🍴 Adding $FORK_REMOTE_NAME remote for $repo..."
      ensure_fork_remote "$repo" "$dir" || confirm_continue "Fork remote for $repo failed."
    fi
  fi
done

for name in "${MERGED_COMPONENTS[@]}"; do
  quarantine_merged_component "$name"
done

for entry in "${REFERENCE_REPOS[@]}"; do
  repo="${entry%%:*}"
  dir="${entry#*:}"
  if [ -d "$dir" ] && is_expected_clone "$dir" "$repo"; then
    if upstream_remote=$(find_upstream_remote "$dir" "$repo"); then
      echo "📦 Updating $dir (reference)..."
      (cd "$dir" && git fetch "$upstream_remote" && git rebase "$upstream_remote/main" --autostash) || \
        echo "⚠️  Update failed for $dir — skipping."
    else
      echo "⚠️  Could not determine upstream remote for $dir (reference) — skipping update."
    fi
  elif [ ! -d "$dir" ]; then
    echo "📥 Cloning $repo (reference, no fork)..."
    git clone "https://github.com/${GITHUB_ORG}/${repo}.git" "$dir"
  fi
done

# Vendor osac-ai-skills (OSAC-3956). Same clone/fetch/rebase pattern as
# ai-workflows below — copy this block for OSAC-3957 (osac/tools/bootstrap.sh).
# Prefer ~/.osac-ai-skills only when it is a usable vendor checkout; otherwise
# use ./.osac-ai-skills (clone or update).
OSAC_AI_SKILLS_REPO="${GITHUB_ORG}/osac-ai-skills"
OSAC_AI_SKILLS_DIR=""
osac_ai_skills_vendor_ok() {
  local dir="$1"
  [ -d "${dir}/.git" ] \
    && [ -d "${dir}/skills" ] \
    && [ -x "${dir}/tools/link-agent-skills.sh" ]
}
if [ -d "${HOME}/.osac-ai-skills" ] && osac_ai_skills_vendor_ok "${HOME}/.osac-ai-skills"; then
  OSAC_AI_SKILLS_DIR="$(readlink -f "${HOME}/.osac-ai-skills")"
  echo "📦 Updating osac-ai-skills (${OSAC_AI_SKILLS_DIR})..."
  if ! (cd "$OSAC_AI_SKILLS_DIR" && git fetch origin); then
    echo "⚠️  Fetch failed for osac-ai-skills. Skipping update."
    UPDATE_WARNINGS=1
  elif ! (cd "$OSAC_AI_SKILLS_DIR" && git rebase origin/main --autostash); then
    (cd "$OSAC_AI_SKILLS_DIR" && git rebase --abort 2>/dev/null || true)
    echo "⚠️  Rebase failed for osac-ai-skills. Resolve manually: cd $OSAC_AI_SKILLS_DIR && git rebase origin/main"
    UPDATE_WARNINGS=1
  fi
elif [ -d ".osac-ai-skills" ] && osac_ai_skills_vendor_ok ".osac-ai-skills"; then
  OSAC_AI_SKILLS_DIR="$(pwd)/.osac-ai-skills"
  echo "📦 Updating osac-ai-skills (.osac-ai-skills)..."
  if ! (cd "$OSAC_AI_SKILLS_DIR" && git fetch origin); then
    echo "⚠️  Fetch failed for osac-ai-skills. Skipping update."
    UPDATE_WARNINGS=1
  elif ! (cd "$OSAC_AI_SKILLS_DIR" && git rebase origin/main --autostash); then
    (cd "$OSAC_AI_SKILLS_DIR" && git rebase --abort 2>/dev/null || true)
    echo "⚠️  Rebase failed for osac-ai-skills. Resolve manually: cd $OSAC_AI_SKILLS_DIR && git rebase origin/main"
    UPDATE_WARNINGS=1
  fi
elif [ -d ".osac-ai-skills" ]; then
  # Same gate as the ~/.osac-ai-skills branch above -- without it, a stale or
  # non-git ./.osac-ai-skills would hit `git fetch` directly and fail with a
  # confusing "Fetch failed" instead of this actionable message.
  echo "❌ .osac-ai-skills exists but is not a usable vendor checkout (expected a git clone with skills/ and an executable tools/link-agent-skills.sh)."
  echo "   Remove or rename it, then re-run bootstrap.sh to clone a fresh copy."
  exit 1
else
  if [ -d "${HOME}/.osac-ai-skills" ]; then
    echo "⚠️  ${HOME}/.osac-ai-skills exists but is not a usable vendor checkout; using ./.osac-ai-skills"
  fi
  OSAC_AI_SKILLS_DIR="$(pwd)/.osac-ai-skills"
  echo "📥 Cloning osac-ai-skills..."
  git clone "https://github.com/${OSAC_AI_SKILLS_REPO}.git" ".osac-ai-skills"
fi

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
# Must run before ai-workflows' install.sh: on a from-scratch clone, nothing
# under .claude/, .cursor/, or .gemini/ exists yet, so link-agent-skills.sh
# can freely create the .claude/skills -> ../skills (etc.) umbrella symlinks.
# install.sh's own `mkdir -p "<agent>/skills"` + targeted `ln -sfn .../<wf>`
# calls are non-destructive against an existing directory symlink -- they
# follow it and land each ai-workflows entry inside the shared skills/ tree.
# Reversing this order breaks a from-scratch bootstrap: install.sh would
# create .claude/skills (etc.) as a real directory first, and safe_symlink
# refuses to replace a real directory with a symlink.
#
# Export the vendor dir this script just resolved/updated/cloned above so the
# wrapper uses that exact directory instead of independently re-resolving one
# -- the wrapper's own resolve_osac_ai_skills_dir() has no way to know this
# script already rejected a stale/invalid ~/.osac-ai-skills or .osac-ai-skills
# in favor of the other, and could otherwise silently link skills from a
# different vendor than the one just fetched/rebased/cloned.
echo "🔗 Linking agent skill directories to skills/..."
OSAC_AI_SKILLS_VENDOR_DIR="${OSAC_AI_SKILLS_DIR}" tools/link-agent-skills.sh --all
echo "🔧 Installing ai-workflows skills..."
AI_WORKFLOWS="bugfix,implement,prd,design,e2e"
"$AI_WORKFLOWS_DIR/install.sh" all --project . --workflows "$AI_WORKFLOWS"

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
    repo="${entry%%:*}"
    branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "unknown")
    echo "   $dir (branch: $branch)"
    if upstream_remote=$(find_upstream_remote "$dir" "$repo"); then
      upstream_url=$(git -C "$dir" remote get-url "$upstream_remote" 2>/dev/null || echo "not set")
      echo "     $upstream_remote: $upstream_url"
    else
      echo "     upstream: unknown — no remote matches ${GITHUB_ORG}/${repo}"
    fi
    fork_url=$(git -C "$dir" remote get-url "$FORK_REMOTE_NAME" 2>/dev/null || echo "not set")
    if [ "$fork_url" != "not set" ]; then
      echo "     $FORK_REMOTE_NAME: $fork_url"
    fi
  fi
done

if [ "$NO_FORK" = true ]; then
  echo ""
  echo "💡 Cloned in read-only mode. To contribute, re-run without --no-fork"
  echo "   or add your fork manually:"
  echo "   cd <repo> && git remote add <name> \$(gh config get git_protocol | grep -q ssh && echo git@github.com: || echo https://github.com/)\$(gh api user -q .login)/<repo>.git"
fi
