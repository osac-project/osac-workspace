---
name: milestone-scope
description: "Scope and readiness assessment for an OSAC milestone — features grouped by use case, epic breakdown with statuses, and gap analysis. Use when asked to report on a version, milestone, or release scope."
---

# Milestone Scope

Generate a structured milestone scope and readiness assessment showing what use cases a specific OSAC version covers, which features and epics deliver them, and where gaps exist.

**CRITICAL**: Use `jira` as the jira binary (must be on PATH). All `list` commands use `--plain --no-headers` for clean output. Do NOT use `--no-input` on `list` or `view` commands — it is not supported.

**IMPORTANT**: Only features with resolution "Done" appear in the completed work section. Features resolved as "Duplicate", "Won't Do", "Cannot Reproduce", or any other non-Done resolution are retired/consolidated and must NOT appear anywhere in the report.

## Input

Accept a fix version as argument. Default to `0.1` if not specified.

## Workflow

### Step 1: Query Features

Fetch **open** features for the target version:

```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<VERSION>' AND status != Closed" --plain --no-headers
```

Fetch **closed** features for the target version (completed work) — only genuinely completed:

```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<VERSION>' AND status = Closed AND resolution = Done" --plain --no-headers
```

Keep the two lists separate — open features go in the main report, closed features go in the "Completed Work" section.

### Step 2: Fetch Feature Details and Epics

For each feature from Step 1, fetch its full details (description, component, fixVersions):

```bash
jira issue view <FEATURE-KEY> --plain
```

Extract: key, summary, status, component(s), description, and fixVersion(s). The component is needed for use-case grouping in Step 3. The description is needed for capability extraction in Step 4. The fixVersions are needed for multi-version gap detection.

Then fetch child epics — use a batched query when there are multiple features:

```bash
jira issue list --project OSAC -q "type = Epic AND parent in (<FEATURE-KEY-1>, <FEATURE-KEY-2>, ...)" --plain --no-headers
```

If the feature count is small (< 5), per-feature queries are fine:

```bash
jira issue list --project OSAC -q "type = Epic AND parent = <FEATURE-KEY>" --plain --no-headers
```

For each child epic, extract: key, summary, status.

**Note:** Fix versions are tracked at the Feature level only in this project. Do NOT query or report fix versions on epics.

### Step 3: Group by Use Case

Group features into use-case categories. Use the **component** field (fetched in Step 2) as the primary grouping key. If a feature has no component, fall back to keyword matching on the summary.

**Grouping rules (check in this order):**

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
- Contains "VMaaS" or "VM" → VMaaS
- Contains "Network" or "Subnet" or "VPN" or "Netris" or "CUDN" or "MetalLB" or "VLAN" or "SecurityGroup" or "PublicIP" → Networking
- Contains "Enclave" or "GoRI" or "Plugin" → Enclave & Deployment
- Contains "Helm" or "Install" or "Packaging" or "Productization" → Infrastructure
- Contains "Storage" or "VAST" or "Tier" → Storage
- Contains "Tenant" or "Org" or "Auth" or "RBAC" or "Catalog" → Core
- Contains "Metering" or "Quota" or "Billing" → Metering & Quota
- Otherwise → Uncategorized

### Step 4: Generate Report

The report has **three parts**: an executive summary, a detailed breakdown, and completed work. This lets readers get the high-level picture quickly and drill into details only where needed.

Output the report in this format:

```markdown
# OSAC Version <VERSION> — Milestone Scope

Generated: <current date>

---

# Part 1: Executive Summary

## Metrics

- **Total features:** <count> (<open count> open, <closed count> completed)
- **Total epics (under open features):** <count>

## Use Cases in This Version

### 1. <Use Case Category>
Features: OSAC-XXXX, OSAC-YYYY
- Capability 1
- Capability 2
- Capability 3

### 2. <Use Case Category>
Features: OSAC-ZZZZ
- Capability 1
- Capability 2

<Repeat for each use case category. For each feature, use the description fetched in Step 2 to extract key capabilities as bullet points. If the description has a "Use Cases" or "Feature Goal" section, use that. If the description is empty or a placeholder template, derive capabilities from the feature title and its child epic summaries.>

## Gaps & Observations

<Analyze and list:>
- **Features with multiple fix versions** — features should map to exactly one fix version. Check the fixVersions fetched in Step 2 and flag any feature with more than one.
- Features with NO child epics (no work breakdown)
- Features where all child epics are Closed but the feature is still open (should it be closed?)
- Use case categories with no features (if any expected ones are missing)
- Features with placeholder/template descriptions that need to be filled in

---

# Part 2: Detailed Breakdown

## <Use Case Category>

### OSAC-XXXX — <Feature Title> (<Status>)

| Epic | Status |
|------|--------|
| OSAC-ZZZ — <Title> | <Status> |
| OSAC-AAA — <Title> | <Status> |

*For features with 3 or more epics, add a status breakdown summary line after the table:*
*N epics total (X Closed, Y In Progress, Z New)*

### OSAC-YYYY — <Feature Title> (<Status>)

| Epic | Status |
|------|--------|
| ... | ... |

---

<Repeat for each use case category>

---

# Part 3: Completed Work

Features in this version that are already closed. Grouped by use case category using the same grouping rules.

## <Use Case Category>

| Feature | Summary |
|---------|---------|
| OSAC-XXXX | <Title> |
| OSAC-YYYY | <Title> |

<Repeat for each use case category that has closed features. If no closed features exist, omit Part 3 entirely.>
```

### Step 5: Present to User

Output the full report as markdown. Do not write it to a file unless the user asks.

After presenting the report, ask:
- "Would you like me to save this report to a file?"
- "Any use case categories that should be adjusted?"

## Tips

- **Rate limiting**: If there are many features, batch the epic queries using `parent in (...)`. Don't fire more than 5 jira commands in parallel.
- **Large features**: For features with 10+ epics (like Packaging), show all epics but note the count.
- **Multiple versions**: The user can run this for different versions to compare scope (e.g., `/milestone-scope 0.1` vs `/milestone-scope 0.2`).
- **Part 3 only shows resolution = Done**: If the user wants to see other closed features, they should check Jira directly.
