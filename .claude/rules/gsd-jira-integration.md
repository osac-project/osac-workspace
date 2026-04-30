# GSD-Jira Integration

This project integrates GSD workflow lifecycle with Jira (Red Hat Jira, MGMT project). The mapping is stored in `.planning/config.json` under the `jira` key. All Jira operations are optional — they silently skip if `jira` CLI is not installed or not configured.

## Mapping Structure

```json
{
  "jira": {
    "epic": "MGMT-12345",
    "phases": {
      "1": "MGMT-12346",
      "2": "MGMT-12347"
    }
  }
}
```

## Lifecycle Hooks

During GSD workflows, apply the Jira hooks defined in `.claude/workflows/gsd-jira-hooks.md`:

| GSD Command | Jira Action |
|-------------|-------------|
| `/gsd:new-milestone` | Create or link Epic |
| `/gsd:plan-phase` | Create Task under Epic |
| `/gsd:execute-phase` | Move Task to In Progress |
| `/gsd:execute-plan` | Use Jira key as commit prefix |
| `/gsd:complete-milestone` | Move Epic to Done |

## Manual Mapping

Use `/jira-sync` to manually link or unlink Jira items:

```text
/jira-sync status                      # show current mapping
/jira-sync link-epic MGMT-23853        # link epic to milestone
/jira-sync link-phase 1 MGMT-24040     # link ticket to phase
/jira-sync unlink                      # remove all mappings
```

## Prerequisites

- `jira` CLI installed and configured for Red Hat Jira (`issues.redhat.com`)
- Bearer token in `~/.netrc` for authentication
- Default project: `MGMT`, default label: `OSAC`
