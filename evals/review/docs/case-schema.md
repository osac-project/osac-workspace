# Case schema

Per-case layout for planning-phase review evals. Aligned with
[agent-eval-harness](https://github.com/opendatahub-io/agent-eval-harness) RFE/review
conventions (`input.yaml`, `reference-review.md`, `annotations.yaml`).

**Judge layout reference:** the `judges:` / `thresholds:` blocks in
`eval-prd-review.yaml` and `eval-design-review.yaml` follow the structure of
the harness's own **rfe-creator** eval configuration (code/LLM quality
judges) — see
[agent-eval-harness](https://github.com/opendatahub-io/agent-eval-harness)
judge examples. `rubric_scoring` and
`critical_findings_recall` are `module`/`function` judges backed by
`evals/review/lib/judges.py` (shared between both eval configs, not
duplicated inline per file); `qualitative_finding_quality` is an LLM
`prompt_file` judge.

`expected_verdict`, `expected_scores`, `critical_findings`, `skip_quality`,
and `reference_review` are enforced by the `judges:` blocks in
`eval-prd-review.yaml` and `eval-design-review.yaml` — not aspirational.
`rubric_version` is not read by any judge (the harness's
`load_case_record()` only exposes `annotations.yaml` to judges), but is
type/presence-checked by the optional `evals/review/lib/validate_cases.py`.
The `input.yaml` fields (`skill`, `case_id`, `jira_key`, `pr_number`) are
documentation-only — neither judges nor `validate_cases.py` check them.

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
| `expected_verdict` | Yes | `PASS` or `FAIL` — matched exactly against the agent output's `### Verdict:` line by the `rubric_scoring` judge |
| `expected_scores` | Yes | Map of criterion name → 0–2 (keys must match skill rubric table headers in `reference-review.md`), matched exactly by the `rubric_scoring` judge. Leave `{}` for wiring fixtures (e.g. `_harness-smoke`) that carry no quality baseline — the judge skips instead of failing when this is empty |
| `rubric_version` | Yes | Pin baseline rubric, e.g. `"2026-07"` |
| `critical_findings` | No | Strings fuzzy-matched (≥60% token overlap) against agent findings by the `critical_findings_recall` judge |
| `skip_quality` | No | When true, skip the optional `qualitative_finding_quality` LLM judge |
| `reference_review` | Effectively yes (for `qualitative_finding_quality`) | Filename of the human-validated review, relative to the case directory — typically `reference-review.md`. The harness's `load_case_record()` only resolves `outputs.annotation_{field}_content` for keys that are *literally present* in `annotations.yaml`; it does not fall back to `reference-review.md` by convention if the key is absent. Every case must set this key explicitly, even when the file is already named `reference-review.md`, or `outputs.annotation_reference_review_content` in the `qualitative_finding_quality` judge's prompt template renders empty and the judge scores against a blank reference with no error |

### Validating a case directory before adding it

`evals/review/lib/validate_cases.py` checks a case directory's structure and
annotation schema (file presence, `document_path` resolution,
`expected_verdict`/`rubric_version`/`expected_scores`/`critical_findings`/
`skip_quality`/`reference_review` types) without running any judge or making
an LLM call. It is not wired into `run-eval.sh` or CI — run it manually
against a new case before committing:

```bash
python3 -c "
from pathlib import Path
from evals.review.lib.validate_cases import validate_case
ok, errors = validate_case(Path('evals/review/cases/prd/<case-id>'), Path('.'))
print('OK' if ok else '\n'.join(errors))
"
```

### Known limitations

`critical_findings_recall`'s bag-of-words token overlap has no notion of
polarity: a review that asserts the *opposite* of a critical finding (e.g.
"tenant isolation is thoroughly addressed" vs. a finding of "missing
tenant isolation") can still score above the 60% threshold purely on
shared topic words. AC-2 requires this judge stay a deterministic
`check`/code judge (no LLM), which rules out a semantic-matching fix here;
a schema change requiring canonical finding IDs from the review skill's
own output would be a heavier, cross-component fix belonging to a
different story. The `qualitative_finding_quality` LLM judge is the
intended backstop for this specific failure mode — it compares
substantive content against `reference-review.md` and would score a
review that gets the substance backwards — but only runs when
`skip_quality` isn't set. A cheaper deterministic partial mitigation (a
small negation-cue word list, e.g. "missing"/"lacks"/"no"/"not" — flag as
suspicious when the finding contains one and the review contains none)
was evaluated but deferred: it only covers explicit negation phrasing, not
polarity flips phrased other ways, and needs real observed cases to
justify the added complexity. Revisit once `OSAC-2265`'s curated golden
cases and `OSAC-2267`'s baseline report show whether this is an actual
observed failure mode.

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
reference_review: reference-review.md
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
reference_review: reference-review.md
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
  - path: artifacts
judges:
  - name: rubric_scoring        # exact verdict + per-criterion score match
  - name: critical_findings_recall   # fuzzy match, gated on critical_findings
  - name: qualitative_finding_quality   # optional LLM judge, gated on skip_quality
thresholds:
  rubric_scoring: { min_pass_rate: 1.0 }
  critical_findings_recall: { min_pass_rate: 1.0 }
  qualitative_finding_quality: { min_mean: 3.5 }
```

`run-eval.sh` passes `--symlinks` to `workspace.py` (see `evals/README.md`).
`hooks.before_all` runs during `execute.py` inside each case workspace.
`outputs.path` is the `artifacts` directory, not the review file itself —
the harness only populates `outputs["files"]` from a directory-typed
`outputs.path`. See each eval YAML's `judges:` block for the `module`/
`function` references (backed by `evals/review/lib/judges.py`) and the
LLM judge's `prompt_file`.

## Smoke fixture (`_harness-smoke`)

Minimal cases under `cases/prd/_harness-smoke/` and `cases/design/_harness-smoke/`
validate harness wiring via:

```bash
evals/review/run-eval.sh --type prd --case _harness-smoke --skip-execute --skip-score
```

Do not treat `_harness-smoke` scores as quality baselines.
