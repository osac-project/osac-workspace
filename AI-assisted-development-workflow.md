# AI-Assisted Development Workflow

Always start from `osac-workspace/` and run `./bootstrap.sh` to clone/update all component repos and install the latest AI workflow skills before starting a new session.

## 1. Create a Jira Feature

`/osac-feature` — Describe what you want to build. Creates a Feature issue in Jira (OSAC project) that anchors everything downstream.

## 2. Write a PRD

`/prd` — Ingests requirements from the Jira Feature, walks through clarifying ambiguities, drafts a Product Requirements Document, and publishes as a PR to `enhancement-proposals`.

Phases: `/prd:ingest` → `/prd:clarify` → `/prd:draft` → `/prd:revise` → `/prd:publish` → `/prd:respond`

Get the PR reviewed and merged before moving on.

## 3. Write a Design (Enhancement Proposal)

`/design` — Takes the merged PRD, researches the problem space, drafts a technical design document (EP), decomposes work into epics and stories, and publishes as a PR to `enhancement-proposals`.

Phases: `/design:ingest` → `/design:research` → `/design:draft` → `/design:decompose` → `/design:revise` → `/design:publish` → `/design:respond`

Get the PR reviewed and merged.

## 4. Create Jira Epics & Tasks

`/design:sync` — Syncs the approved task breakdown from the design into Jira as epics and tasks under the Feature.

## 5. Implement

`/implement` — Pick up a Jira task, plan the implementation, write tests and code via TDD, validate, and publish a PR.

Phases: `/implement:ingest` → `/implement:plan` → `/implement:code` → `/implement:validate` → `/implement:publish` → `/implement:respond`

## Other Useful Skills

- `/bugfix` — Systematic bug investigation and fix (phase-based)
- `/create-pr` — Runs repo-specific validation and creates a PR via the fork workflow
- `/code-review` — Review your current diff before submitting

Each skill is phase-based — you can jump directly to any phase (e.g., `/prd:draft`, `/implement:code`).
