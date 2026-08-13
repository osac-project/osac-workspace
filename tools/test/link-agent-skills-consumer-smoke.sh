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

# Isolate HOME so fixtures never pick up the developer's ~/.osac-ai-skills.
run_wrapper() {
  local ws="$1"
  shift
  mkdir -p "${ws}/home"
  (cd "$ws" && HOME="${ws}/home" ./tools/link-agent-skills.sh "$@")
}

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

  # Shared rules/agents/design-context (OSAC-4006): stub the same filenames
  # the vendored script's SHARED_RULES/SHARED_AGENTS/SHARED_DESIGN_CONTEXT
  # arrays expect, so materialize_shared_dir has real files to link to.
  # reference/*.md (ARCHITECTURE.md and siblings) is NOT part of this
  # fan-out — it's a codebase-analysis snapshot, not portable skill
  # guidance; placement deferred to OSAC-4008. reference/ stays a real,
  # workspace-local directory, untouched by this script.
  mkdir -p "${vendor}/.claude/rules" "${vendor}/.claude/agents" "${vendor}/.design/context"
  for name in architecture-patterns networking-design-alignment request-path-tracing; do
    echo "# stub ${name}" >"${vendor}/.claude/rules/${name}.md"
  done
  for name in quick-fix; do
    echo "# stub ${name}" >"${vendor}/.claude/agents/${name}.md"
  done
  for name in enclave-wizard-pipeline networking-decisions osac-dimensions review-patterns; do
    echo "# stub ${name}" >"${vendor}/.design/context/${name}.md"
  done
}

install_wrapper() {
  local ws="$1"
  mkdir -p "${ws}/tools" "${ws}/home"
  cp "$WRAPPER" "${ws}/tools/link-agent-skills.sh"
  chmod +x "${ws}/tools/link-agent-skills.sh"
}

