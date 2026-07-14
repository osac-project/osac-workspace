#!/bin/bash
# Project statusline: extends user statusline with osac-workspace + ai-workflows sync status

input=$(cat)

# Run the user's global statusline first
if [[ -f ~/.claude/statusline.sh ]]; then
  echo "$input" | bash ~/.claude/statusline.sh
fi

# Colors
GREEN='\033[32m'
YELLOW='\033[33m'
GRAY='\033[90m'
RESET='\033[0m'

log_info() { printf '%b%s%b' "$GREEN" "$1" "$RESET"; }
log_warning() { printf '%b%s%b' "$YELLOW" "$1" "$RESET"; }
log_muted() { printf '%b%s%b' "$GRAY" "$1" "$RESET"; }

repo_status() {
  local dir="$1" name="$2"
  [[ -d "$dir" ]] || { log_muted "$name: not found"; return; }

  local branch behind
  branch=$(git -C "$dir" branch --show-current 2>/dev/null) || branch="detached"
  [[ -n "$branch" ]] || branch="detached"
  behind=$(git -C "$dir" rev-list HEAD..origin/main --count 2>/dev/null) || { log_muted "$name: $branch ?"; return; }

  if [[ "$behind" -eq 0 ]]; then
    log_info "$name: $branch ✓"
  else
    log_warning "$name: $branch ↓${behind} behind"
  fi
}

WORKSPACE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
AI_DIR="${HOME}/.ai-workflows"

ws=$(repo_status "$WORKSPACE_DIR" "workspace")
ai=$(repo_status "$AI_DIR" "ai-workflows")

printf '%b %b %b\n' "$ws" "${GRAY}|${RESET}" "$ai"
