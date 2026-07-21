# Planning-phase review evals

Measures PRD and design review skill quality via [agent-eval-harness](https://github.com/opendatahub-io/agent-eval-harness) from workspace root.

## Layout

| File / directory | Role |
|------------------|------|
| `harness.lock` | Pinned agent-eval-harness version |
| `setup-harness.sh` | Clone harness into `.harness/` (gitignored) |
| `eval-prd-review.yaml` | PRD review harness config |
| `eval-design-review.yaml` | Design review harness config |
| `run-eval.sh` | Runner (`--type`, `--case`, `--skip-execute`, `--skip-score`, `RUN_ID`) |
| `cases/prd/` | PRD review test cases |
| `cases/design/` | Design review test cases |
| `docs/` | Taxonomy and case schema |
| `results/` | Harness run output (gitignored) |

Prerequisites, bootstrap model, and workspace-native location decision:
[`../README.md`](../README.md).

## Quick start

```bash
# From workspace root after ./bootstrap.sh
evals/review/setup-harness.sh
evals/review/run-eval.sh --type prd --case _harness-smoke --skip-execute --skip-score
```
