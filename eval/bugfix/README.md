# Bugfix Eval Harness

Evaluates the bugfix `/unattended` workflow against real OSAC bugs with known fixes. The eval checks out repos at pre-fix SHAs, gives the agent a bug report, and judges whether it produces a correct fix — compared against the real PR that was merged.

## Prerequisites

1. **Claude Code CLI** installed and authenticated
2. **agent-eval-harness** plugin installed in Claude Code
3. **python3** with `pyyaml` module

The repo cache (cloned OSAC component repos for eval) is created automatically on first run at `/tmp/osac-eval-repos/`. To use a different location:

```bash
export REPO_CACHE=/path/to/cache
```

## What this tests

The eval exercises the full AI bugfix pipeline end-to-end:

- **CLAUDE.md** — does the project context help the agent navigate the codebase?
- **Architecture docs** (`.planning/codebase/`) — do they provide enough context for diagnosis?
- **Bugfix skill** (`.claude/skills/bugfix/`) — does the unattended workflow produce the right phases and artifacts?
- **task.md** — does the task orchestration format work? Is it too broad, too narrow?
- **issue.md** — is the bug report format sufficient for diagnosis?
- **Prompt** — does "Read and follow task.md" trigger the right behavior?

## Quick start

```bash
# Run one case
bash eval/bugfix/run-eval.sh --case MGMT-23654-securitygroup-unknown-type

# Run all 11 cases
bash eval/bugfix/run-eval.sh

# Run with a custom run ID
RUN_ID=my-experiment bash eval/bugfix/run-eval.sh

# Just set up workspaces (inspect without running the agent)
bash eval/bugfix/run-eval.sh --case MGMT-23654-securitygroup-unknown-type --skip-execute --skip-score

# Re-score an existing run without re-executing
# (useful after changing judges in eval-bugfix.yaml)
bash eval/bugfix/run-eval.sh --skip-execute --skip-setup
```

You can run from any directory — the script resolves all paths relative to its own location.

## What happens during a run

```
workspace.py          Create isolated workspace per case (harness native)
        │             Copies CLAUDE.md, .claude/, .planning/ from osac-workspace root
        ▼
setup-workspace.sh    Clone repos at pinned SHAs, render task.md from template
        │
        ▼
execute.py            Run the bugfix agent headlessly via Claude Code
        │             Agent reads task.md → issue.md → executes unattended workflow
        ▼
collect.py            Gather .ai-bot/ artifacts, stdout.log, run metrics
        ▼
score.py              Run 5 judges against collected outputs
```

## Directory structure

```
eval/bugfix/
├── eval-bugfix.yaml              # Eval config: skill, judges, thresholds, permissions
├── run-eval.sh                   # Wrapper orchestrating the full pipeline
├── setup-workspace.sh            # Clones repos at pinned SHAs per case
├── task.md.tmpl                  # Task template rendered per case
├── README.md                     # This file
│
├── cases/                        # 11 test cases
│   └── MGMT-XXXXX-slug/
│       ├── input.yaml            # Repo SHAs, jira key, primary repo
│       ├── issue.md              # Bug report (title, description, comments)
│       ├── reference.md          # Real PR diff for judge comparison
│       ├── annotations.yaml      # Expected repos, files, difficulty
│       └── answers.yaml          # AskUserQuestion auto-answer guidance
│
└── runs/                         # Eval results (per run, gitignored)
    └── <run-id>/
        ├── cases/<case-id>/
        │   ├── .ai-bot/          # Workflow artifacts
        │   ├── stdout.log        # Full stream-json trace
        │   └── run_result.json   # Cost, turns, duration
        └── eval-summary.md       # Human-readable summary
```

## How to iterate

Everything the agent sees comes from the osac-workspace tree — edit, re-run, compare scores.

### Changing context (CLAUDE.md, architecture docs)

Edit the files directly in osac-workspace:

| File | Location | Effect |
|------|----------|--------|
| CLAUDE.md | `osac-workspace/CLAUDE.md` | Changes project context the agent reads |
| Architecture docs | `osac-workspace/.planning/codebase/*.md` | Changes architecture knowledge |

### Changing the bugfix skill

```bash
# Edit a phase
vim ~/.ai-workflows/bugfix/skills/unattended.md

# Re-run to test
bash eval/bugfix/run-eval.sh --case MGMT-23654-securitygroup-unknown-type
```

### Changing the task template

```bash
vim eval/bugfix/task.md.tmpl

# Re-run — setup-workspace.sh renders the template per case
bash eval/bugfix/run-eval.sh --case MGMT-23654-securitygroup-unknown-type
```

### Changing judges or thresholds

