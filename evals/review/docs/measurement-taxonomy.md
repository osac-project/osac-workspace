# Measurement taxonomy (draft)

Cross-phase metrics for the OSAC agentic SDLC evaluation program.
Operational metric collection detail for the operations phase is marked **TBD**
pending fetcher design.

## Scoring rules (planning phase)

Aligned with review skills in `skills/prd-review/` and `skills/design-review/`:

| Review type | Rubric | PASS threshold | Auto-fail |
|-------------|--------|----------------|-----------|
| PRD | 0–2 per criterion, /10 total | Total ≥ 7 | Any criterion scored 0 |
| Design | 0–2 per criterion, /8 total | Total ≥ 5 | Any criterion scored 0 |

Harness judges enforce verdict match, zero-dimension auto-fail, and critical
finding recall against `annotations.yaml` baselines.

## Metrics by phase

| Phase | Metric | What it measures | Data source | Status |
|-------|--------|------------------|-------------|--------|
| **1 — Planning** | Review verdict accuracy | Agent PASS/FAIL matches human baseline | `evals/review/results/` harness scores | Active |
| **1 — Planning** | Rubric dimension scores | Per-criterion 0–2 vs `annotations.yaml` | Harness `check` judges | Active |
| **1 — Planning** | Critical finding recall | Key findings present in agent output | Harness fuzzy match | Active |
| **1 — Planning** | Qualitative finding quality | Nuance vs `reference-review.md` | Optional LLM `prompt` judge | Planned |
| **2 — Execution** | Fix correctness | Bugfix skill resolves seeded issues | `osac-bugfix-eval` (external) | Phase 2 |
| **2 — Execution** | Regression pass rate | Eval suite gate on skill changes | Unified `evals/run-all.sh` | Phase 2 |
| **3 — Operations** | MTTR | Agent and resolution time on labeled bugs | `org-pulse-data` (extend) | Phase 3 — formulas in § Operations metrics |
| **3 — Operations** | PR velocity | Throughput and cycle time | GitHub API / `org-pulse-data` | Phase 3 |
| **3 — Operations** | FTPR (reference) | % merged PRs passing CI on first commit | **UOI** (Konflux DevLake + n8n) — not `org-pulse-data` | External baseline |
| **3 — Operations** | RCA accuracy | Root-cause quality on closed bugs | **Indirect** — review finding recall + bugfix `fix_correctness`; no standalone rubric | Active (planning + execution proxies) |
| **4 — Reporting** | Trend views | Week-over-week eval + ops metrics | Org Pulse | Phase 4 |
| **4 — Reporting** | Weekly automated reports | Slack/email digest of quality shifts | Org Pulse + eval adapters | Phase 4 |

## Validation (E2E definition)

End-to-end validation for the agentic SDLC program is satisfied in **two phases**:

| Phase | When | What counts as E2E | Evidence |
|-------|------|-------------------|----------|
| **Planning E2E** | Planning phase complete | Harness runs `prd-review` + `design-review` on **6 human-validated reference cases** from real merged `enhancement-proposals` PRs (+ optional 2 FAIL calibration cases) | `evals/review/results/baseline/README.md` |
| **Full agentic SDLC E2E** | Execution phase complete | Planning suite **plus** bugfix eval on **11 real MGMT bug cases** (`osac-bugfix-eval`) via unified report | `evals/results/{run_id}/summary.json` |

**Not E2E for this program:** production EP Review Bot on live PRs, tenant cluster
provisioning, or `_harness-smoke` wiring fixtures alone.

Optional: baseline appendix comparing local harness vs EP bot on 2 design PRs —
informational only, not a pass gate.

## Indirect coverage

RCA accuracy and fix quality are partially observable through planning review
finding recall and bugfix eval `fix_correctness` scores rather than standalone
RCA rubrics in Phase 1 — consistent with sequencing eval harness quality before
operational dashboards.

## Operations metrics (Phase 3)

| Metric | Definition |
|--------|------------|
| **Agent MTTR (primary)** | `New` → first autofix PR opened |
| **Resolution MTTR (secondary)** | `New` → `Closed` |
| Human-wait exclusion | Omit Blocked, Waiting for Reporter, On Hold; **include** Code Review |
| Outlier cap | Single wait segment > 5 business days → exclude from mean, count separately |
| Scope | Agent-labeled OSAC bugs (`jira-autofix-merged`, `jira-autofix-rejected`, successors) |
| Reopened | Excluded from MTTR mean; track **`reopen_rate`** = reopened / closed agent bugs |
| GitHub velocity attribution | PR labels → `Assisted-by:` trailers → bot/service accounts |

Refine against `org-pulse-data` fields during Org Pulse coordination.

## External baselines (not eval ingest targets)

**Unified Operational Intelligence (UOI)** — `devtools.pages.redhat.com/n8n-pulumi-poc` — Konflux
DevLake blueprint `134` + n8n webhooks. **Distinct from** `org-pulse-data` (GitLab ConfigMap
pipelines). OSAC team tabs today:

| Tab | Metric | Program role |
|-----|--------|--------------|
| FTPR | First-time CI pass rate on merged PRs | **Reference baseline** in weekly reports — complementary to harness eval pass rates |
| PR Cycle Time | Commit → merge stage breakdown | Context for operations-phase velocity — separate data plane |
| Issue Cycle Time | Jira commitment → resolution | Context only — MTTR uses autofix-labeled bugs via `org-pulse-data` |
| AI Commit Scanner | AI-assisted commit attribution | Out of scope for this eval program |
| AI Review | Engagement with AI PR review feedback | Out of scope for this eval program |
| Agent Ready | Repo AI-readiness tier compliance | Out of scope for this eval program |

**FTPR definition:** % of merged PRs that pass all CI checks on their first commit (8 OSAC
repos). Example snapshot (2026-07-14, last 30 days, all repos): 73.6% FTPR, 606 merged PRs,
351 first-time passes, 477/606 CI coverage.

Harness eval pass rates measure **skill output quality** against golden cases; FTPR measures
**delivery CI health** on real merged PRs. A skill can regress on golden cases while FTPR rises,
or vice versa — both belong in the program narrative.

## Related artifacts

- Case layout: [`case-schema.md`](case-schema.md)
- Review skills: `skills/prd-review/SKILL.md`, `skills/design-review/SKILL.md`
- Unified report schema: `evals/lib/unified-report.schema.yaml`
- Bugfix ingest contract: `evals/lib/bugfix-ingest.md`
