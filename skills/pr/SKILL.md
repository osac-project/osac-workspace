---
name: pr
version: 0.3.0
description: >-
  PR lifecycle workflow for multi-repo workspaces — create PRs, review PRs,
  respond to review comments, and fix review findings across component
  repositories. Use when creating, reviewing, responding to, or fixing
  pull requests in any component repo (e.g., osac-operator, fulfillment-service).
  Activated by commands: /create, /review, /respond, /fix.
---
# PR Lifecycle Workflow

## Invocation

Every phase accepts a component directory and optional PR number:

```
/pr:<phase> <component-dir> [pr-number]
```

## Quick Start

1. If the user invoked a specific command (e.g., `/create`, `/review`), read
   `commands/{command}.md` and follow it.
2. Otherwise, read [skills/controller.md](skills/controller.md) to load the workflow controller.

If a step fails, stop and report the error. Do not advance to the next phase.

Read [guidelines.md](guidelines.md) for principles, hard limits, and safety rules.
