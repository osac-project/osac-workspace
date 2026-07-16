#!/usr/bin/env bash
# Backfill bootstrap epics: add bootstrap label; copy fixVersion from parent Feature.
#
# Requires jira-cli authenticated for OSAC (same as osac-feature skill).
# Default is dry-run — review output before applying writes.
#
# Usage:
#   tools/backfill-bootstrap-epics.sh [--dry-run]   # default: print planned edits
#   tools/backfill-bootstrap-epics.sh --apply       # execute Jira edits
#   tools/backfill-bootstrap-epics.sh --epic OSAC-NNNN [--dry-run|--apply]
#
# Query: project = OSAC AND type = Epic AND summary ~ "Bootstrap"
# Skips epics whose direct parent is not a Feature.
set -euo pipefail

MODE=dry-run
EPIC_FILTER=""

usage() {
  cat <<'EOF'
Backfill bootstrap epics with label and copied Feature fixVersion.

  tools/backfill-bootstrap-epics.sh [--dry-run] [--epic KEY]
  tools/backfill-bootstrap-epics.sh --apply [--epic KEY]

Options:
  --dry-run   Print planned edits only (default)
  --apply     Execute jira issue edit commands
  --epic KEY  Process a single epic (for testing)
  -h, --help  Show this help
EOF
}

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

parse_plain_keys() {
  tail -n +2 | while IFS= read -r line; do
    [ -z "$line" ] && continue
    key=$(printf '%s\n' "$line" | awk -F'\t' '$2 ~ /^OSAC-[0-9]+$/ {print $2; exit}')
    if [ -n "$key" ]; then
      echo "$key"
    else
      printf '%s\n' "$line" | grep -Eo 'OSAC-[0-9]+' | head -1
    fi
  done
}

list_bootstrap_epic_keys() {
  jira issue list -q 'project = OSAC AND type = Epic AND summary ~ "Bootstrap"' --plain \
    | parse_plain_keys
}

has_label() {
  local raw=$1 label=$2
  printf '%s' "$raw" | jq -e --arg l "$label" '.fields.labels[]? | select(. == $l)' >/dev/null 2>&1
}

epic_has_fix_version() {
  local raw=$1 version=$2
  printf '%s' "$raw" | jq -e --arg v "$version" '.fields.fixVersions[]?.name | select(. == $v)' >/dev/null 2>&1
}

epic_has_any_fix_version() {
  local raw=$1 count
  count=$(printf '%s' "$raw" | jq -r '[.fields.fixVersions[]?.name] | length')
  [ "${count:-0}" -gt 0 ]
}

# Takes the already-fetched parent Feature payload (see process_epic) rather
# than re-fetching by key — avoids a duplicate `jira issue view` per epic.
# Caller has already verified the parent is a Feature.
parent_feature_fix_version() {
  local parent_raw=$1 count version
  count=$(printf '%s' "$parent_raw" | jq -r '[.fields.fixVersions[]?.name] | length')
  if [ "${count:-0}" -ne 1 ]; then
    return 2
  fi
  version=$(printf '%s' "$parent_raw" | jq -r '.fields.fixVersions[0].name // empty')
  [ -n "$version" ] || return 1
  printf '%s' "$version"
}

process_epic() {
  local epic_key=$1
  local raw parent_key parent_raw parent_type needs_label=0 needs_version=0 version="" rc=0

  if ! raw=$(jira issue view "$epic_key" --raw 2>/dev/null); then
    warn "Could not load ${epic_key} — skipping"
    return 0
  fi

  parent_key=$(printf '%s' "$raw" | jq -r '.fields.parent.key // empty')
  if [ -z "$parent_key" ]; then
    warn "${epic_key}: no parent — skipping"
    return 0
  fi

  if ! parent_raw=$(jira issue view "$parent_key" --raw 2>/dev/null); then
    warn "${epic_key}: could not load parent ${parent_key} — skipping"
    return 0
  fi
  parent_type=$(printf '%s' "$parent_raw" | jq -r '.fields.issuetype.name // empty')
  if [ "$parent_type" != "Feature" ]; then
    warn "${epic_key}: parent ${parent_key} is ${parent_type:-unknown}, not Feature — skipping"
    return 0
  fi

  if ! has_label "$raw" "bootstrap"; then
    needs_label=1
  fi

  version=""
  rc=0
  version=$(parent_feature_fix_version "$parent_raw") || rc=$?
  if [ "$rc" -eq 2 ]; then
    warn "${epic_key}: parent ${parent_key} has 0 or multiple fixVersions — label only"
    version=""
  elif [ "$rc" -ne 0 ]; then
    warn "${epic_key}: could not read parent Feature fixVersion — label only"
    version=""
  elif [ -n "$version" ] && ! epic_has_fix_version "$raw" "$version"; then
    if epic_has_any_fix_version "$raw"; then
      warn "${epic_key}: epic already has a different fixVersion — skip version copy"
    else
      needs_version=1
    fi
  fi

  if [ "$needs_label" -eq 0 ] && [ "$needs_version" -eq 0 ]; then
    log "OK ${epic_key}: no changes needed"
    return 0
  fi

  local actions=()
  [ "$needs_label" -eq 1 ] && actions+=("add label bootstrap")
  [ "$needs_version" -eq 1 ] && actions+=("copy fixVersion ${version}")

  if [ "$MODE" = "dry-run" ]; then
    log "DRY-RUN ${epic_key} (parent ${parent_key}): ${actions[*]}"
    return 0
  fi

  local edit_args=()
  [ "$needs_label" -eq 1 ] && edit_args+=(-l bootstrap)
  [ "$needs_version" -eq 1 ] && edit_args+=(--fix-version "$version")

  # set -e is active; a single failed edit must not abort the remaining ~70
  # epics, so capture the status explicitly instead of letting it propagate.
  if jira issue edit "$epic_key" "${edit_args[@]}" --no-input </dev/null; then
    log "APPLIED ${epic_key}: ${actions[*]}"
  else
    warn "${epic_key}: edit failed (${actions[*]}) — set manually and re-run with --epic ${epic_key}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE=dry-run; shift ;;
    --apply) MODE=apply; shift ;;
    --epic)
      [ $# -ge 2 ] || { echo "Missing value for --epic" >&2; exit 1; }
      EPIC_FILTER=$2
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if ! command -v jira >/dev/null 2>&1; then
  echo "jira CLI not found in PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found in PATH" >&2
  exit 1
fi

if [ -n "$EPIC_FILTER" ]; then
  if ! [[ "$EPIC_FILTER" =~ ^OSAC-[0-9]+$ ]]; then
    echo "Invalid epic key: ${EPIC_FILTER}" >&2
    exit 1
  fi
  epic_keys=("$EPIC_FILTER")
else
  epic_keys=()
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    epic_keys+=("$k")
  done < <(list_bootstrap_epic_keys)
fi

if [ "${#epic_keys[@]}" -eq 0 ]; then
  log "No bootstrap epics found."
  exit 0
fi

log "Mode: ${MODE}; epics: ${#epic_keys[@]}"

for epic_key in "${epic_keys[@]}"; do
  [ -z "$epic_key" ] && continue
  process_epic "$epic_key"
  sleep 1
done
