---
name: generate-status-report
description: "Generate project status reports from Jira issues using jira-cli. When an agent needs to: (1) Create a status report for a project, (2) Summarize project progress or updates, (3) Generate weekly/daily reports from Jira, or (4) Analyze project blockers and completion. Queries Jira issues, categorizes by status/priority, and creates formatted reports."
---

# Generate Status Report

Automatically query Jira for project status, analyze issues, and generate formatted status reports using `jira-cli`.

**CRITICAL**: This skill should be **interactive**. Always clarify scope (time period, audience) with the user before generating the report.

All commands use `--plain` for clean output and `--no-input` to skip interactive prompts.

## Workflow

1. **Identify scope** — Determine project, time period, and target audience
2. **Query Jira** — Fetch relevant issues using JQL queries
3. **Analyze data** — Categorize issues and identify key insights
4. **Format report** — Structure content based on audience and purpose

## Step 1: Identify Scope

Clarify these details with the user:

**Project identification:**
- Which Jira project key? (e.g., "MGMT", "ENG")
- If unsure: `jira project list --plain`

**Time period:**
- If not specified, ask: "What time period should this report cover? (default: last 7 days)"
- Options: Weekly (7 days), Daily (24 hours), Sprint-based, Custom period

**Target audience:**
- If not specified, ask: "Who is this report for?"
- **Executives**: High-level summary with key metrics and blockers
- **Team-level**: Detailed breakdown with issue-by-issue status
- **Daily standup**: Brief update on yesterday/today/blockers

## Step 2: Query Jira

Execute multiple targeted queries rather than one large query.

### Completed Issues

```bash
jira issue list --jql 'project = PROJECT_KEY AND status = Done AND resolved >= -7d ORDER BY resolved DESC' --plain
```

### In-Progress Issues

```bash
jira issue list --jql 'project = PROJECT_KEY AND status = "In Progress" ORDER BY priority DESC' --plain
```

### Blocked / High Priority Issues

```bash
jira issue list --jql 'project = PROJECT_KEY AND (priority IN (Highest, High) OR status = Blocked) AND status != Done ORDER BY priority DESC' --plain
```

### All Open Issues

```bash
jira issue list --jql 'project = PROJECT_KEY AND status != Done ORDER BY priority DESC, updated DESC' --plain
```

### Issues Updated in Period

```bash
jira issue list --jql 'project = PROJECT_KEY AND updated >= -7d ORDER BY priority DESC' --plain
```

Use `--paginate 50` if more results are needed.

### Data to Extract

For each issue, capture: key, summary, status, priority, assignee, dates. Use `jira issue view <KEY> --plain` for deeper details on blockers.

## Step 3: Analyze Data

Process the retrieved issues to identify:

**Metrics:**
- Total issues by status (Done, In Progress, Blocked, etc.)
- Number of high priority items
- Unassigned issue count

**Key insights:**
- Major accomplishments (recently completed high-value items)
- Critical blockers (blocked high priority issues)
- At-risk items (overdue or stuck in progress)
- Resource bottlenecks (one assignee with many issues)

**Categorization:**
Group issues logically by status, priority, assignee, or epic.

## Step 4: Format Report

### For Executives

Use **Executive Summary Format**:
- Brief overall status (On Track / At Risk / Blocked)
- Key metrics (total, completed, in progress, blocked)
- Top 3 highlights (major accomplishments)
- Critical blockers with impact
- Upcoming priorities

Keep it concise — 1-2 pages maximum.

### For Team-Level Reports

Use **Detailed Technical Format**:
- Completed issues listed with keys and links
- In-progress issues with assignee and priority
- Blocked issues with blocker description and action needed
- Risks and dependencies
- Next period priorities

### For Daily Updates

Use **Daily Standup Format**:
- What was completed yesterday
- What's planned for today
- Current blockers

Keep it brief.

### Report Structure Example

```markdown
# [Project Name] - Status Report - [Date]

## Overall Status: [On Track / At Risk / Blocked]

## Key Metrics
| Metric | Count |
|--------|-------|
| Completed (this period) | X |
| In Progress | X |
| Blocked | X |
| Total Open | X |

## Highlights
- Completed [PROJ-123] - Major feature description
- Completed [PROJ-124] - Another accomplishment

## Blockers
- [PROJ-456] - Description (assigned to @user, blocked by X)
  - **Action needed:** [what needs to happen]

## In Progress
- [PROJ-789] - Feature work (assigned to @user, priority: High)

## Upcoming Priorities
- [PROJ-890] - Next planned work
```

Include links in format: `https://redhat.atlassian.net/browse/PROJ-123`

## Tips for Quality Reports

- **Be data-driven:** Include specific numbers and issue keys
- **Highlight what matters:** Lead with blockers and accomplishments
- **Make it actionable:** For blockers, state what action is needed and from whom
- **Keep it consistent:** Use the same format for recurring reports

## When NOT to Use This Skill

**Don't use for:**
- Creating individual tasks (use jira-task-management)
- Triaging bugs (use triage-issue)
- Creating backlogs from specs (use spec-to-backlog)

**Use only when:** A status report or project summary is needed.
