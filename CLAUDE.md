# CLAUDE.md

@AGENTS.md

## Critical Rules

- **`osac-workspace/` is the project root** — all work happens from here; component `CLAUDE.md` files are loaded via progressive disclosure
- **Read component `CLAUDE.md` first** before making changes in any component repo (progressive disclosure). Where a component also has `AGENTS.md`, it holds tool-agnostic conventions; `CLAUDE.md` remains the Claude entry point.
- **Edit OSAC skills only in [`osac-project/osac-ai-skills`](https://github.com/osac-project/osac-ai-skills)** — bump `metadata.version` there; this workspace only vendors skills via bootstrap.

## Detailed Rules (auto-loaded from `.claude/rules/`)

- **`cross-repo-workflow.md`** — Git worktrees, cross-component changes, remotes and PR mechanics (workspace-authored, workspace-local)
- **`architecture-patterns.md`** — Multi-tenancy, resource hierarchy, service stack, integration testing (centralized in `osac-ai-skills`, symlinked)
- **`networking-design-alignment.md`** — Networking design/implementation alignment triggers (centralized in `osac-ai-skills`, symlinked)
- **`request-path-tracing.md`** — Request path tracing conventions (centralized in `osac-ai-skills`, symlinked)
- **`dev-conventions.md`** — Branch naming, fork-based push rules, DCO sign-off, AI attribution, Jira conventions (centralized in `osac-ai-skills`, symlinked)

## Claude Command Syntax

Workflows from AGENTS.md are invoked with `/skill:phase` syntax in Claude Code:

- **bugfix:** `/bugfix:assess`, `/bugfix:reproduce`, `/bugfix:diagnose`, `/bugfix:fix`, `/bugfix:test`, `/bugfix:review`, `/bugfix:document`, `/bugfix:pr`
- **implement:** `/implement:ingest`, `/implement:plan`, `/implement:code`, `/implement:validate`, `/implement:publish`
- **PRD:** `/prd:ingest`, `/prd:clarify`, `/prd:draft`, `/prd:publish`, `/prd:respond`
- **Design:** `/design:ingest`, `/design:research`, `/design:draft`, `/design:decompose`, `/design:revise`, `/design:publish`, `/design:respond`, `/design:sync`
- **EP (legacy):** `/ep.create`
- **E2E:** `/e2e`, `/debug-e2e`

## PRD and Design Configuration

See **Feature Dimensions Context** in `AGENTS.md` — both `/prd:ingest` and `/design:ingest` must read all files in `.design/context/` during their ingest phase.
