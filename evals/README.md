# OSAC workspace evals

Workspace-native evaluation tooling for measuring agentic SDLC quality. Lives in
`osac-workspace` alongside `skills/` and `.design/context/` — not a bootstrapped
component repo and not a separate clone.

## Location decision

| Approach | This project |
|----------|--------------|
| Separate `osac-review-eval` repo | **No** |
| Bootstrapped component (like `fulfillment-service`) | **No** |
| Workspace-native `evals/` tree | **Yes** |

Bugfix evals remain in external [`eranco74/osac-bugfix-eval`](https://github.com/eranco74/osac-bugfix-eval).
Clone separately; set `BUGFIX_EVAL_REPO`. Phase 2 links review and bugfix results
via `evals/run-all.sh`.

## Prerequisites

Run all eval commands from the **workspace root** (the directory that contains
`enhancement-proposals/` and `skills/`).

1. **Bootstrap the workspace**

   ```bash
   ./bootstrap.sh
   ```

   This clones `enhancement-proposals/` and links agent skills (including
   `prd-review` and `design-review`) under `.claude/skills/`.

2. **Claude Code CLI** — required for headless skill execution.

3. **agent-eval-harness** — pinned checkout bootstrapped locally:

   ```bash
   evals/review/setup-harness.sh
   ```

   This reads `evals/review/harness.lock`, clones to
   `evals/review/.harness/agent-eval-harness`, checks out the pinned ref, and
   creates `.eval-venv` with an editable install.

   Pin **≥ v1.13.0** (lifecycle `hooks` in eval YAML). This repo locks **v1.22.0**
   in `harness.lock` (recommended).

   Harness is **not** installed by `./bootstrap.sh` — run `setup-harness.sh` when
   you need review evals.

   `run-eval.sh` uses that checkout by default. Override with
   `AGENT_EVAL_HARNESS=/other/path` for harness development.

   Optional Claude Code plugin (for `/eval-run` skill workflows):

   ```bash
   claude plugin install agent-eval-harness@opendatahub-skills
   ```

   To bump the harness version: edit `harness.lock`, run `setup-harness.sh`,
   re-run the dry-run smoke below, then commit the lock file.

   **Execution path:** `run-eval.sh` calls the harness **script chain**
   (`preflight.py` → `workspace.py` → `execute.py` → `collect.py` → `score.py`).
   Do not depend on the upstream `agent-eval run` CLI until
   [PR #109](https://github.com/opendatahub-io/agent-eval-harness/pull/109) merges.

## Per-case workspaces and `workspace.py --symlinks`

Review evals use harness **case mode**: each case gets an isolated workspace.
Case `input.yaml` paths such as `enhancement-proposals/enhancements/.../prd.md` are
relative to the **osac-workspace root**, but the skill runs inside the per-case
workspace. `run-eval.sh` passes `--symlinks` to `workspace.py` so those paths resolve.

Minimum symlinks required (always include these):

- `enhancement-proposals` — document targets under `enhancement-proposals/`
- `.design` — review skills load `.design/context/`

`run-eval.sh` also symlinks `skills`, `.claude`, and `CLAUDE.md` so headless
`prd-review` / `design-review` skills match `./bootstrap.sh` layout.

Skill-based review evals use `runner.type: claude-code` with per-case workspaces.
Do **not** use `runner.workspace_mode: repo` (in-repo execution is for prompt-mode
evals only in harness v1.22.0).

Prerequisite checks run in two places:

1. **`run-eval.sh`** (before harness) — workspace root, skills, harness checkout
2. **`hooks.before_all` in eval YAML** — re-validates inside each case workspace
   during `execute.py` (skipped when using `--skip-execute`)

## Gitignored paths and baseline

`evals/review/.gitignore` excludes:

- `.harness/` — pinned harness clone
- `results/` — harness run output
- `artifacts/` — per-case skill output during runs

Committed baseline summaries (golden-set scores, rubric pins) belong in
**OSAC-2267**, not this scaffold story.

## Models

Planning review evals pin Claude models in each eval YAML (`models.skill`, `models.judge`).
Bugfix eval model policy remains in external `osac-bugfix-eval`.

| Role | Pinned model | Notes |
|------|--------------|-------|
| Skill (`prd-review`, `design-review`) | `claude-sonnet-4-6` | Read-only doc review + structured output |
| Judge (LLM judges) | `claude-sonnet-4-6` | Same default; inline `check` judges are model-agnostic |

**Rationale:** cost-effective golden-set regression on reference cases; distinct from
harness template Opus defaults for general skill evals.

Eval YAML pins `claude-sonnet-4-6` for both roles. The baseline report records
pinned models alongside `rubric_version`.

**Bump policy:** intentional model changes require YAML update and a new baseline run.
Ad-hoc override: harness `/eval-run --model` or edit eval YAML locally (not committed).

## What we do not do

Review evals intentionally avoid patterns from `osac-bugfix-eval` that duplicate
workspace setup:

- No `deps/osac-workspace` clone
- No `workspace-template/` or per-case symlink farms
- No `setup.sh` that re-clones `enhancement-proposals` (already provided by `./bootstrap.sh`)

The harness runs with workspace root as CWD and symlinks `skills/`, `.claude/`,
`.design/`, and `enhancement-proposals/` into each case workspace.

## Review evals (`evals/review/`)

Planning-phase evals measure `prd-review` and `design-review` skill quality against
human-validated reference cases.

| Path | Purpose |
|------|---------|
| `evals/review/harness.lock` | Pinned agent-eval-harness ref and SHA |
| `evals/review/setup-harness.sh` | Bootstrap harness into `.harness/` |
| `evals/review/eval-prd-review.yaml` | Harness config for PRD review |
| `evals/review/eval-design-review.yaml` | Harness config for design review |
| `evals/review/run-eval.sh` | CLI runner wired to agent-eval-harness |
| `evals/review/cases/` | Test cases (`prd/`, `design/`) |
| `evals/review/docs/` | Measurement taxonomy and case schema |
| `evals/review/results/` | Run output (gitignored) |

See [`evals/review/README.md`](review/README.md) and
[`evals/review/docs/`](review/docs/) for case layout and metrics.

## Dry-run smoke (no LLM)

Validates harness wiring, eval YAML, and workspace layout without skill execution
or scoring:

```bash
evals/review/setup-harness.sh
evals/review/run-eval.sh --type prd --case _harness-smoke --skip-execute --skip-score
```

Full LLM eval runs, harness judges, and baseline reporting are follow-on work
(OSAC-2264 judges, golden cases, **OSAC-2267** baseline).

## Documentation

- [`evals/review/docs/measurement-taxonomy.md`](review/docs/measurement-taxonomy.md) — cross-phase metrics and data sources
- [`evals/review/docs/case-schema.md`](review/docs/case-schema.md) — per-case file layout
- [`evals/lib/unified-report.schema.yaml`](lib/unified-report.schema.yaml) — combined review + bugfix report (`feed_type: eval_run`)
- [`evals/lib/bugfix-ingest.md`](lib/bugfix-ingest.md) — bugfix adapter input contract
