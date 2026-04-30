---
name: fix-bug
description: End-to-end bug fix workflow — opens a Jira bug, writes the fix with tests, verifies build/format/tests pass, commits, posts a PR, and moves the ticket to Code Review. Use when the user says 'fix this bug', 'open a bug and fix it', 'file a bug', or describes a bug they want tracked and resolved in Jira with a PR.
---

# Fix Bug Workflow

This skill delegates to the `osac-dev:fix-bug` agent which runs in its own context.

## When to Use

- User describes a bug and wants it tracked + fixed
- User says "fix this bug", "open a bug for this", "file a bug and fix it"
- A bug is discovered during development and needs the full workflow

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
