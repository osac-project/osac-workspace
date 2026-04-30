---
name: jira-sync
description: Link GSD milestones and phases to Jira epics and tickets, or view current mapping
argument-hint: "<link-epic MGMT-XXXXX | link-phase N MGMT-XXXXX | status | unlink>"
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
- `link-epic MGMT-XXXXX` — Link existing Jira epic to current milestone
- `link-phase <phase-number> MGMT-XXXXX` — Link existing Jira ticket to a phase
- `status` — Show current Jira mapping with live status from Jira
- `unlink` — Remove all Jira mappings

When no subcommand is given, show status.
</objective>

<execution_context>
Read and follow the workflow at .claude/workflows/jira-sync.md
</execution_context>

<context>
Subcommand and arguments: $ARGUMENTS

Jira CLI is pre-configured for Red Hat Jira (issues.redhat.com), MGMT project.
Mapping is stored in `.planning/config.json` under the `jira` key.
</context>
