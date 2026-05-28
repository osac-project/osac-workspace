---
name: jira-sync
description: Link GSD milestones and phases to Jira epics and tickets, or view current mapping
argument-hint: "<link-epic OSAC-XXXXX | link-phase N OSAC-XXXXX | status | unlink>"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
---
<objective>
Manage the Jira mapping for the current GSD milestone. Link existing Jira epics and tickets to milestones and phases, view current mapping, or remove mappings.

Subcommands:
- `link-epic OSAC-XXXXX` — Link existing Jira epic to current milestone
- `link-phase <phase-number> OSAC-XXXXX` — Link existing Jira ticket to a phase
- `status` — Show current Jira mapping with live status from Jira
- `unlink` — Remove all Jira mappings

When no subcommand is given, show status.
</objective>

<execution_context>
Read and follow the workflow at .claude/workflows/jira-sync.md
</execution_context>

<context>
Subcommand and arguments: $ARGUMENTS

Jira CLI is pre-configured for Red Hat Jira (redhat.atlassian.net), OSAC project.
Mapping is stored in `.planning/config.json` under the `jira` key.
</context>
