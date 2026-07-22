#!/usr/bin/env bash
# Detect which git remotes point to the upstream org and the developer's fork.
#
# Usage:
#   eval $(tools/resolve-remotes.sh [OPTIONS] [REPO_PATH])
#   tools/resolve-remotes.sh --print [REPO_PATH]
#
# Options:
#   --org ORG    GitHub org to detect as upstream (default: osac-project)
#   --print      Human-readable output instead of eval-able assignments
#   -h, --help   Show usage
#
# Output (eval mode):
#   UPSTREAM_REMOTE=origin
#   PUSH_REMOTE=fork
#
# Exit codes:
#   0  Upstream remote resolved (PUSH_REMOTE may be empty for read-only clones)
#   1  No remote matches the upstream org
#   2  Usage error
set -euo pipefail

ORG="osac-project"
PRINT=false
REPO_PATH=""

usage() {
  sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      [[ -n "${2:-}" ]] || { echo "error: --org requires a value" >&2; exit 2; }
      ORG="$2"; shift 2 ;;
    --print)  PRINT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "error: unknown option: $1" >&2; exit 2 ;;
    *)
      [[ -z "$REPO_PATH" ]] || { echo "error: unexpected argument: $1" >&2; exit 2; }
      REPO_PATH="$1"; shift ;;
  esac
done

REPO_PATH="${REPO_PATH:-.}"

if ! git -C "$REPO_PATH" rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: $REPO_PATH is not a git repository" >&2
  exit 2
fi

REPO_TOPLEVEL=$(git -C "$REPO_PATH" rev-parse --show-toplevel)
if [[ -n "$(git -C "$REPO_PATH" rev-parse --git-common-dir 2>/dev/null)" ]] \
   && [[ "$(git -C "$REPO_PATH" rev-parse --git-common-dir)" != "$(git -C "$REPO_PATH" rev-parse --git-dir)" ]]; then
  REPO_NAME=$(basename "$(git -C "$REPO_PATH" rev-parse --git-common-dir | sed 's|/\.git/worktrees/.*||; s|/\.git$||')")
else
  REPO_NAME=$(basename "$REPO_TOPLEVEL")
fi

ORG_ESC=$(printf '%s' "$ORG" | sed 's/[.+?{}()|\\[^$*]/\\&/g')
REPO_ESC=$(printf '%s' "$REPO_NAME" | sed 's/[.+?{}()|\\[^$*]/\\&/g')

UPSTREAM_REMOTE=""
PUSH_REMOTE=""
push_candidates=()

while IFS= read -r remote; do
  url=$(git -C "$REPO_PATH" remote get-url "$remote" 2>/dev/null || true)
  if echo "$url" | grep -qE "[:/]${ORG_ESC}/${REPO_ESC}(\\.git)?$"; then
    if [[ -z "$UPSTREAM_REMOTE" ]]; then
      UPSTREAM_REMOTE="$remote"
    fi
  else
    push_candidates+=("$remote")
  fi
done < <(git -C "$REPO_PATH" remote)

if [[ ${#push_candidates[@]} -eq 1 ]]; then
  PUSH_REMOTE="${push_candidates[0]}"
elif [[ ${#push_candidates[@]} -gt 1 ]]; then
  PUSH_REMOTE="${push_candidates[0]}"
  echo "warning: multiple push remote candidates: ${push_candidates[*]}; using '${PUSH_REMOTE}'" >&2
fi

if [[ -z "$UPSTREAM_REMOTE" ]]; then
  echo "error: no remote points to ${ORG}/${REPO_NAME}" >&2
  echo "  Add one (any name works): git -C $REPO_PATH remote add <name> https://github.com/${ORG}/${REPO_NAME}.git" >&2
  exit 1
fi

redact_url() {
  sed -E 's|://[^@]+@|://***@|'
}

if [[ "$PRINT" == true ]]; then
  echo "Repository:      ${REPO_NAME}"
  echo "Upstream remote:  ${UPSTREAM_REMOTE} ($(git -C "$REPO_PATH" remote get-url "$UPSTREAM_REMOTE" | redact_url))"
  if [[ -n "$PUSH_REMOTE" ]]; then
    echo "Push remote:      ${PUSH_REMOTE} ($(git -C "$REPO_PATH" remote get-url "$PUSH_REMOTE" | redact_url))"
  else
    echo "Push remote:      (none — read-only clone)"
  fi
else
  printf 'UPSTREAM_REMOTE=%q\n' "$UPSTREAM_REMOTE"
  printf 'PUSH_REMOTE=%q\n' "$PUSH_REMOTE"
fi
