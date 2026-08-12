#!/usr/bin/env bash
# Smoke test jira-safe-create.sh and affected skill patterns.
# Run from osac-workspace after bootstrap (or tools/link-agent-skills.sh) so
# skills/ is materialized from vendored osac-ai-skills:
#   bash tools/test/jira-skills-smoke.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
SOURCE="${ROOT}/tools/jira-safe-create.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$SOURCE" ]] || fail "missing $SOURCE"

# --- Library tests (tools/jira-safe-create.sh) ---

run_library_tests() {
  bash "${SCRIPT_DIR}/jira-safe-create-smoke.sh"
}

# --- Static checks on skill markdown ---

test_skills_reference_shared_script() {
  local skill
  for skill in jira-task-management report-bug capture-tasks-from-meeting-notes osac-feature; do
    grep -q 'jira-safe-create\.sh' "${ROOT}/skills/${skill}/SKILL.md" \
      || fail "${skill}: missing jira-safe-create.sh reference"
    pass "${skill}: references shared script"
  done
}

test_no_fixed_tmp_paths() {
  if rg -q '/tmp/(issue-body|jira-create)' "${ROOT}/skills/jira-task-management" \
      "${ROOT}/skills/report-bug" \
      "${ROOT}/skills/capture-tasks-from-meeting-notes" \
      "${ROOT}/skills/osac-feature" 2>/dev/null; then
    fail "fixed /tmp paths still present in skill docs"
  fi
  pass "no fixed /tmp create paths in affected skills"
}

test_no_inline_create_in_examples() {
  local skill file line
  for skill in report-bug capture-tasks-from-meeting-notes osac-feature; do
    file="${ROOT}/skills/${skill}/SKILL.md"
    while IFS= read -r line; do
      # Skip prohibition / prose lines
      [[ "$line" == *'never '* ]] && continue
      [[ "$line" == *'Never '* ]] && continue
      [[ "$line" == *'Do not '* ]] && continue
      fail "${skill}: inline KEY=\$(jira issue create...) pattern in example: ${line:0:80}"
    done < <(rg 'KEY=\$\(jira issue create' "$file" || true)
    pass "${skill}: no inline create antipattern in examples"
  done
}

test_osac_feature_no_duplicate_helpers() {
  if rg -q '^TEMP_FILES=\(\)' "${ROOT}/skills/osac-feature/SKILL.md"; then
    fail "osac-feature: inline TEMP_FILES block should be removed (use shared script)"
  fi
  pass "osac-feature: no duplicate temp helpers"
}

# --- Simulated create patterns (no jira calls) ---

source_helpers() {
  # shellcheck source=/dev/null
  source "$SOURCE"
}

test_source_from_git_root() {
  local resolved
  resolved=$(
    cd "$ROOT" && source "$(git rev-parse --show-toplevel)/tools/jira-safe-create.sh"
    new_temp smoke-root
  )
  [[ -n "$resolved" && -f "$resolved" ]] || fail "source via git rev-parse failed"
  rm -f "$resolved"
  pass "source via git rev-parse --show-toplevel"
}

simulate_single_create() {
  local label=$1
  local body out err key

  body=$(new_temp "${label}-body")
  add_temp "$body"
  out=$(new_temp "${label}-out")
  add_temp "$out"
  err=$(new_temp "${label}-err")
  add_temp "$err"

  cat >"$body" <<'EOF'
test issue body
EOF
  echo '{"key":"OSAC-9999"}' >"$out"
  : >"$err"

  key=$(jq -r '.key // empty' "$out")
  [[ "$key" == "OSAC-9999" ]] || fail "${label}: jq key parse failed"
  [[ -s "$body" ]] || fail "${label}: body temp empty"
}

test_jira_task_management_pattern() {
  (
    source_helpers
    simulate_single_create "jira-task-management"
  )
  pass "jira-task-management pattern (BODY/OUT/ERR + jq)"
}

test_report_bug_pattern() {
  (
    source_helpers
    simulate_single_create "report-bug"
  )
  pass "report-bug pattern (BODY/OUT/ERR + jq)"
}

test_meeting_notes_loop_pattern() {
  (
    source_helpers
    local i
    for i in 1 2; do
      simulate_single_create "meeting-task-${i}"
    done
  )
  pass "meeting-notes pattern (source once, per-task temps)"
}

test_osac_feature_multi_step_pattern() {
  (
    source_helpers
    # Feature create
    simulate_single_create "osac-feature"
    # Epic create (reuses OUT/ERR naming from skill)
    local out err
    out=$(new_temp osac-jira-epic-out)
    add_temp "$out"
    err=$(new_temp osac-jira-epic-err)
    add_temp "$err"
    echo '{"key":"OSAC-8888"}' >"$out"
    local epic_key
    epic_key=$(jq -r '.key // empty' "$out")
    [[ "$epic_key" == "OSAC-8888" ]] || fail "osac-feature epic key parse failed"
    # Bootstrap task
    simulate_single_create "osac-bootstrap-task"
  )
  pass "osac-feature pattern (feature + epic + task temps)"
}

test_require_osac_key_from_skill() {
  # Inline require_osac_key as documented in osac-feature (skill-specific, not in shared script)
  require_osac_key() {
    local key=$1 label=$2 out=$3 err=$4
    if ! [[ "${key}" =~ ^OSAC-[0-9]+$ ]]; then
      echo "Invalid or empty ${label} key: ${key:-<empty>}" >&2
      cat "$err" >&2
      exit 1
    fi
  }

  local out err
  out=$(mktemp)
  err=$(mktemp)
  echo '{"key":"OSAC-1234"}' >"$out"
  require_osac_key "OSAC-1234" "test" "$out" "$err"
  if (
    require_osac_key "" "test" "$out" "$err" 2>/dev/null
  ); then
    rm -f "$out" "$err"
    fail "require_osac_key should reject empty key"
  fi
  rm -f "$out" "$err"
  pass "osac-feature require_osac_key helper"
}

# --- Run all ---

echo "=== jira-safe-create library ==="
run_library_tests

echo ""
echo "=== skill documentation ==="
test_skills_reference_shared_script
test_no_fixed_tmp_paths
test_no_inline_create_in_examples
test_osac_feature_no_duplicate_helpers

echo ""
echo "=== skill create patterns (simulated) ==="
test_source_from_git_root
test_jira_task_management_pattern
test_report_bug_pattern
test_meeting_notes_loop_pattern
test_osac_feature_multi_step_pattern
test_require_osac_key_from_skill

echo ""
echo "All jira skill smoke tests passed."
