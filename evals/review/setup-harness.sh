#!/usr/bin/env bash
# Bootstrap a pinned agent-eval-harness checkout for review evals.
#
# Usage:
#   evals/review/setup-harness.sh [--force]
#
# Reads evals/review/harness.lock, clones to evals/review/.harness/agent-eval-harness,
# checks out the pinned ref, creates .eval-venv, and pip install -e .
set -euo pipefail

REVIEW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="${REVIEW_DIR}/harness.lock"
HARNESS_DIR="${REVIEW_DIR}/.harness/agent-eval-harness"
FORCE=0

usage() {
  sed -n '2,8p' "$0"
  exit "${1:-0}"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      die "unknown option: $1 (try --help)"
      ;;
  esac
done

[[ -f "$LOCK_FILE" ]] || die "harness.lock not found: ${LOCK_FILE}"

read_lock() {
  local key="$1"
  local line
  line="$(grep -E "^${key}:" "$LOCK_FILE" | head -1)" || true
  [[ -n "$line" ]] || die "harness.lock missing key: ${key}"
  printf '%s' "${line#*:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//;s/^'\''//;s/'\''$//'
}

REPO="$(read_lock repo)"
REF="$(read_lock ref)"
SHA="$(read_lock sha)"

[[ -n "$REPO" && -n "$REF" ]] || die "harness.lock must set repo and ref"

mkdir -p "${REVIEW_DIR}/.harness"

if [[ -d "$HARNESS_DIR/.git" ]]; then
  echo "Updating harness at ${HARNESS_DIR}..." >&2
  git -C "$HARNESS_DIR" fetch --tags origin
else
  echo "Cloning ${REPO} into ${HARNESS_DIR}..." >&2
  git clone --depth 1 --branch "$REF" "$REPO" "$HARNESS_DIR" 2>/dev/null || {
    rm -rf "$HARNESS_DIR"
    git clone "$REPO" "$HARNESS_DIR"
    git -C "$HARNESS_DIR" fetch --tags origin
  }
fi

if [[ "$FORCE" -eq 1 ]]; then
  git -C "$HARNESS_DIR" fetch --tags origin
fi

git -C "$HARNESS_DIR" checkout -q "$REF" 2>/dev/null || git -C "$HARNESS_DIR" checkout -q "tags/${REF}"

if [[ -n "$SHA" ]]; then
  actual_sha="$(git -C "$HARNESS_DIR" rev-parse HEAD)"
  if [[ "$actual_sha" != "$SHA" ]]; then
    echo "Checking out pinned sha ${SHA}..." >&2
    git -C "$HARNESS_DIR" fetch --depth 1 origin "$SHA" 2>/dev/null || git -C "$HARNESS_DIR" fetch origin
    git -C "$HARNESS_DIR" checkout -q "$SHA"
    actual_sha="$(git -C "$HARNESS_DIR" rev-parse HEAD)"
    [[ "$actual_sha" == "$SHA" ]] || die \
      "harness HEAD ${actual_sha} does not match harness.lock sha ${SHA}"
  fi
fi

VENV_DIR="${HARNESS_DIR}/.eval-venv"
if [[ ! -x "${VENV_DIR}/bin/python3" ]]; then
  echo "Creating harness venv at ${VENV_DIR}..." >&2
  python3 -m venv "$VENV_DIR"
fi

echo "Installing agent-eval-harness (editable)..." >&2
"${VENV_DIR}/bin/pip" install -q --upgrade pip
"${VENV_DIR}/bin/pip" install -q -e "$HARNESS_DIR"

if [[ -f "${HARNESS_DIR}/scripts/ensure_deps.py" ]]; then
  PLUGIN_DATA="${XDG_STATE_HOME:-${HOME}/.local/state}/agent-eval-data"
  echo "Ensuring harness optional deps..." >&2
  (cd "$REVIEW_DIR" && "${VENV_DIR}/bin/python3" "${HARNESS_DIR}/scripts/ensure_deps.py" "$PLUGIN_DATA") || true
fi

echo "" >&2
echo "Harness ready:" >&2
echo "  path: ${HARNESS_DIR}" >&2
echo "  ref:  ${REF} ($(git -C "$HARNESS_DIR" rev-parse --short HEAD))" >&2
echo "" >&2
echo "Dry-run smoke:" >&2
echo "  evals/review/run-eval.sh --type prd --case _harness-smoke --skip-execute --skip-score" >&2
