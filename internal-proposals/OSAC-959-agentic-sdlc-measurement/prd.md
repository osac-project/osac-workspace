# Agentic SDLC Measurement

| Field       | Value   |
|-------------|---------|
| Author(s)   | Tommy Hughes |
| Jira        | [OSAC-959](https://redhat.atlassian.net/browse/OSAC-959) |
| Date        | 2026-07-23 |

*Scope note: this is an internal engineering-tooling PRD — it has no tenant-facing surface, and none of OSAC's four canonical personas or tenant-facing cross-cutting dimensions apply (see User Stories).*

## Problem Statement

The team is transitioning bug-fix and feature-development workflows to an agentic (AI-agent-driven) SDLC, but has no quantitative way to know whether that transition is actually working. Today's only measurement is an existing FTPR (first-time-pass-rate) dashboard that predates the agentic effort and wasn't designed to isolate agent-driven work from human-driven work. Without dedicated metrics for MTTR, RCA accuracy, and development velocity, engineering leadership, product owners, and DevOps engineers cannot tell whether AI agents are improving outcomes, holding steady, or introducing risk. Any automated scoring built to answer that question is itself unproven until it addresses a specific trust gap: nothing today prevents an LLM-as-judge from favoring output written in its own model family's style over output that is actually better. [Jira: OSAC-959] [Clarify: R2.Q1]

## In Scope

- A documented measurement framework defining MTTR, RCA accuracy (indirect, via review-finding recall and bug-fix correctness scoring), and development velocity for agentic bug-fix and feature-development workflows, published where engineering leadership, product owners, and DevOps engineers can look up each metric's definition and current value. [Jira: OSAC-959]
- Automated data collection from Jira and GitHub feeding that framework. [Jira: OSAC-959]
- A judge-model policy: any automated agent-performance score is only trusted once it has been shown to agree with a human reviewer's judgment on real, human-reviewed reference cases. A score that hasn't been checked this way is treated as unproven, not authoritative. A judge/human agreement rate is published alongside any score that relies on this policy, so a reviewer can look up how well-calibrated that score is before trusting it. [Clarify: R2.Q1]
- Extension of the existing Org Pulse dashboard with new tabs/data surfacing agent performance trends — not a new, standalone dashboard. [Clarify: R1.Q4]
- A dedicated weekly automated reporting pipeline, sourced from this framework's own data feeds, distinct from existing personal-activity reporting tooling. [Clarify: R1.Q5]
- Validation of the framework against real end-to-end use cases, delivered in phases (see Assumptions for the specific sequencing). [Jira: OSAC-959]

## Out of Scope

- Code quality metrics (test coverage, cyclomatic complexity, etc.). [Jira: OSAC-959]
- Tenant User productivity tracking. [Jira: OSAC-959]
- Cost analysis of production/tenant AI model usage (e.g., per-tenant AI usage billing). [Clarify: R1.Q3]
- Per-run cost telemetry for eval/CI-review runs (what an automated review or eval invocation costs) — a distinct observability signal from the MTTR/RCA/velocity metrics above and from tenant AI-usage billing; deferred as its own feature. [Clarify: R1.Q3]

## User Stories

These personas are internal engineering roles who consume agentic-SDLC measurement output — not OSAC's tenant-facing personas (Cloud Provider Admin, Cloud Infrastructure Admin, Tenant Admin, Tenant User). This feature has no tenant-observable behavior and none of OSAC's tenant-facing cross-cutting dimensions (Tenant Onboarding, Networking, Storage, Provisioning, Inventory, UI-in-osac-ui) apply. [Clarify: R1.Q1]

### Lead Engineer

- As a lead engineer, I want to see MTTR trend data for agent-driven bug fixes so that I can tell whether AI agents are resolving issues faster over time. [Jira: OSAC-959]

### Product Owner

- As a product owner, I want to see cycle-time data — from Jira Task creation to merged PR — for agent-assisted feature work, so that I can plan releases with a realistic sense of agent-assisted throughput. [Jira: OSAC-959]

### DevOps Engineer

- As a DevOps engineer, I want a dashboard tracking agent success rates over time so that I can monitor the health of the agentic SDLC without manually cross-referencing Jira and GitHub. [Jira: OSAC-959]

## Assumptions

- No numeric target thresholds exist yet for MTTR improvement, RCA accuracy, or velocity change — the framework establishes baselines first; specific targets are not yet defined. [Clarify: Remaining Gaps]
- End-to-end validation against real use cases proceeds in phases rather than all at once: an initial planning-review golden set, followed later by real bug-fix outcome validation once bug-fix evaluation is integrated — full validation is not available from day one. Each phase is complete when its golden dataset and a baseline judge/human agreement report both exist and are reproducible, giving reviewers a concrete, inspectable checkpoint rather than an open-ended validation effort. [Jira: OSAC-959]

## Dependencies

- **Org Pulse dashboard (OSAC-2004):** Provides the dashboard surface this framework's trend data extends; must not duplicate EP Review Bot score visibility already dashboarded there (OSAC-2007). [Clarify: R1.Q4]
- **Bug-fix evaluation harness (OSAC-516):** Supplies the RCA-accuracy and bug-fix-outcome data this framework ingests rather than re-implementing; currently has a single-point-of-failure hosting risk with no organizational backup. [Jira: OSAC-959]
- **Alignment sign-off (Eran Cohen):** Two program-level questions — comfortable with phased E2E validation and indirect RCA accuracy for this milestone, and whether Epic 3–4 priorities should shift — remain unanswered as of this PRD. [Clarify: R1.Q6]

---

## Provenance

Authored: revise @ prd 0.6.0 - 7b6dfe0, workspace OSAC-2264-review-harness-judges @ 6f530dcb
Phases: draft, revise, revise

<!-- ai-workflow-provenance:{"schema_version":1,"provenance_kind":"session","workflow":"prd","workflow_version":"0.6.0","ai_workflows":"7b6dfe0","source_repo":"6f530dcb","source_repo_branch":"OSAC-2264-review-harness-judges","commits_behind_main":0,"commits_ahead_main":6,"main_ref":"main","phases":["draft","revise","revise"],"authoring_modes":["skill"],"context_changed":false} -->
