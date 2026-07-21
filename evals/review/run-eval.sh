#!/usr/bin/env bash
# Run planning-phase review evals via agent-eval-harness from workspace root.
#
# Usage:
#   evals/review/run-eval.sh [options]
#
# Options:
#   --type prd|design|all   Eval config(s) to run (default: all)
#   --case <id>             Case subdirectory name (repeatable)
#   --skip-execute          Workspace prep only; skip execute.py
#   --skip-score            Skip score.py
#
# Environment:
#   AGENT_EVAL_HARNESS      Harness checkout (default: evals/review/.harness/agent-eval-harness)
#   RUN_ID                  Run identifier (default: UTC timestamp)
#
# First-time setup: evals/review/setup-harness.sh
set -euo pipefail

REVIEW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVALS_DIR="$(cd "${REVIEW_DIR}/.." && pwd)"
WORKSPACE_ROOT="$(cd "${EVALS_DIR}/.." && pwd)"

EVAL_TYPE="all"
SKIP_EXECUTE=0
SKIP_SCORE=0
CASE_IDS=()
RUN_ID="${RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"

usage() {
  sed -n '2,14p' "$0"
  exit "${1:-0}"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      [[ $# -ge 2 ]] || die "--type requires prd, design, or all"
      EVAL_TYPE="$2"
      shift 2
      ;;
    --case)
      [[ $# -ge 2 ]] || die "--case requires a case id"
      CASE_IDS+=("$2")
      shift 2
      ;;
    --skip-execute)
      SKIP_EXECUTE=1
      shift
      ;;
    --skip-score)
      SKIP_SCORE=1
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

case "$EVAL_TYPE" in
  prd|design|all) ;;
  *) die "--type must be prd, design, or all" ;;
esac

# --- Prerequisites -----------------------------------------------------------

[[ -d "${WORKSPACE_ROOT}/enhancement-proposals" ]] || die \
  "run from bootstrapped workspace root (missing enhancement-proposals/). Run ./bootstrap.sh first."

require_skill() {
  local skill="$1"
  if [[ -d "${WORKSPACE_ROOT}/.claude/skills/${skill}" ]]; then
    return 0
  fi
  if [[ -d "${WORKSPACE_ROOT}/skills/${skill}" ]]; then
    echo "WARNING: .claude/skills not linked; using skills/ directly. Run tools/link-agent-skills.sh or ./bootstrap.sh" >&2
    return 0
  fi
  die "${skill} skill not found under .claude/skills/ or skills/"
}

SKILLS_NEEDED=()
if [[ "$EVAL_TYPE" == "prd" || "$EVAL_TYPE" == "all" ]]; then
  SKILLS_NEEDED+=(prd-review)
fi
if [[ "$EVAL_TYPE" == "design" || "$EVAL_TYPE" == "all" ]]; then
  SKILLS_NEEDED+=(design-review)
fi
for skill in "${SKILLS_NEEDED[@]}"; do
  require_skill "$skill"
done

HARNESS_DEFAULT="${REVIEW_DIR}/.harness/agent-eval-harness"
export AGENT_EVAL_HARNESS="${AGENT_EVAL_HARNESS:-$HARNESS_DEFAULT}"

[[ -d "${AGENT_EVAL_HARNESS}" ]] || die \
  "harness not found at ${AGENT_EVAL_HARNESS}. Run evals/review/setup-harness.sh first."

HARNESS_ROOT="$(cd "${AGENT_EVAL_HARNESS}" && pwd)"

verify_harness_lock() {
  local lock_file="${REVIEW_DIR}/harness.lock"
  [[ -f "$lock_file" ]] || return 0
  local expected_sha
  expected_sha="$(grep -E '^sha:' "$lock_file" | head -1 | sed 's/^sha:[[:space:]]*//')"
  [[ -n "$expected_sha" ]] || return 0
  local actual_sha
  actual_sha="$(git -C "$HARNESS_ROOT" rev-parse HEAD 2>/dev/null)" || return 0
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "WARNING: harness checkout ${actual_sha:0:12} differs from harness.lock sha ${expected_sha:0:12}. Run evals/review/setup-harness.sh" >&2
  fi
}
verify_harness_lock
HARNESS_SCRIPTS="${HARNESS_ROOT}/skills/eval-run/scripts"
[[ -f "${HARNESS_SCRIPTS}/workspace.py" ]] || die \
  "harness scripts not found at ${HARNESS_SCRIPTS}/workspace.py (check AGENT_EVAL_HARNESS)"

# Prefer harness venv interpreter when present (matches plugin bootstrap)
if [[ -z "${PYTHON:-}" && -x "${HARNESS_ROOT}/.eval-venv/bin/python3" ]]; then
  PYTHON="${HARNESS_ROOT}/.eval-venv/bin/python3"
fi
PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null 2>&1 || die "python3 not found"

