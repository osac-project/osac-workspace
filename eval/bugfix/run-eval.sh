#!/bin/bash
# run-eval.sh — Orchestrate bugfix eval: workspace setup → repo cloning → execution → scoring
#
# Usage: ./run-eval.sh [--case CASE_ID] [--skip-setup] [--skip-execute] [--skip-score]
#
# Wraps the agent-eval-harness pipeline with a repo-cloning step between
# workspace creation and agent execution:
#
#   workspace.py  →  setup-workspace.sh (per case)  →  execute.py  →  collect.py  →  score.py
#
# Runs from osac-workspace root so the harness picks up CLAUDE.md, .claude/,
# .planning/, and skills/ via symlinks into each case workspace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="${AGENT_EVAL_HARNESS:-$(find ~/.claude/plugins/cache -path '*/agent-eval-harness/*/skills/eval-run/scripts' -type d 2>/dev/null | head -1)}"

if [ -z "$HARNESS_DIR" ]; then
    echo "ERROR: Could not find agent-eval-harness scripts directory."
    echo "Set AGENT_EVAL_HARNESS to the path containing workspace.py, execute.py, etc."
    exit 1
fi

EVAL_CONFIG="$SCRIPT_DIR/eval-bugfix.yaml"
SETUP_SCRIPT="$SCRIPT_DIR/setup-workspace.sh"
RUN_ID="${RUN_ID:-$(date +%Y-%m-%d-%H%M)}"
OUTPUT_DIR="$SCRIPT_DIR/runs/$RUN_ID"

# Parse flags
CASE_FILTER=""
SKIP_SETUP=false
SKIP_EXECUTE=false
SKIP_SCORE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --case)       CASE_FILTER="$2"; shift 2 ;;
        --skip-setup) SKIP_SETUP=true; shift ;;
        --skip-execute) SKIP_EXECUTE=true; shift ;;
        --skip-score) SKIP_SCORE=true; shift ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

echo "=== Bugfix Eval Run: $RUN_ID ==="
echo "Config:   $EVAL_CONFIG"
echo "Output:   $OUTPUT_DIR"
echo ""

# --- Step 1: Create workspaces (harness native) ---
# CWD = osac-workspace root so the harness finds CLAUDE.md, .claude/, .planning/

WORKSPACE_ROOT="$SCRIPT_DIR/../.."

echo "--- Step 1: Creating case workspaces ---"
cd "$WORKSPACE_ROOT"

WORKSPACE_ARGS=(
    --config "$EVAL_CONFIG"
    --run-id "$RUN_ID"
    --symlinks "CLAUDE.md,.claude,.planning,skills"
)
if [ -n "$CASE_FILTER" ]; then
    WORKSPACE_ARGS+=(--case-filter "$CASE_FILTER")
fi

# Capture workspace path from workspace.py output
WS_OUTPUT=$(python3 "$HARNESS_DIR/workspace.py" "${WORKSPACE_ARGS[@]}" 2>&1)
echo "$WS_OUTPUT"

WORKSPACE=$(echo "$WS_OUTPUT" | grep "^WORKSPACE:" | awk '{print $2}')
if [ -z "$WORKSPACE" ]; then
    echo "ERROR: Could not determine workspace path from workspace.py output"
    exit 1
fi

echo "Workspace: $WORKSPACE"
echo ""

# --- Step 2: Clone repos into each case workspace ---

if [ "$SKIP_SETUP" = false ]; then
    echo "--- Step 2: Setting up repos in case workspaces ---"

    for case_ws in "$WORKSPACE/cases/"*/; do
        case_id=$(basename "$case_ws")
        input_file="$case_ws/input.yaml"

        if [ ! -f "$input_file" ]; then
            echo "  SKIP $case_id (no input.yaml)"
            continue
        fi

        echo "  Setting up $case_id..."
        bash "$SETUP_SCRIPT" "$input_file" "$case_ws"
        echo ""
    done
else
    echo "--- Step 2: SKIPPED (--skip-setup) ---"
fi

# --- Step 3: Execute agent per case ---

if [ "$SKIP_EXECUTE" = false ]; then
    echo "--- Step 3: Executing bugfix skill per case ---"
    mkdir -p "$OUTPUT_DIR"

    python3 "$HARNESS_DIR/execute.py" \
        --workspace "$WORKSPACE" \
        --skill bugfix \
        --output "$OUTPUT_DIR" \
        --config "$EVAL_CONFIG"

    echo ""
else
    echo "--- Step 3: SKIPPED (--skip-execute) ---"
fi

# --- Step 4: Collect outputs ---

if [ "$SKIP_EXECUTE" = false ]; then
    echo "--- Step 4: Collecting outputs ---"

    python3 "$HARNESS_DIR/collect.py" \
        --workspace "$WORKSPACE" \
        --output "$OUTPUT_DIR" \
        --config "$EVAL_CONFIG"

    echo ""
fi

# --- Step 5: Score ---

if [ "$SKIP_SCORE" = false ] && [ "$SKIP_EXECUTE" = false ]; then
    echo "--- Step 5: Scoring ---"

    AGENT_EVAL_RUNS_DIR="$SCRIPT_DIR/runs" \
    python3 "$HARNESS_DIR/score.py" judges \
        --run-id "$RUN_ID" \
        --config "$EVAL_CONFIG"

    echo ""
fi

echo "=== Done ==="
echo "Results: $OUTPUT_DIR"
echo "Workspace: $WORKSPACE"
