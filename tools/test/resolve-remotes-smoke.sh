#!/usr/bin/env bash
# Smoke test for tools/resolve-remotes.sh — run from osac-workspace:
#   bash tools/test/resolve-remotes-smoke.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="${SCRIPT_DIR}/../resolve-remotes.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$SCRIPT" ]] || fail "missing $SCRIPT"
[[ -x "$SCRIPT" ]] || fail "$SCRIPT is not executable"

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

make_repo() {
  local dir="$TMPDIR_ROOT/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" -c user.name=test -c user.email=test@test commit --allow-empty -m "init" -q
  echo "$dir"
}

test_standard_bootstrap_naming() {
  local repo
  repo=$(make_repo "standard")
  git -C "$repo" remote add origin "https://github.com/osac-project/standard.git"
  git -C "$repo" remote add fork "git@github.com:dev/standard.git"
  local out
  out=$("$SCRIPT" "$repo")
  echo "$out" | grep -q "UPSTREAM_REMOTE=origin" || fail "expected UPSTREAM_REMOTE=origin, got: $out"
  echo "$out" | grep -q "PUSH_REMOTE=fork" || fail "expected PUSH_REMOTE=fork, got: $out"
  pass "standard bootstrap naming (origin=upstream, fork=push)"
}

test_reversed_naming() {
  local repo
  repo=$(make_repo "reversed")
  git -C "$repo" remote add origin "git@github.com:dev/reversed.git"
  git -C "$repo" remote add upstream "https://github.com/osac-project/reversed.git"
  local out
  out=$("$SCRIPT" "$repo")
  echo "$out" | grep -q "UPSTREAM_REMOTE=upstream" || fail "expected UPSTREAM_REMOTE=upstream, got: $out"
  echo "$out" | grep -q "PUSH_REMOTE=origin" || fail "expected PUSH_REMOTE=origin, got: $out"
  pass "reversed naming (origin=fork, upstream=upstream)"
}

test_no_upstream() {
  local repo
  repo=$(make_repo "noupstream")
  git -C "$repo" remote add myremote "git@github.com:dev/noupstream.git"
  local rc=0
  "$SCRIPT" "$repo" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 1 ]] || fail "expected exit code 1 when no upstream remote, got $rc"
  pass "exit code 1 when no upstream remote"
}

test_read_only_clone() {
  local repo
  repo=$(make_repo "readonly")
  git -C "$repo" remote add origin "https://github.com/osac-project/readonly.git"
  local out
  out=$("$SCRIPT" "$repo")
  echo "$out" | grep -q "UPSTREAM_REMOTE=origin" || fail "expected UPSTREAM_REMOTE=origin, got: $out"
  echo "$out" | grep -q "PUSH_REMOTE=" || fail "expected PUSH_REMOTE= in output, got: $out"
  eval "$out"
  [[ -z "$PUSH_REMOTE" ]] || fail "expected empty PUSH_REMOTE after eval, got: $PUSH_REMOTE"
  pass "read-only clone (no push remote)"
}

test_custom_org() {
  local repo
  repo=$(make_repo "customorg")
  git -C "$repo" remote add origin "https://github.com/my-org/customorg.git"
  local out
  out=$("$SCRIPT" --org my-org "$repo")
  echo "$out" | grep -q "UPSTREAM_REMOTE=origin" || fail "expected UPSTREAM_REMOTE=origin, got: $out"
  pass "custom org via --org flag"
}

test_print_mode() {
  local repo
  repo=$(make_repo "printmode")
  git -C "$repo" remote add origin "https://github.com/osac-project/printmode.git"
  git -C "$repo" remote add fork "git@github.com:dev/printmode.git"
  local out
  out=$("$SCRIPT" --print "$repo")
  echo "$out" | grep -q "Repository:" || fail "expected Repository: in print output"
  echo "$out" | grep -q "Upstream remote:" || fail "expected Upstream remote: in print output"
  echo "$out" | grep -q "Push remote:" || fail "expected Push remote: in print output"
  pass "print mode output"
}

test_idempotent() {
  local repo
  repo=$(make_repo "idempotent")
  git -C "$repo" remote add origin "https://github.com/osac-project/idempotent.git"
  git -C "$repo" remote add fork "git@github.com:dev/idempotent.git"
  local out1 out2
  out1=$("$SCRIPT" "$repo")
  out2=$("$SCRIPT" "$repo")
  [[ "$out1" == "$out2" ]] || fail "non-idempotent output: '$out1' vs '$out2'"
  pass "idempotent (two runs produce same output)"
}

test_not_a_repo() {
  local dir="$TMPDIR_ROOT/not-a-repo"
  mkdir -p "$dir"
  local rc=0
  "$SCRIPT" "$dir" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] || fail "expected exit code 2 for non-repo directory, got $rc"
  pass "exit code 2 for non-git directory"
}

test_eval_integration() {
  local repo
  repo=$(make_repo "evaltest")
  git -C "$repo" remote add upstream "https://github.com/osac-project/evaltest.git"
  git -C "$repo" remote add origin "git@github.com:dev/evaltest.git"
  eval "$("$SCRIPT" "$repo")"
  [[ "$UPSTREAM_REMOTE" == "upstream" ]] || fail "eval: UPSTREAM_REMOTE=$UPSTREAM_REMOTE, expected upstream"
  [[ "$PUSH_REMOTE" == "origin" ]] || fail "eval: PUSH_REMOTE=$PUSH_REMOTE, expected origin"
  pass "eval integration (variables set in calling shell)"
}

test_worktree() {
  local repo
  repo=$(make_repo "worktree-main")
  git -C "$repo" remote add origin "https://github.com/osac-project/worktree-main.git"
  git -C "$repo" remote add fork "git@github.com:dev/worktree-main.git"
  local wt="$TMPDIR_ROOT/worktree-fix"
  git -C "$repo" worktree add "$wt" -b fix-branch -q
  local out
  out=$("$SCRIPT" "$wt")
  echo "$out" | grep -q "UPSTREAM_REMOTE=origin" || fail "worktree: expected UPSTREAM_REMOTE=origin, got: $out"
  echo "$out" | grep -q "PUSH_REMOTE=fork" || fail "worktree: expected PUSH_REMOTE=fork, got: $out"
  git -C "$repo" worktree remove "$wt" 2>/dev/null
  pass "worktree (repo name resolved from main repo, not worktree dir)"
}

test_standard_bootstrap_naming
test_reversed_naming
test_no_upstream
test_read_only_clone
test_custom_org
test_print_mode
test_idempotent
test_not_a_repo
test_eval_integration
test_worktree

echo ""
echo "All resolve-remotes smoke tests passed."
