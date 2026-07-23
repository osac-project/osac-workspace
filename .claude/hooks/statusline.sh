#!/bin/bash
# Project statusline: extends user statusline with osac-workspace + ai-workflows sync status

input=$(cat)

# workspace.project_dir, passed down by the settings.json statusLine command
# (which already extracted it from the JSON payload to build the absolute
# path it needed to invoke this script in the first place).
project_dir="${1:-}"

# Run the user's own global statusline first. This project's statusLine
# setting fully replaces (not merges with) the user's global one, so recover
# whatever they actually configured in ~/.claude/settings.json and re-invoke
# it directly — works for ccstatusline, a custom script, or any other tool,
# without assuming every contributor uses the same one.
if command -v jq >/dev/null 2>&1 && [[ -f "${HOME}/.claude/settings.json" ]]; then
  USER_STATUSLINE_CMD=$(jq -r '.statusLine.command // empty' "${HOME}/.claude/settings.json" 2>/dev/null)
  if [[ -n "${USER_STATUSLINE_CMD}" ]]; then
    printf "%s\n" "$input" | bash -c "${USER_STATUSLINE_CMD}"
  fi
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

# Fall back to re-deriving project_dir from $input when this script is
# invoked directly/manually without the argument. Deriving from $0/cwd
# doesn't work: Claude Code runs statusLine commands with cwd set to the
# session's *current* directory, which drifts as the agent cd's around this
# multi-repo workspace and differs from where the session was actually
# launched (see https://code.claude.com/docs/en/statusline.md#available-data).
WORKSPACE_DIR="${project_dir:-$(printf '%s' "$input" | jq -r '.workspace.project_dir // empty' 2>/dev/null)}"
AI_DIR="${HOME}/.ai-workflows"

ws=$(repo_status "$WORKSPACE_DIR" "workspace")
ai=$(repo_status "$AI_DIR" "ai-workflows")

printf '%b %b %b\n' "$ws" "${GRAY}|${RESET}" "$ai"