export AGENT_EVAL_RUNS_DIR="${AGENT_EVAL_RUNS_DIR:-${REVIEW_DIR}/results}"
OUTPUT_DIR="${AGENT_EVAL_RUNS_DIR}/${RUN_ID}"
mkdir -p "$OUTPUT_DIR"

# Workspace symlinks: project resources the review skills need
WORKSPACE_SYMLINKS="skills,.claude,.design,enhancement-proposals,CLAUDE.md"

cd "$WORKSPACE_ROOT"

configs=()
if [[ "$EVAL_TYPE" == "prd" || "$EVAL_TYPE" == "all" ]]; then
  configs+=("${REVIEW_DIR}/eval-prd-review.yaml")
fi
if [[ "$EVAL_TYPE" == "design" || "$EVAL_TYPE" == "all" ]]; then
  configs+=("${REVIEW_DIR}/eval-design-review.yaml")
fi

workspace_args=()
if [[ ${#CASE_IDS[@]} -gt 0 ]]; then
  workspace_args+=(--cases "${CASE_IDS[@]}")
fi

extract_workspace_path() {
  local log_file="$1"
  local path
  path="$(grep '^WORKSPACE: ' "$log_file" | tail -1 | sed 's/^WORKSPACE: //')"
  [[ -n "$path" ]] || die "workspace.py did not print WORKSPACE: (see ${log_file})"
  printf '%s' "$path"
}

run_eval_config() {
  local config="$1"
  local config_name
  config_name="$(basename "$config" .yaml)"
  local log_prefix="${OUTPUT_DIR}/${config_name}"
  local workspace_log="${log_prefix}.workspace.log"

  echo "=== ${config_name} (run-id: ${RUN_ID}) ===" >&2

  if [[ $SKIP_EXECUTE -eq 0 ]]; then
    if [[ -f "${HARNESS_SCRIPTS}/preflight.py" ]]; then
      "$PYTHON" "${HARNESS_SCRIPTS}/preflight.py" \
        --config "$config" \
        --run-id "$RUN_ID" \
        || die "preflight failed for ${config_name}"
    fi
  fi

  "$PYTHON" "${HARNESS_SCRIPTS}/workspace.py" \
    --config "$config" \
    --run-id "$RUN_ID" \
    --symlinks "$WORKSPACE_SYMLINKS" \
    ${workspace_args[@]+"${workspace_args[@]}"} \
    2>&1 | tee "$workspace_log"

  local workspace_path
  workspace_path="$(extract_workspace_path "$workspace_log")"
  echo "Workspace: ${workspace_path}" >&2

  if [[ $SKIP_EXECUTE -eq 1 ]]; then
    echo "Skipping execute.py (--skip-execute)" >&2
  else
    local skill model mlflow_exp
    skill="$("$PYTHON" -c "
import yaml, sys
cfg = yaml.safe_load(open(sys.argv[1]))
print(cfg.get('execution', {}).get('skill') or cfg.get('skill', ''))
" "$config")"
    model="$("$PYTHON" -c "
import yaml, sys
cfg = yaml.safe_load(open(sys.argv[1]))
print(cfg.get('models', {}).get('skill', ''))
" "$config")"
    mlflow_exp="$("$PYTHON" -c "
import yaml, sys
cfg = yaml.safe_load(open(sys.argv[1]))
print(cfg.get('mlflow', {}).get('experiment', ''))
" "$config")"

    local -a exec_args=(
      "$PYTHON" "${HARNESS_SCRIPTS}/execute.py"
      --config "$config"
      --workspace "$workspace_path"
      --output "$OUTPUT_DIR"
      --run-id "$RUN_ID"
    )
    [[ -n "$skill" ]] && exec_args+=(--skill "$skill")
    [[ -n "$model" ]] && exec_args+=(--model "$model")
    [[ -n "$mlflow_exp" ]] && exec_args+=(--mlflow-experiment "$mlflow_exp")

    "${exec_args[@]}"

    "$PYTHON" "${HARNESS_SCRIPTS}/collect.py" \
      --config "$config" \
      --workspace "$workspace_path" \
      --output "$OUTPUT_DIR"
  fi

  if [[ $SKIP_SCORE -eq 1 ]]; then
    echo "Skipping score.py (--skip-score)" >&2
  elif [[ $SKIP_EXECUTE -eq 0 ]]; then
    local judge_model
    judge_model="$("$PYTHON" -c "
import yaml, sys
cfg = yaml.safe_load(open(sys.argv[1]))
print(cfg.get('models', {}).get('judge') or cfg.get('models', {}).get('skill', ''))
" "$config")"
    "$PYTHON" "${HARNESS_SCRIPTS}/score.py" judges \
      --run-id "$RUN_ID" \
      --config "$config" \
      --workspace "$workspace_path" \
      --model "$judge_model"
  fi

  echo "Results: ${OUTPUT_DIR}" >&2
}

for config in "${configs[@]}"; do
  [[ -f "$config" ]] || die "eval config not found: $config"
  run_eval_config "$config"
done

echo "Done. Run output: ${OUTPUT_DIR}" >&2
