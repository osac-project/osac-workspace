# CLAUDE.md

@AGENTS.md

## Detailed Rules (auto-loaded from `.claude/rules/`)

- **`cross-repo-workflow.md`** — workspace-local link to [`guidance/cross-repo-workflow.md`](guidance/cross-repo-workflow.md)
- **`architecture-patterns.md`** — current OSAC architecture and tenancy references (centralized in `osac-ai-skills`, symlinked)
- **`networking-design-alignment.md`** — Networking design/implementation alignment triggers (centralized in `osac-ai-skills`, symlinked)
- **`request-path-tracing.md`** — points to the fulfillment-service request-path guide (centralized in `osac-ai-skills`, symlinked)
- **`dev-conventions.md`** — Branch naming, fork-based push rules, DCO sign-off, AI attribution, Jira conventions (centralized in `osac-ai-skills`, symlinked)

## Claude Command Syntax

Workflows from AGENTS.md are invoked with `/skill:phase` syntax in Claude Code:

- **bugfix:** `/bugfix:assess`, `/bugfix:reproduce`, `/bugfix:diagnose`, `/bugfix:fix`, `/bugfix:test`, `/bugfix:review`, `/bugfix:document`, `/bugfix:pr`
- **implement:** `/implement:ingest`, `/implement:plan`, `/implement:code`, `/implement:validate`, `/implement:publish`
- **PRD:** `/prd:ingest`, `/prd:clarify`, `/prd:draft`, `/prd:publish`, `/prd:respond`
- **Design:** `/design:ingest`, `/design:research`, `/design:draft`, `/design:publish`, `/design:respond`, `/design:decompose`, `/design:sync`
- **EP (legacy):** `/ep.create`
- **E2E:** `/e2e`, `/debug-e2e`

## PRD and Design Configuration

See **Feature Dimensions Context** in `AGENTS.md` — both `/prd:ingest` and `/design:ingest` must read all files in `.design/context/` during their ingest phase.
