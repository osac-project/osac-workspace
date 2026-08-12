#!/usr/bin/env bash
# Smoke test: osac-workspace consumer wrapper for osac-ai-skills fan-out.
# Run from osac-workspace: bash tools/test/link-agent-skills-consumer-smoke.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
WRAPPER="${REPO_ROOT}/tools/link-agent-skills.sh"
# Prefer Task-1 fan-out (PROJECT_ROOT) from sibling checkout or vendored clone.
VENDOR_FANOUT=""
for candidate in \
  "${REPO_ROOT}/../osac-ai-skills/tools/link-agent-skills.sh" \
  "${REPO_ROOT}/.osac-ai-skills/tools/link-agent-skills.sh"; do
  if [[ -f "$candidate" ]] && grep -q 'PROJECT_ROOT:-' "$candidate" 2>/dev/null; then
    VENDOR_FANOUT=$(cd "$(dirname "$candidate")" && pwd)/link-agent-skills.sh
    break
  fi
done

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$WRAPPER" ]] || fail "missing $WRAPPER"
[[ -x "$WRAPPER" ]] || fail "$WRAPPER is not executable"
[[ -n "$VENDOR_FANOUT" ]] || fail "no PROJECT_ROOT-capable fan-out found (merge/land OSAC-3956 Task 1 first)"

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

seed_vendor() {
  local ws="$1"
  local vendor="${ws}/.osac-ai-skills"
  mkdir -p "${vendor}/tools" "${vendor}/skills"
  cp "$VENDOR_FANOUT" "${vendor}/tools/link-agent-skills.sh"
  chmod +x "${vendor}/tools/link-agent-skills.sh"

  # Minimal native skills the vendored verify_osac_skills list requires —
  # symlink from the real skills tree when available, else stub files.
  local real_skills=""
  for candidate in \
    "${REPO_ROOT}/../osac-ai-skills/skills" \
    "${REPO_ROOT}/.osac-ai-skills/skills" \
    "${REPO_ROOT}/skills"; do
    if [[ -d "${candidate}/create-pr" ]]; then
      real_skills=$(cd "$candidate" && pwd -P)
      break
    fi
  done
  [[ -n "$real_skills" ]] || fail "cannot locate a real skills/create-pr tree for fixtures"

  local name
  for name in browser-demo-recording capture-tasks-from-meeting-notes create-pr \
    design-review generate-status-report github-actions-workflows jira-task-management \
    milestone-scope osac-cluster osac-demo-recording osac-feature osac-release \
    performance-review prd-review presentation quick-fix report-bug review-gate \
    security-review; do
    if [[ -d "${real_skills}/${name}" ]]; then
      ln -sfn "${real_skills}/${name}" "${vendor}/skills/${name}"
    else
      mkdir -p "${vendor}/skills/${name}"
      echo "# stub ${name}" >"${vendor}/skills/${name}/SKILL.md"
    fi
  done
}

install_wrapper() {
  local ws="$1"
  mkdir -p "${ws}/tools"
  cp "$WRAPPER" "${ws}/tools/link-agent-skills.sh"
  chmod +x "${ws}/tools/link-agent-skills.sh"
}

test_missing_vendor_fails() {
  local ws
  ws=$(mktemp -d "${TMPDIR_ROOT}/missing.XXXXXX")
  install_wrapper "$ws"
  local rc=0
  (cd "$ws" && ./tools/link-agent-skills.sh --claude) >/dev/null 2>&1 || rc=$?
  [[ "$rc" -ne 0 ]] || fail "expected non-zero exit when vendor missing"
  pass "missing vendor dir fails loudly"
}

test_materialize_and_link() {
  local ws
  ws=$(mktemp -d "${TMPDIR_ROOT}/ok.XXXXXX")
  seed_vendor "$ws"
  install_wrapper "$ws"

  # Stub ai-workflows for --with-ai-workflows (default path via wrapper).
  mkdir -p "${ws}/.ai-workflows/bugfix" \
    "${ws}/.ai-workflows/design" \
    "${ws}/.ai-workflows/e2e" \
    "${ws}/.ai-workflows/implement" \
    "${ws}/.ai-workflows/prd" \
    "${ws}/.ai-workflows/_shared"
  echo '# stub' >"${ws}/.ai-workflows/bugfix/SKILL.md"
  echo '# stub' >"${ws}/.ai-workflows/design/SKILL.md"
  echo '# stub' >"${ws}/.ai-workflows/e2e/SKILL.md"
  echo '# stub' >"${ws}/.ai-workflows/implement/SKILL.md"
  echo '# stub' >"${ws}/.ai-workflows/prd/SKILL.md"

  (cd "$ws" && ./tools/link-agent-skills.sh --all --with-ai-workflows) >/dev/null

  [[ -L "${ws}/skills/create-pr" ]] || fail "skills/create-pr is not a symlink"
  [[ -r "${ws}/skills/create-pr/SKILL.md" ]] || fail "cannot read create-pr via skills/"
  local target
  target=$(readlink "${ws}/skills/create-pr")
  [[ "$target" = /* ]] || fail "expected absolute symlink target, got: $target"

  [[ -L "${ws}/.claude/skills" ]] || fail ".claude/skills is not a symlink"
  [[ -r "${ws}/.claude/skills/create-pr/SKILL.md" ]] || fail "cannot read create-pr via .claude/skills"
  [[ -L "${ws}/skills/bugfix" ]] || fail "expected skills/bugfix from --with-ai-workflows"
  pass "materialize + vendored fan-out links consumer tree"
}

test_refuse_real_skill_directory() {
  local ws
  ws=$(mktemp -d "${TMPDIR_ROOT}/refuse.XXXXXX")
  seed_vendor "$ws"
  install_wrapper "$ws"
  mkdir -p "${ws}/skills/create-pr"
  echo "real leftover" >"${ws}/skills/create-pr/SKILL.md"

  local rc=0
  local err
  err=$(cd "$ws" && ./tools/link-agent-skills.sh --claude 2>&1) || rc=$?
  [[ "$rc" -ne 0 ]] || fail "expected failure when skills/create-pr is a real directory"
  echo "$err" | grep -qi 'not a symlink\|refusing\|real directory' \
    || fail "expected refusal message, got: $err"
  pass "refuses to replace a real skill directory"
}

test_missing_vendor_fails
test_materialize_and_link
test_refuse_real_skill_directory

echo "All link-agent-skills consumer smoke tests passed."
