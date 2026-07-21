# Case schema (draft)

Per-case layout for planning-phase review evals. Aligned with
[agent-eval-harness](https://github.com/opendatahub-io/agent-eval-harness) RFE/review
conventions (`input.yaml`, `reference-review.md`, `annotations.yaml`).

Scoring enforcement fields in `annotations.yaml` are **draft** here; harness judge
blocks in eval YAML finalize alignment.

## Directory layout

```text
evals/review/cases/{prd|design}/{case-id}/
  input.yaml
  reference-review.md
  annotations.yaml
```

- `{case-id}` — stable slug (e.g. `storage-network`)
- `_harness-smoke` — wiring fixture only; not a curated golden baseline

## `input.yaml`

| Field | Required | Description |
|-------|----------|-------------|
| `document_path` | Yes | Path relative to **workspace root**, e.g. `enhancement-proposals/enhancements/<slug>/prd.md` or `README.md` for design (some slugs use `design.md`) |
| `skill` | Yes | `prd-review` or `design-review` |
| `case_id` | Yes | Matches directory name |
| `jira_key` | No | Source Jira feature key for traceability |
| `pr_number` | No | Merged enhancement-proposals PR number |

Example:

```yaml
document_path: enhancement-proposals/enhancements/<slug>/prd.md
skill: prd-review
case_id: <slug>
jira_key: <feature-key>
pr_number: 72
```

Harness resolves `{document_path}` in `execution.arguments` from each case's
`input.yaml`.

## `reference-review.md`

Human-validated golden review output. Markdown body plus optional YAML frontmatter
(score, pass, per-criterion 0–2) per harness RFE/review example.

PRD reviews follow `skills/prd-review/SKILL.md` output format (rubric table,
verdict, findings). Design reviews follow `skills/design-review/SKILL.md`.

## `annotations.yaml`

Expected outcomes for harness judges:

| Field | Required | Description |
|-------|----------|-------------|
| `expected_verdict` | Yes | `PASS` or `FAIL` |
| `expected_scores` | Yes | Map of criterion name → 0–2 (keys must match skill rubric table headers in `reference-review.md`) |
| `rubric_version` | Yes | Pin baseline rubric, e.g. `"2026-07"` |
| `critical_findings` | No | Strings for fuzzy match against agent findings |
| `skip_quality` | No | When true, skip optional LLM quality judge |

Example (PRD — keys from `skills/prd-review/SKILL.md` rubric table):

```yaml
expected_verdict: PASS
rubric_version: "2026-07"
expected_scores:
  "WHAT (clear need)": 2
  "WHY (justification)": 2
  "User-Facing Focus": 2
  "Right-Sized": 1
  "Testability": 2
critical_findings:
  - "Missing tenant isolation in user stories"
```

Example (design — keys from `skills/design-review/SKILL.md` rubric table):

```yaml
expected_verdict: PASS
rubric_version: "2026-07"
expected_scores:
  Architecture: 2
  Feasibility: 2
  Scope: 1
  Testability: 2
critical_findings:
  - "Missing tenant isolation in API section"
```

## Harness config linkage

Each eval YAML (`eval-prd-review.yaml`, `eval-design-review.yaml`) sets:

```yaml
dataset:
  path: cases/prd   # or cases/design
execution:
  mode: case
  skill: prd-review   # or design-review
  arguments: >
    Review the document at {document_path}.
    Write the full structured review to artifacts/review-output.md.
runner:
  type: claude-code   # not workspace_mode: repo (prompt-mode only)
hooks:
  before_all:
    - description: enhancement-proposals available in case workspace
      command: test -d enhancement-proposals
    - description: design context for review skills
      command: test -d .design
outputs:
  - path: artifacts/review-output.md
```

`run-eval.sh` passes `--symlinks` to `workspace.py` (see `evals/README.md`).
`hooks.before_all` runs during `execute.py` inside each case workspace.

Judges and `thresholds` blocks are added when harness scoring is configured.

## Smoke fixture (`_harness-smoke`)

Minimal cases under `cases/prd/_harness-smoke/` and `cases/design/_harness-smoke/`
validate harness wiring via:

```bash
evals/review/run-eval.sh --type prd --case _harness-smoke --skip-execute --skip-score
```

Do not treat `_harness-smoke` scores as quality baselines.
