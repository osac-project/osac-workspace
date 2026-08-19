#!/usr/bin/env bash
# Smoke test for tools/check-mandatory-reviewers.sh — run from osac-workspace:
#   bash tools/test/check-mandatory-reviewers-smoke.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="${SCRIPT_DIR}/../check-mandatory-reviewers.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$SCRIPT" ]] || fail "missing $SCRIPT"
[[ -x "$SCRIPT" ]] || fail "$SCRIPT is not executable"

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

write_config() {
  cat > "$TMPDIR_ROOT/config.yaml"
}

test_real_config_passes() {
  bash "$SCRIPT" "${SCRIPT_DIR}/../../skills/.config/create-pr-reviewers.yaml" \
    || fail "the real, current config should pass"
  pass "real config passes"
}

test_missing_entry_fails() {
  write_config <<'EOF'
reviewers:
  - name: performance-review
    skill: skills/performance-review/SKILL.md
    category: Performance
    base: main
    enabled: true

prompt_template: |
  placeholder {skill} {base} {category} {repo_dir}
EOF
  if bash "$SCRIPT" "$TMPDIR_ROOT/config.yaml" 2>/dev/null; then
    fail "expected failure when security-review entry is missing"
  fi
  pass "missing security-review entry fails"
}

test_missing_mandatory_fails() {
  write_config <<'EOF'
reviewers:
  - name: security-review
    skill: skills/security-review/SKILL.md
    category: Security
    base: main
    enabled: true

prompt_template: |
  placeholder {skill} {base} {category} {repo_dir}
EOF
  if bash "$SCRIPT" "$TMPDIR_ROOT/config.yaml" 2>/dev/null; then
    fail "expected failure when mandatory: true is missing"
  fi
  pass "missing mandatory: true fails"
}

test_disabled_fails() {
  write_config <<'EOF'
reviewers:
  - name: security-review
    skill: skills/security-review/SKILL.md
    category: Security
    base: main
    enabled: false
    mandatory: true

prompt_template: |
  placeholder {skill} {base} {category} {repo_dir}
EOF
  if bash "$SCRIPT" "$TMPDIR_ROOT/config.yaml" 2>/dev/null; then
    fail "expected failure when enabled: false is set alongside mandatory: true"
  fi
  pass "enabled: false alongside mandatory: true fails"
}

test_valid_config_passes() {
  write_config <<'EOF'
reviewers:
  - name: performance-review
    skill: skills/performance-review/SKILL.md
    category: Performance
    base: main
    enabled: true

  - name: security-review
    skill: skills/security-review/SKILL.md
    category: Security
    base: main
    enabled: true
    mandatory: true

prompt_template: |
  placeholder {skill} {base} {category} {repo_dir}
EOF
  bash "$SCRIPT" "$TMPDIR_ROOT/config.yaml" || fail "expected a valid config to pass"
  pass "valid config with mandatory security-review passes"
}

test_real_config_passes
test_missing_entry_fails
test_missing_mandatory_fails
test_disabled_fails
test_valid_config_passes

echo "All check-mandatory-reviewers smoke tests passed."