Edit `eval/bugfix/eval-bugfix.yaml` and re-score without re-executing:

```bash
vim eval/bugfix/eval-bugfix.yaml   # edit judges section

# Re-score existing run
AGENT_EVAL_RUNS_DIR=eval/bugfix/runs \
python3 $HARNESS_DIR/score.py judges --run-id <run-id> --config eval/bugfix/eval-bugfix.yaml
```

### Adding a new test case

1. Create `eval/bugfix/cases/MGMT-XXXXX-slug/`
2. Add `input.yaml` with `jira_key`, `repos` (all 7 with pinned SHAs), `primary_repo`
3. Add `issue.md` with the bug report
4. Add `reference.md` with the real PR diff (`gh pr diff <num> --repo osac-project/<repo>`)
5. Add `annotations.yaml` with `expected_repos`, `expected_files`, `difficulty`
6. Add `answers.yaml` with AskUserQuestion guidance
7. Get the pre-fix SHA: first parent of the merge commit (`gh api repos/osac-project/<repo>/commits/<merge-sha> --jq '.parents[0].sha'`)
8. Get context SHAs for other repos: `git rev-list -1 --before="<bug-date>" origin/main`

## Judges

| Judge | Type | What it checks |
|-------|------|---------------|
| `correct_repo` | Inline (stream-json) | Did the agent Edit/Write in the expected repo(s)? |
| `correct_files` | Inline (stream-json) | Did the agent modify the expected source files? |
| `tests_added` | Inline (stream-json) | Did the agent create/modify test files? |
| `artifacts_produced` | Inline (files) | Did the workflow write root-cause.md, implementation-notes.md, verification.md? |
| `fix_correctness` | LLM (Opus) | Compare agent's fix against the real PR — root cause, correctness, completeness, test quality (1-5 scale) |

Inline judges parse Edit/Write tool calls from the stream-json stdout — they don't need filesystem access to the workspace.

## Metrics tracked

Per run:
- **fix_correctness mean** — average quality across cases (target: >= 3.0)
- **pass rates** — per judge (correct_repo, correct_files, tests_added, artifacts_produced)
- **cost_per_turn_usd** — efficiency metric
- **cache_hit_rate** — context reuse efficiency

Per case:
- **cost_usd** — total API cost
- **num_turns** — conversation turns
- **duration_s** — wall clock time
- **artifacts count** — how many of 6 expected artifacts were produced

All data stored in `eval/bugfix/runs/<run-id>/` and optionally logged to MLflow (`mlflow ui` to browse).

## Improvement workflow

```
1. Run eval
   ↓
2. Review scores — which judges failed? Which cases?
   ↓
3. Read the trace — what did the agent actually do?
   (eval/bugfix/runs/<run-id>/cases/<case>/stdout.log)
   ↓
4. Identify root cause:
   - Skill issue → edit ~/.ai-workflows/bugfix/skills/*.md
   - Context issue → edit CLAUDE.md or .planning/codebase/*.md
   - Prompt issue → edit task.md.tmpl or eval-bugfix.yaml arguments
   - Harness issue → edit eval-bugfix.yaml (hooks, permissions, handlers)
   - Judge issue → edit eval-bugfix.yaml judges section
   ↓
5. Re-run the failing case
   ↓
6. Compare scores — did it improve?
   ↓
7. Run full suite to check for regressions
```

## Current test cases

| Case | Bug Category | Difficulty | Repo(s) | Multi-repo |
|------|-------------|------------|---------|------------|
| MGMT-23473 | missing-validation | medium | fulfillment-service | no |
| MGMT-23568 | logic-error | hard | fulfillment-service | no |
| MGMT-23638 | missing-default | easy | fulfillment-service | no |
| MGMT-23654 | missing-registration | easy | fulfillment-service | no |
| MGMT-23662 | missing-persist | medium | osac-operator | no |
| MGMT-23770 | ansible-conditional-error | easy | osac-aap | no |
| MGMT-23970 | missing-fallback | easy | fulfillment-service | no |
| MGMT-23998 | missing-rbac | hard | fulfillment-service + osac-installer | yes |
| MGMT-24061 | config-change | easy | osac-aap | no |
| MGMT-24142 | missing-file | easy | fulfillment-service | no |
| MGMT-24226 | version-mismatch | hard | osac-installer + fulfillment-service + osac-aap | yes |

## Cost

- **Single easy case**: ~$1-2, ~3-5 minutes
- **Single hard case**: ~$3-4, ~8-15 minutes
- **Full 11-case run**: ~$21, ~2 hours (sequential)
- **Model**: Opus 4.6 (skill), Sonnet 4.6 (subagents, hooks)
