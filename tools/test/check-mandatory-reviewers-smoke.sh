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

expect_pass() {
  local label=$1
  bash "$SCRIPT" "$TMPDIR_ROOT/config.yaml" >/dev/null 2>&1 || fail "expected pass: $label"
  pass "$label"
}

expect_fail() {
  local label=$1
  if bash "$SCRIPT" "$TMPDIR_ROOT/config.yaml" >/dev/null 2>&1; then
    fail "expected failure: $label"
  fi
  pass "$label"
}

VALID_TEMPLATE='reviewers:
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
'

test_real_config_passes() {
  bash "$SCRIPT" "${SCRIPT_DIR}/../../skills/.config/create-pr-reviewers.yaml" \
    || fail "the real, current config should pass"
  pass "real config passes"
}

test_valid_config_passes() {
  printf '%s' "$VALID_TEMPLATE" | write_config
  expect_pass "valid config with mandatory security-review passes"
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
  expect_fail "missing security-review entry fails"
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
  expect_fail "missing mandatory: true fails"
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
  expect_fail "enabled: false alongside mandatory: true fails"
}

# The remaining tests each cover a specific bypass a naive text-pattern
# checker was found vulnerable to (see commit history) — a real YAML parser
# should reject all of them.

test_boolean_spelling_variants_fail() {
  local variant
  for variant in "False" "no" "off" "FALSE"; do
    write_config <<EOF
reviewers:
  - name: security-review
    skill: skills/security-review/SKILL.md
    category: Security
    base: main
    enabled: ${variant}
    mandatory: true

prompt_template: |
  placeholder {skill} {base} {category} {repo_dir}
EOF
    expect_fail "enabled: ${variant} (alternate YAML boolean-false spelling) fails"
  done
}

test_repointed_skill_fails() {
  write_config <<'EOF'
reviewers:
  - name: security-review
    skill: skills/performance-review/SKILL.md
    category: Security
    base: main
    enabled: true
    mandatory: true

prompt_template: |
  placeholder {skill} {base} {category} {repo_dir}
EOF
  expect_fail "security-review entry repointed to a different skill file fails"
}

test_decoy_entry_does_not_hide_missing_mandatory() {
  write_config <<'EOF'
reviewers:
  - name: security-review
    skill: skills/security-review/SKILL.md
    category: Security
    base: main
    enabled: true

  - name: security-review-legacy
    skill: skills/security-review/SKILL.md
    category: Security
    base: main
    enabled: true
    mandatory: true

prompt_template: |
  placeholder {skill} {base} {category} {repo_dir}
EOF
  expect_fail "real security-review entry missing mandatory: true is not masked by a same-prefix decoy entry"
}

test_unrelated_similarly_named_entry_disabled_does_not_false_fail() {
  write_config <<'EOF'
reviewers:
  - name: security-review
    skill: skills/security-review/SKILL.md
    category: Security
    base: main
    enabled: true
    mandatory: true

  - name: security-review-experimental
    skill: skills/security-review/SKILL.md
    category: SecurityExperimental
    base: main
    enabled: false

prompt_template: |
  placeholder {skill} {base} {category} {repo_dir}
EOF
  expect_pass "a disabled, unrelated entry whose name merely contains 'security-review' does not falsely fail the real entry"
}

test_commented_out_mandatory_fails() {
  write_config <<'EOF'
reviewers:
  - name: security-review
    skill: skills/security-review/SKILL.md
    category: Security
    base: main
    enabled: true
    # downgraded from mandatory: true per team decision

prompt_template: |
  placeholder {skill} {base} {category} {repo_dir}
EOF
  expect_fail "a commented-out 'mandatory: true' line does not satisfy the requirement"
}

test_real_config_passes
test_valid_config_passes
test_missing_entry_fails
test_missing_mandatory_fails
test_disabled_fails
test_boolean_spelling_variants_fail
test_repointed_skill_fails
test_decoy_entry_does_not_hide_missing_mandatory
test_unrelated_similarly_named_entry_disabled_does_not_false_fail
test_commented_out_mandatory_fails

echo "All check-mandatory-reviewers smoke tests passed."
