# Bugfix eval ingest contract

Adapter input for cross-workflow reporting. Source: `agent-eval-harness` `score.py` /
`execute.py` (pinned via `evals/review/harness.lock`) cross-checked against
`eranco74/osac-bugfix-eval` README — **2026-07-14**.

> **Revisit before adapter implementation:** Run one scored easy case (e.g.
> `MGMT-23638-missing-default`) and confirm `summary.yaml` `per_case` shape
> matches this doc. Update if harness version drifted.

## Repo layout

Clone to `BUGFIX_EVAL_REPO` (default: sibling `osac-bugfix-eval/`):

```bash
git clone https://github.com/eranco74/osac-bugfix-eval.git "${BUGFIX_EVAL_REPO:-../osac-bugfix-eval}"
```

Output after `./run-eval.sh --case <id>`:

```
${BUGFIX_EVAL_REPO}/runs/<run-id>/
├── summary.yaml          # PRIMARY adapter input (machine-readable)
├── run_result.json       # Run-level execution metadata + per_case map
├── collection.json       # Artifact collection counts
└── cases/<case-id>/
    ├── run_result.json   # Per-case execution metadata (optional detail)
    ├── stdout.log
    └── .ai-bot/          # Workflow phase artifacts
```

**Note:** `osac-bugfix-eval` README references `eval-summary.md` — that file is
**not** produced by current harness; use **`summary.yaml`**.

## `summary.yaml` (from `score.py judges`)

Written by `AGENT_EVAL_RUNS_DIR=runs python3 score.py judges --run-id <id>`.

| Key | Content | Adapter use |
|-----|---------|-------------|
| `run_id` | string | Unified report `run_id` |
| `judges` | map judge → `{pass_rate, mean, …}` | `workflow_aggregate.pass_rates`, `fix_correctness_mean` |
| `per_case` | map case_id → judge results | `cases[]` in unified schema |
| `run_metrics` | `cost_per_turn_usd`, `cache_hit_rate`, … | Optional provenance |

## `run_result.json` (run level)

| Field | Type | Notes |
|-------|------|-------|
| `cost_usd` | number | Total run cost |
| `num_turns` | integer | Total turns |
| `duration_s` | number | Wall-clock aggregate |
| `per_case` | object | Per-case `exit_code`, `cost_usd`, `num_turns`, `duration_s`, `token_usage` |
| `num_cases` | integer | Case count |
| `model`, `agent` | string | Provenance |

## Pass semantics (adapter default)

A case **passes** when all inline judges pass (`correct_repo`, `correct_files`,
`tests_added`, `artifacts_produced`) **and** `fix_correctness` ≥ 3 (harness
README target). Confirm threshold with bugfix eval owners if adapter disagrees with
`summary.yaml` aggregates.

## Adapter output

Maps into `evals/lib/unified-report.schema.yaml` with `workflow: bugfix`,
`gate: execution.bugfix`.

## Adapter kickoff checklist

- [ ] Clone `eranco74/osac-bugfix-eval`; run one easy case with scoring
- [ ] Diff `runs/<run-id>/summary.yaml` against this doc
- [ ] Commit fixture `evals/lib/fixtures/bugfix-summary.sample.yaml` from real run
- [ ] Implement adapter + unit test against fixture
