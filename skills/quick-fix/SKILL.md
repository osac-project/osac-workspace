---
name: quick-fix
description: Unattended bug fix — creates a Jira bug, fixes it in the background, posts a PR, and moves the ticket to Code Review. Use when a bug is found during the current session and needs an immediate fix without interactive phases. For attended, phase-by-phase bug investigation, use /bugfix instead.
---

# Quick Fix Workflow

This skill delegates to the `osac-dev:fix-bug` agent which runs in the background.

## When to Use

- A bug is discovered during the current session and the root cause is already known
- User wants an unattended fix: Jira ticket → code fix → tests → PR in one shot
- For interactive, phase-by-phase investigation of an existing Jira bug, use `/bugfix` instead

## Gather Inputs

Collect from conversation context. Ask only if truly ambiguous:

| Input | Required | Default |
|-------|----------|---------|
| Bug description | Yes | From conversation context |
| Root cause | Yes | From conversation context or investigation |
| Epic key | If ambiguous | Ask user — e.g. "Which epic should I link this to?" |
| Label | No | `OSAC` |
| Affected repo | Yes | Infer from file paths in conversation |

## Execute

Once inputs are gathered, launch the fix-bug agent in the background using the Agent tool:

```
Agent tool call:
  subagent_type: osac-dev:fix-bug
  run_in_background: true
  prompt: |
    Fix this bug end-to-end.

    Bug description: <description>
    Root cause: <root cause>
    Epic: <EPIC-KEY>
    Repo: <repo-name>
    Affected files: <file paths if known>

    <any additional context from the conversation>
```

Tell the user the agent has been launched and they'll be notified when it completes.
