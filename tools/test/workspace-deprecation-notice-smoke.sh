#!/usr/bin/env bash
# Smoke test for the osac-workspace deprecation notice on ./bootstrap.sh.
# Run from osac-workspace: bash tools/test/workspace-deprecation-notice-smoke.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
BOOTSTRAP="${ROOT}/bootstrap.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$BOOTSTRAP" ]] || fail "missing $BOOTSTRAP"

contains() {
  local haystack=$1 needle=$2
  grep -Fq -- "$needle" <<<"$haystack"
}

assert_notice_bullets() {
  local haystack=$1 label=$2
  contains "$haystack" "New work is in" || fail "$label missing 'New work is in'"
  contains "$haystack" "osac-project/osac" || fail "$label missing 'osac-project/osac'"
  contains "$haystack" "Do not start a new osac-workspace checkout" || fail "$label missing 'Do not start a new osac-workspace checkout'"
  contains "$haystack" "osac/tools/bootstrap.sh" || fail "$label missing 'osac/tools/bootstrap.sh'"
  contains "$haystack" "osac-workspace/osac" || fail "$label missing 'osac-workspace/osac'"
  contains "$haystack" "Clone osac-project/osac and run tools/bootstrap.sh there" || fail "$label missing clone-and-bootstrap sentence"
}

help_out=$(cd "$ROOT" && ./bootstrap.sh --help)
help_rc=$?
[[ "$help_rc" -eq 0 ]] || fail "./bootstrap.sh --help exited $help_rc"
pass "./bootstrap.sh --help exits 0"

assert_notice_bullets "$help_out" "./bootstrap.sh --help stdout"
pass "./bootstrap.sh --help stdout contains the deprecation bullets"

contains "$help_out" "Usage: ./bootstrap.sh" || fail "./bootstrap.sh --help stdout missing usage text"
pass "./bootstrap.sh --help still prints usage"

if grep -Fq "OSAC_ALLOW_WORKSPACE_BOOTSTRAP" "$BOOTSTRAP"; then
  fail "bootstrap.sh must not mention OSAC_ALLOW_WORKSPACE_BOOTSTRAP"
fi
pass "bootstrap.sh does not mention OSAC_ALLOW_WORKSPACE_BOOTSTRAP"
