# CLAUDE.md

@AGENTS.md

## Critical Rules

- **`osac-workspace/` is the project root** — all work happens from here; component `CLAUDE.md` files are loaded via progressive disclosure
- **Read component `CLAUDE.md` first** before making changes in any component repo (progressive disclosure). Where a component also has `AGENTS.md`, it holds tool-agnostic conventions; `CLAUDE.md` remains the Claude entry point.

## Detailed Rules (auto-loaded from `.claude/rules/`)

- **`protobuf-conventions.md`** — Proto naming, API structure, field guidelines, type/service patterns
- **`cross-repo-workflow.md`** — Git worktrees, cross-component changes, PR rules
- **`architecture-patterns.md`** — Multi-tenancy, resource hierarchy, service stack, integration testing

## Claude Command Syntax

Workflows from AGENTS.md are invoked with `/skill:phase` syntax in Claude Code:

- **bugfix:** `/bugfix:assess`, `/bugfix:reproduce`, `/bugfix:diagnose`, `/bugfix:fix`, `/bugfix:test`, `/bugfix:review`, `/bugfix:document`, `/bugfix:pr`
- **implement:** `/implement:ingest`, `/implement:plan`, `/implement:code`, `/implement:validate`, `/implement:publish`
- **PRD:** `/prd:ingest`, `/prd:clarify`, `/prd:draft`, `/prd:publish`, `/prd:respond`
- **Design:** `/design:ingest`, `/design:draft`, `/design:publish`, `/design:respond`, `/design:decompose`, `/design:sync`
- **EP (legacy):** `/ep.create`
- **E2E:** `/e2e`, `/debug-e2e`

## PRD and Design Configuration

Both `/prd:ingest` and `/design:ingest` must read all files in `.design/context/` during their ingest phase:

- **`osac-dimensions.md`** — Cross-cutting dimensions (services, personas, tenant onboarding, inventory, provisioning, networking, storage, installation, E2E testing, documentation, UI) that every OSAC feature must address. Use it to guide clarifying questions during `/prd:clarify` and persona/user-story scope during `/prd:draft` (see § Personas and `osac-docs/personas.md`); ensure the design covers all relevant dimensions.
- **`review-patterns.md`** — Common EP reviewer feedback themes, anti-patterns, and the EP reference library. Use during `/prd:draft` and `/design:draft` to anticipate reviewer expectations.
