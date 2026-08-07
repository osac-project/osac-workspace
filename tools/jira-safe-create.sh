#!/usr/bin/env bash
# Temp-file and Jira-credential helpers for jira-cli safe create (mktemp +
# EXIT trap cleanup, plus jira_login()/jira_token() for skills that need
# direct REST calls).
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

# Jira API token for the same `curl -K -` credentials, preferring
# $JIRA_API_TOKEN and falling back to the password field of the
# `machine redhat.atlassian.net` entry in ~/.netrc — the same file
# jira-cli itself authenticates from (see jira-task-management/SKILL.md's
# "Auth: Bearer token in ~/.netrc" setup). Assumes a single-line netrc
# entry (`machine redhat.atlassian.net login <user> password <token>`),
# matching this repo's documented format; does not handle netrc's
# multi-line or `macdef` syntax. Returns 1 if neither source has a token.
jira_token() {
  if [ -n "${JIRA_API_TOKEN:-}" ]; then
    printf '%s\n' "$JIRA_API_TOKEN"
    return 0
  fi
  local netrc=~/.netrc token
  if [ ! -r "$netrc" ]; then
    echo "jira_token: \$JIRA_API_TOKEN not set and ${netrc} not found or unreadable" >&2
    return 1
  fi
  token=$(awk '
    /^machine[[:space:]]+redhat\.atlassian\.net([[:space:]]|$)/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "password" && i < NF) { print $(i + 1); exit }
      }
    }
  ' "$netrc")
  if [ -z "$token" ]; then
    echo "jira_token: \$JIRA_API_TOKEN not set and no 'machine redhat.atlassian.net' password entry in ${netrc}" >&2
    return 1
  fi
  printf '%s\n' "$token"
}
