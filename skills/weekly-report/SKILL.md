---
name: weekly-report
description: "Generate a weekly progress report for OSAC — what changed in the last 7 days, current state snapshot, progress by use case, and blockers. Use when asked for a weekly update, status summary, or progress check."
---

# Weekly Report

Generate a weekly progress report showing what changed in the last 7 days, current milestone state, and progress by use case.

**CRITICAL**: Use `~/go/bin/jira` as the jira binary. All `list` commands use `--plain --no-headers` for clean output. Do NOT use `--no-input` on `list` or `view` commands — it is not supported.

**IMPORTANT**: Features with resolution "Duplicate" are retired consolidations — they were replaced by unified features. They must NOT appear anywhere in the report (not in highlights, not in progress tables, not in detailed status). When querying closed features, always filter with `resolution = Done` to exclude duplicates and other non-delivered resolutions.

## Input

Accept an optional fix version as argument (e.g., `0.1`). If no version specified, report across all open features with any fix version set.

## Workflow

### Step 1: Query This Week's Changes

Run three queries to capture what moved in the last 7 days.

**Completed (closed in the last 7 days):**

```bash
~/go/bin/jira issue list --project OSAC -q "type in (Feature, Epic) AND status = Closed AND resolved >= -7d AND resolution = Done" --plain --no-headers
```

**Newly started (moved to In Progress in the last 7 days):**

```bash
~/go/bin/jira issue list --project OSAC -q "type in (Feature, Epic) AND status = 'In Progress' AND updated >= -7d" --plain --no-headers
```

Note: the "newly started" query may include items that were already In Progress and just got updated. To distinguish truly new starts, check if the item was in a different status before (e.g., was New/To Do). Use `jira issue view <KEY> --plain` and look at the status change history if needed. If this is too noisy, just report all In Progress items updated this week and let the reader filter.

**Newly created (created in the last 7 days):**

```bash
~/go/bin/jira issue list --project OSAC -q "type in (Feature, Epic) AND created >= -7d" --plain --no-headers
```

If a fix version is specified, add `AND fixVersion = '<VERSION>'` to each query. Since epics don't have fix versions in this project, also check if an epic's parent feature has the target version — use `jira issue view <KEY> --raw` to get the parent, then check the parent's fix version.

### Step 2: Query Current State

Query open features and genuinely completed features (resolution = Done only).

**Open features — if a version is specified:**

```bash
~/go/bin/jira issue list --project OSAC -q "type = Feature AND fixVersion = '<VERSION>' AND status != Closed" --plain --no-headers
```

**Open features — if no version:**

```bash
~/go/bin/jira issue list --project OSAC -q "type = Feature AND status != Closed AND fixVersion is not EMPTY" --plain --no-headers
```

**Completed features (for progress counting and detailed status) — only resolution = Done:**

```bash
~/go/bin/jira issue list --project OSAC -q "type = Feature AND fixVersion = '<VERSION>' AND status = Closed AND resolution = Done" --plain --no-headers
```

For each feature (open and completed), fetch child epics:

```bash
~/go/bin/jira issue list --project OSAC -q "type = Epic AND parent = <FEATURE-KEY>" --plain --no-headers
```

### Step 3: Identify Stale Items

Query epics that are In Progress but haven't been updated in 14+ days — these are potential blockers or forgotten work:

```bash
~/go/bin/jira issue list --project OSAC -q "type = Epic AND status = 'In Progress' AND updated <= -14d" --plain --no-headers
```

If a version is specified, filter to only epics whose parent feature has that version.

### Step 4: Group by Use Case

Use the same grouping rules as the version-report skill:

| Component / Keyword | Use Case Category |
|---------------------|-------------------|
| CaaS | CaaS — Cluster Provisioning |
| VMaaS, VCD | VMaaS — VM Management |
| Storage | Storage |
| Connectivity&Fabric, Networking | Networking |
| Core | Core — Multi-Tenancy & Platform |
| Enclave | Enclave & Deployment |
| Infrastructure | Infrastructure |
| BMaaS | BMaaS — Bare Metal Lifecycle |
| Metering | Metering & Quota |
| UI | UI |

**Keyword fallback** (scan the feature summary if no component):
- Contains "CaaS" or "Cluster" → CaaS
- Contains "VMaaS" or "VM " → VMaaS
- Contains "Network" or "Subnet" or "VPN" or "Netris" or "CUDN" or "MetalLB" or "VLAN" or "SecurityGroup" or "PublicIP" → Networking
- Contains "Enclave" or "GoRI" or "Plugin" → Enclave & Deployment
- Contains "Helm" or "Install" or "Packaging" or "Productization" → Infrastructure
- Contains "Storage" or "VAST" or "Tier" → Storage
- Contains "Tenant" or "Org" or "Auth" or "RBAC" or "Catalog" → Core
- Contains "Metering" or "Quota" or "Billing" → Metering & Quota
- Otherwise → Uncategorized

### Step 5: Compute Progress Metrics

For each use-case category, compute:
- Number of features
- Total epics across those features
- Epics by status: Closed, In Progress, New
- Percentage complete: (Closed / Total) × 100, rounded to nearest integer

### Step 6: Generate Report

```markdown
# OSAC Weekly Report — <start date> to <end date>

Version: <VERSION or "All open milestones">

---

## This Week's Highlights

### Completed
- OSAC-XXX — <Title> (<type> under <parent feature if epic>)

<If nothing was completed, write: "No items completed this week.">

### Newly Started
- OSAC-ZZZ — <Title> (moved to In Progress)

<If nothing newly started, write: "No new items started this week.">

### Newly Created
- OSAC-AAA — <Title> (<type>)

<If nothing created, write: "No new items created this week.">

### Blockers & Risks

<List items that are:>
- In Progress but not updated in 14+ days (stale)
- Marked as Blocker or Critical priority
- Any items the reporter flagged as blocked

<If no blockers, write: "No blockers or risks identified.">

---

## Progress by Use Case

| Use Case | Features | Epics | Done | In Progress | New | % Complete |
|----------|----------|-------|------|-------------|-----|------------|
| <category> | <n> | <n> | <n> | <n> | <n> | <n>% |

---

## Detailed Status

<For each use case category, show features and their epics. Features that had changes this week get the full epic table with a "Changed" column. Features with no changes this week get a condensed one-line summary.>

### <Use Case Category>

#### OSAC-XXXX — <Feature Title> (<Status>) — *changed this week*

| Epic | Status | Changed |
|------|--------|---------|
| OSAC-ZZZ — <Title> | Closed | Closed this week |
| OSAC-AAA — <Title> | In Progress | |

*N epics total (X Closed, Y In Progress, Z New)*

#### OSAC-YYYY — <Feature Title> (<Status>) — *no changes*
*N epics (X Closed, Y In Progress, Z New) — no movement this week*

<Repeat for each use case category>
```

### Step 7: Present to User

Output the full report as markdown. Do not write it to a file unless the user asks.

After presenting the report, ask:
- "Would you like me to save this report to a file?"
- "Any sections to adjust?"

## Tips

- **Rate limiting**: Batch jira queries. Don't fire more than 5 in parallel.
- **"Newly started" noise**: The updated >= -7d query for In Progress items may include items that were just commented on, not truly started. If the list is long, note this caveat in the report.
- **Stale threshold**: 14 days is the default for flagging stale items. If the user wants a different threshold, adjust the query.
- **No version specified**: When reporting across all versions, the progress table shows aggregate numbers. The detailed section still groups by use case.
- **Empty weeks**: If nothing changed, the report should still show the current state snapshot — it's still useful to see where things stand.
