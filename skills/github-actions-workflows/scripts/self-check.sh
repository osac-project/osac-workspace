#!/usr/bin/env bash
# Sanity-checks this skill's own content: lints the embedded workflow_run
# gate template, syntax-checks the shared script, and exercises the semver
# regex against known good/bad tags. Run this after editing SKILL.md or
# reference.md - it's what "Verification before committing" in SKILL.md
# actually looks like when run against the skill's own examples.
#
# Usage: skills/github-actions-workflows/scripts/self-check.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
FAILED=0

pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1"; FAILED=1; }

echo "== bash -n on shared scripts =="
for script in "$SCRIPT_DIR"/*.sh; do
  # Capture stderr into a variable rather than a fixed /tmp path - avoids
  # leaving a predictable, world-writable-tmp-dir-adjacent file around.
  if bash_n_err="$(bash -n "$script" 2>&1)"; then
    pass "$(basename "$script")"
  else
    fail "$(basename "$script"): $bash_n_err"
  fi
done

echo
echo "== actionlint on embedded workflow_run gate template (SKILL.md) =="
if command -v actionlint &>/dev/null; then
  tmp_yaml="$(mktemp /tmp/gha-skill-template.XXXXXX.yaml)"
  awk '/^```yaml$/{flag=1; next} /^```$/{if(flag){flag=0; exit}} flag' \
    "$SKILL_DIR/SKILL.md" > "$tmp_yaml"
  if [ ! -s "$tmp_yaml" ]; then
    fail "no \`\`\`yaml block found in SKILL.md - extraction awk pattern may be stale"
  elif actionlint "$tmp_yaml"; then
    pass "embedded template (0 errors)"
  else
    fail "embedded template - see actionlint output above"
  fi
  rm -f "$tmp_yaml"
else
  echo "  skip: actionlint not installed (https://github.com/rhysd/actionlint)"
fi

echo
echo "== semver regexes against known good/bad tags =="
# Two distinct regexes are documented, on purpose - keep both tables in
# sync with their source:
#   general:       reference.md#semver-regex (allows +build metadata)
#   image-tag-safe: SKILL.md's guard job / verification example (rejects
#                   +build, since Docker/OCI tags can't contain '+')
general_re='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(\.((0|[1-9][0-9]*)|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
image_tag_safe_re='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(\.((0|[1-9][0-9]*)|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?$'

check_regex_table() {
  local label="$1" re="$2"; shift 2
  local tag expected actual
  while [ "$#" -ge 2 ]; do
    tag="$1"; expected="$2"; shift 2
    if [[ "$tag" =~ $re ]]; then actual=MATCH; else actual=REJECT; fi
    if [ "$actual" = "$expected" ]; then
      pass "[$label] $tag -> $actual"
    else
      fail "[$label] $tag -> $actual (expected $expected)"
    fi
  done
}

check_regex_table general "$general_re" \
  "v1.2.3" MATCH \
  "v0.0.1-test-osac2185" MATCH \
  "v5.0.0-rc-1" MATCH \
  "v1.2.3-alpha.1" MATCH \
  "v1.2.3+build.1" MATCH \
  "v01.2.3" REJECT \
  "v1.2.3-01" REJECT \
  "vfoo" REJECT \
  "v1.2.3+" REJECT

check_regex_table image-tag-safe "$image_tag_safe_re" \
  "v1.2.3" MATCH \
  "v0.0.1-test-osac2185" MATCH \
  "v5.0.0-rc-1" MATCH \
  "v1.2.3-alpha.1" MATCH \
  "v1.2.3+build.1" REJECT \
  "v01.2.3" REJECT \
  "v1.2.3-01" REJECT \
  "vfoo" REJECT

echo
echo "== verify-tag-matches-sha.sh, functionally, against a real repo/tag =="
if [ -n "${SELF_CHECK_SKIP_LIVE:-}" ]; then
  echo "  skip: SELF_CHECK_SKIP_LIVE set"
elif command -v gh &>/dev/null && gh auth status &>/dev/null; then
  # Overridable via env vars rather than hardcoded, so this doesn't
  # permanently couple the skill's own self-check to one specific
  # external repo/tag continuing to exist - set SELF_CHECK_REPO/
  # SELF_CHECK_TAG to point at something else, or SELF_CHECK_SKIP_LIVE=1
  # to skip this network-dependent block entirely (e.g. in an offline or
  # sandboxed environment).
  REPO="${SELF_CHECK_REPO:-osac-project/osac-operator}"
  TAG="${SELF_CHECK_TAG:-v0.0.1}"
  # Resolve the expected commit SHA the same way verify-tag-matches-sha.sh
  # does (peel annotated tags) rather than reading .object.sha directly -
  # for a lightweight tag that's already the commit SHA, but for an
  # annotated tag it would be the *tag object's* SHA instead, silently
  # testing against the wrong value. Deliberately not calling out to the
  # script under test for this setup step, to keep the test independent.
  ref_json="$(gh api "repos/${REPO}/git/ref/tags/${TAG}" --jq '[.object.type, .object.sha] | @tsv' 2>/dev/null || true)"
  GUARDED_SHA=""
  if [ -n "$ref_json" ]; then
    read -r ref_type ref_sha <<< "$ref_json"
    if [ "$ref_type" = "tag" ]; then
      GUARDED_SHA="$(gh api "repos/${REPO}/git/tags/${ref_sha}" --jq .object.sha 2>/dev/null || true)"
    else
      GUARDED_SHA="$ref_sha"
    fi
  fi
  if [ -n "$GUARDED_SHA" ]; then
    # Capture combined output (not &>/dev/null) so a failure message can
    # show *why* - a real regression vs. a transient gh api hiccup look
    # identical from the exit code alone.
    if pos_out="$(GH_TOKEN="$(gh auth token)" REPO="$REPO" TAG="$TAG" GUARDED_SHA="$GUARDED_SHA" \
        "$SCRIPT_DIR/verify-tag-matches-sha.sh" 2>&1)"; then
      pass "positive case ($REPO@$TAG, correct SHA) exits 0"
    else
      fail "positive case ($REPO@$TAG, correct SHA) should have exited 0: $pos_out"
    fi
    if neg_out="$(GH_TOKEN="$(gh auth token)" REPO="$REPO" TAG="$TAG" GUARDED_SHA="0000000000000000000000000000000000dead" \
        "$SCRIPT_DIR/verify-tag-matches-sha.sh" 2>&1)"; then
      fail "negative case (deliberately wrong SHA) should have exited non-zero: $neg_out"
    else
      pass "negative case (deliberately wrong SHA) exits non-zero"
    fi
  else
    echo "  skip: couldn't resolve $REPO@$TAG via gh api (network/auth?)"
  fi
else
  echo "  skip: gh CLI not installed or not authenticated"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "All checks passed."
else
  echo "One or more checks FAILED - see above."
  exit 1
fi