test_missing_vendor_fails() {
  local ws
  ws=$(mktemp -d "${TMPDIR_ROOT}/missing.XXXXXX")
  install_wrapper "$ws"
  local rc=0
  run_wrapper "$ws" --claude >/dev/null 2>&1 || rc=$?
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

  run_wrapper "$ws" --all --with-ai-workflows >/dev/null

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

test_shared_rules_agents_design_context() {
  local ws
  ws=$(mktemp -d "${TMPDIR_ROOT}/shared.XXXXXX")
  seed_vendor "$ws"
  install_wrapper "$ws"

  run_wrapper "$ws" --claude >/dev/null

  [[ -L "${ws}/.claude/rules/architecture-patterns.md" ]] \
    || fail "expected .claude/rules/architecture-patterns.md to be a symlink"
  [[ -r "${ws}/.claude/rules/architecture-patterns.md" ]] \
    || fail "cannot read .claude/rules/architecture-patterns.md via symlink"
  [[ -L "${ws}/.claude/agents/quick-fix.md" ]] \
    || fail "expected .claude/agents/quick-fix.md to be a symlink"
  [[ -r "${ws}/.claude/agents/quick-fix.md" ]] \
    || fail "cannot read .claude/agents/quick-fix.md via symlink"
  [[ -L "${ws}/.design/context/osac-dimensions.md" ]] \
    || fail "expected .design/context/osac-dimensions.md to be a symlink"
  [[ -r "${ws}/.design/context/osac-dimensions.md" ]] \
    || fail "cannot read .design/context/osac-dimensions.md via symlink"
  pass "materializes shared rules/agents/design-context"
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
  err=$(run_wrapper "$ws" --claude 2>&1) || rc=$?
  [[ "$rc" -ne 0 ]] || fail "expected failure when skills/create-pr is a real directory"
  echo "$err" | grep -qi 'not a symlink\|refusing\|real directory' \
    || fail "expected refusal message, got: $err"
  pass "refuses to replace a real skill directory"
}

test_prunes_removed_vendor_skill() {
  local ws
  ws=$(mktemp -d "${TMPDIR_ROOT}/prune.XXXXXX")
  seed_vendor "$ws"
  install_wrapper "$ws"
  mkdir -p "${ws}/.osac-ai-skills/skills/obsolete-skill"
  echo '# obsolete' >"${ws}/.osac-ai-skills/skills/obsolete-skill/SKILL.md"

  run_wrapper "$ws" --claude >/dev/null
  [[ -L "${ws}/skills/obsolete-skill" ]] || fail "expected obsolete-skill link after first materialize"

  rm -rf "${ws}/.osac-ai-skills/skills/obsolete-skill"
  run_wrapper "$ws" --claude >/dev/null
  [[ ! -e "${ws}/skills/obsolete-skill" && ! -L "${ws}/skills/obsolete-skill" ]] \
    || fail "expected obsolete-skill symlink to be pruned after vendor removal"
  [[ -L "${ws}/skills/create-pr" ]] || fail "create-pr should still be linked after prune"
  pass "prunes stale vendor skill symlinks"
}

test_verify_rejects_removed_canonical_file() {
  local ws
  ws=$(mktemp -d "${TMPDIR_ROOT}/verify-removed.XXXXXX")
  seed_vendor "$ws"
  install_wrapper "$ws"

  run_wrapper "$ws" --claude >/dev/null
  run_wrapper "$ws" --claude --verify >/dev/null \
    || fail "expected --verify to pass before canonical file removal"

  # Simulate a canonical shared rule vanishing out from under an
  # otherwise-present consumer symlink (e.g. mid-migration deletion).
  rm -f "${ws}/.osac-ai-skills/.claude/rules/architecture-patterns.md"
  [[ -L "${ws}/.claude/rules/architecture-patterns.md" ]] \
    || fail "expected stale symlink to remain after canonical file removal"

  local rc=0
  local err
  err=$(run_wrapper "$ws" --claude --verify 2>&1) || rc=$?
  [[ "$rc" -ne 0 ]] || fail "expected --verify to fail after canonical file removal"
  echo "$err" | grep -qi 'missing or unreadable' \
    || fail "expected missing-canonical-source error, got: $err"
  pass "--verify rejects a symlink whose canonical file was removed"
}

test_vendor_override_env_var_is_authoritative() {
  local ws
  ws=$(mktemp -d "${TMPDIR_ROOT}/override.XXXXXX")
  seed_vendor "$ws"
  install_wrapper "$ws"

  # Seed a second, distinguishable vendor at the home path -- the wrapper's
  # own default resolution checks HOME first, so without the override it
  # would pick this one instead of the project-local vendor passed via the
  # env var. Reproduces the bug where bootstrap.sh resolves/clones one vendor
  # dir but the wrapper it invokes independently re-resolves and silently
  # picks a different one (e.g. a stale ~/.osac-ai-skills that bootstrap.sh
  # already rejected in favor of a fresh ./.osac-ai-skills clone).
  local home_vendor="${ws}/home/.osac-ai-skills"
  mkdir -p "${home_vendor}/tools" "${home_vendor}/skills/create-pr"
  cp "$VENDOR_FANOUT" "${home_vendor}/tools/link-agent-skills.sh"
  chmod +x "${home_vendor}/tools/link-agent-skills.sh"
  echo '# stub create-pr (home vendor -- must NOT be used)' >"${home_vendor}/skills/create-pr/SKILL.md"

  local project_vendor="${ws}/.osac-ai-skills"
  (cd "$ws" && HOME="${ws}/home" OSAC_AI_SKILLS_VENDOR_DIR="${project_vendor}" \
    ./tools/link-agent-skills.sh --claude >/dev/null) \
    || fail "wrapper run with OSAC_AI_SKILLS_VENDOR_DIR override failed"

  grep -q "home vendor" "${ws}/skills/create-pr/SKILL.md" \
    && fail "override was ignored -- wrapper used the home vendor instead of OSAC_AI_SKILLS_VENDOR_DIR"
  [[ -r "${ws}/skills/create-pr/SKILL.md" ]] || fail "expected create-pr to resolve via the overridden vendor"

  local rc=0
  local err
  err=$(cd "$ws" && HOME="${ws}/home" OSAC_AI_SKILLS_VENDOR_DIR="${ws}/no-such-vendor" \
    ./tools/link-agent-skills.sh --claude 2>&1) || rc=$?
  [[ "$rc" -ne 0 ]] || fail "expected failure for an invalid OSAC_AI_SKILLS_VENDOR_DIR (no silent fallback)"
  echo "$err" | grep -qi 'OSAC_AI_SKILLS_VENDOR_DIR' \
    || fail "expected error to reference OSAC_AI_SKILLS_VENDOR_DIR, got: $err"
  pass "OSAC_AI_SKILLS_VENDOR_DIR override is authoritative (no independent re-resolution, no silent fallback)"
}

test_missing_vendor_fails
test_materialize_and_link
test_shared_rules_agents_design_context
test_refuse_real_skill_directory
test_prunes_removed_vendor_skill
test_verify_rejects_removed_canonical_file
test_vendor_override_env_var_is_authoritative

echo "All link-agent-skills consumer smoke tests passed."
