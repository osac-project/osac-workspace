#!/usr/bin/env bash
# Smoke test for .claude/hooks/statusline.sh and update-ai-context.sh —
# specifically the workspace-root resolution that broke when Claude Code
# invokes these commands with cwd set to somewhere other than the workspace
# root (drifts as the agent cd's into component repos/worktrees). Run from
# osac-workspace: bash tools/test/claude-hooks-smoke.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
STATUSLINE="${ROOT}/.claude/hooks/statusline.sh"
UPDATE_CONTEXT="${ROOT}/.claude/hooks/update-ai-context.sh"
SETTINGS="${ROOT}/.claude/settings.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$STATUSLINE" ]] || fail "missing $STATUSLINE"
[[ -f "$UPDATE_CONTEXT" ]] || fail "missing $UPDATE_CONTEXT"
[[ -f "$SETTINGS" ]] || fail "missing $SETTINGS"

# --- Disposable sandbox: two throwaway repos + a fake $HOME, cleaned up on exit ---
# Overriding $HOME keeps these tests from touching the real user's
# ~/.claude/settings.json (statusline.sh chains to it) or ~/.ai-workflows.

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

make_repo() {
  local dir=$1 branch=$2
  mkdir -p "$dir"
  git -C "$dir" init -q -b "$branch"
  git -C "$dir" -c user.email=smoke@test -c user.name=smoke commit -q --allow-empty -m init
}

FAKE_HOME="${SANDBOX}/fake-home"
WORKSPACE_REPO="${SANDBOX}/workspace-repo"
mkdir -p "$FAKE_HOME"
make_repo "$WORKSPACE_REPO" "smoke-workspace-branch"
make_repo "${FAKE_HOME}/.ai-workflows" "smoke-ai-workflows-branch"

# Mirror the real repo layout inside the sandbox workspace repo so tests that
# exercise path resolution (not just internal logic) have a real script to
# invoke by relative/absolute path, the same way settings.json does.
mkdir -p "${WORKSPACE_REPO}/.claude/hooks"
cp "$STATUSLINE" "${WORKSPACE_REPO}/.claude/hooks/statusline.sh"
cp "$UPDATE_CONTEXT" "${WORKSPACE_REPO}/.claude/hooks/update-ai-context.sh"

# --- statusline.sh: $1 argument path ---

test_statusline_uses_passed_project_dir() {
  local out
  out=$(echo '{}' | HOME="$FAKE_HOME" bash "$STATUSLINE" "$WORKSPACE_REPO")
  echo "$out" | grep -q "smoke-workspace-branch" || fail "statusline (arg): workspace branch missing: $out"
  echo "$out" | grep -q "smoke-ai-workflows-branch" || fail "statusline (arg): ai-workflows branch missing: $out"
  pass "statusline.sh resolves workspace root from \$1 argument"
}

# --- statusline.sh: JSON fallback path (no $1) ---

test_statusline_falls_back_to_json_project_dir() {
  local payload out
  payload=$(printf '{"workspace":{"project_dir":"%s"}}' "$WORKSPACE_REPO")
  out=$(printf '%s' "$payload" | HOME="$FAKE_HOME" bash "$STATUSLINE")
  echo "$out" | grep -q "smoke-workspace-branch" || fail "statusline (json fallback): workspace branch missing: $out"
  pass "statusline.sh falls back to workspace.project_dir from JSON when \$1 is absent"
}

# --- statusline.sh: neither $1 nor JSON project_dir present — must not crash ---

test_statusline_handles_missing_project_dir_gracefully() {
  local out rc=0
  out=$(echo '{}' | HOME="$FAKE_HOME" bash "$STATUSLINE") || rc=$?
  [[ "$rc" -eq 0 ]] || fail "statusline (no project_dir): expected exit 0, got $rc"
  echo "$out" | grep -q "not found" || fail "statusline (no project_dir): expected graceful 'not found', got: $out"
  pass "statusline.sh degrades gracefully with no project_dir available"
}

# --- Regression: the actual configured settings.json command must survive cwd drift ---

test_settings_statusline_command_survives_cwd_drift() {
  local cmd payload out
  cmd=$(jq -r '.statusLine.command' "$SETTINGS")
  payload=$(printf '{"workspace":{"project_dir":"%s"}}' "$WORKSPACE_REPO")
  # Run from the sandbox root — a directory with no .claude/hooks/ of its
  # own — which is exactly the failure mode: cwd elsewhere in a multi-repo
  # checkout when Claude Code invokes the statusLine command.
  out=$(cd "$SANDBOX" && printf '%s' "$payload" | HOME="$FAKE_HOME" sh -c "$cmd")
  echo "$out" | grep -q "smoke-workspace-branch" || fail "settings.json statusLine command: cwd-independent resolution failed: $out"
  pass "settings.json statusLine command resolves correctly from a non-root cwd"
}

# --- update-ai-context.sh: CLAUDE_PROJECT_DIR resolution ---

test_update_context_uses_claude_project_dir() {
  local out rc=0
  out=$(cd "$SANDBOX" && CLAUDE_PROJECT_DIR="$WORKSPACE_REPO" HOME="$FAKE_HOME" bash "$UPDATE_CONTEXT" 2>&1) || rc=$?
  [[ "$rc" -eq 0 ]] || fail "update-ai-context.sh (CLAUDE_PROJECT_DIR): expected exit 0, got $rc: $out"
  echo "$out" | grep -q "smoke-workspace-branch" || fail "update-ai-context.sh: did not operate on \$CLAUDE_PROJECT_DIR repo: $out"
  pass "update-ai-context.sh resolves workspace root from \$CLAUDE_PROJECT_DIR"
}

# --- update-ai-context.sh: falls back to $0-relative derivation when unset ---

test_update_context_falls_back_without_claude_project_dir() {
  local out rc=0
  out=$(cd "$WORKSPACE_REPO" && HOME="$FAKE_HOME" bash .claude/hooks/update-ai-context.sh 2>&1) || rc=$?
  [[ "$rc" -eq 0 ]] || fail "update-ai-context.sh (fallback): expected exit 0, got $rc: $out"
  echo "$out" | grep -q "smoke-workspace-branch" || fail "update-ai-context.sh (fallback): did not resolve via \$0: $out"
  pass "update-ai-context.sh falls back to \$0-relative resolution when \$CLAUDE_PROJECT_DIR is unset"
}

echo "=== statusline.sh ==="
test_statusline_uses_passed_project_dir
test_statusline_falls_back_to_json_project_dir
test_statusline_handles_missing_project_dir_gracefully
test_settings_statusline_command_survives_cwd_drift

echo ""
echo "=== update-ai-context.sh ==="
test_update_context_uses_claude_project_dir
test_update_context_falls_back_without_claude_project_dir

echo ""
echo "All claude-hooks smoke tests passed."
