#!/usr/bin/env bash
# Temp-file and Jira-credential helpers for jira-cli safe create (mktemp +
# EXIT trap cleanup, plus jira_login() for skills that need direct REST calls).
#
# Source from osac-workspace (do not execute — defines shell functions):
#   source "$(git rev-parse --show-toplevel)/tools/jira-safe-create.sh"
#
# Call new_temp for each temp path, then add_temp in the parent shell after
# assignment. add_temp inside $(new_temp ...) runs in a subshell and the EXIT
# trap will not see those paths.

if [[ -n "${JIRA_SAFE_CREATE_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
JIRA_SAFE_CREATE_LOADED=1

TEMP_FILES=()
cleanup() {
  if ((${#TEMP_FILES[@]} > 0)); then
    rm -f "${TEMP_FILES[@]}"
  fi
}
trap cleanup EXIT

add_temp() { TEMP_FILES+=("$1"); }

new_temp() {
  local prefix=${1:-osac-jira}
  mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}

# Configured Jira username, for skills that build `curl -K -` credentials
# (`user = "$(jira_login):${JIRA_API_TOKEN}"`) to call the Jira REST API
# directly for operations jira-cli itself can't perform. Returns 1 (and
# prints nothing) if the config file is missing, unreadable, or has no
# non-empty `login:` value — `grep | awk`'s own exit status is awk's, which
# is 0 even when grep found nothing, so callers can't rely on it alone.
jira_login() {
  local config=~/.config/.jira/.config.yml login
  if [ ! -r "$config" ]; then
    echo "jira_login: ${config} not found or unreadable — run 'jira init' first" >&2
    return 1
  fi
  login=$(grep '^login:' "$config" | awk '{print $2}')
  if [ -z "$login" ]; then
    echo "jira_login: no 'login:' value in ${config}" >&2
    return 1
  fi
  printf '%s\n' "$login"
}
