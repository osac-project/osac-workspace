#!/usr/bin/env bash
# SessionStart hook: fetch+rebase osac-workspace (if on main) and ai-workflows
# so the AI agent always has the latest CLAUDE.md, rules, and skills.

WORKSPACE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

resolve_upstream() {
  local dir="$1"
  local script="${WORKSPACE_DIR}/tools/resolve-remotes.sh"
  if [[ -x "$script" ]]; then
    eval "$("$script" "$dir" 2>/dev/null)" 2>/dev/null && echo "$UPSTREAM_REMOTE" && return
  fi
  echo "origin"
}

fetch_and_rebase() {
  local dir="$1" name="$2" only_on_main="${3:-false}"
  [[ -d "$dir" ]] || return 0

  local branch upstream
  branch="$(git -C "$dir" branch --show-current 2>/dev/null)" || return 0
  upstream="$(resolve_upstream "$dir")"

  if [[ "$only_on_main" == "true" && "$branch" != "main" ]]; then
    git -C "$dir" fetch "$upstream" -q 2>/dev/null || true
    local behind
    behind=$(git -C "$dir" rev-list "HEAD..${upstream}/main" --count 2>/dev/null || echo "?")
    if [[ "$behind" == "0" ]]; then
      echo "$name: on '$branch', up to date with main"
    else
      echo "$name: on '$branch', $behind commits behind main — consider running: git rebase ${upstream}/main"
    fi
    return 0
  fi

  if ! git -C "$dir" fetch "$upstream" -q 2>/dev/null; then
    echo "$name: fetch failed"
    return 0
  fi

  local head_before head_after
  head_before="$(git -C "$dir" rev-parse HEAD)"

  trap 'git -C "$dir" rebase --abort 2>/dev/null || true' INT TERM

  if git -C "$dir" rebase "${upstream}/main" --autostash -q >/dev/null 2>&1; then
    head_after="$(git -C "$dir" rev-parse HEAD)"
    if [[ "$head_before" == "$head_after" ]]; then
      echo "$name: up to date"
    else
      echo "$name: updated"
    fi
  else
    git -C "$dir" rebase --abort 2>/dev/null || true
    echo "$name: rebase conflict, skipped"
  fi
  trap - INT TERM
}

fetch_and_rebase "$WORKSPACE_DIR" "osac-workspace" true
fetch_and_rebase "${HOME}/.ai-workflows" "ai-workflows"
