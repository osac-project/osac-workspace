---
name: version-report
description: "Generate a milestone report for an OSAC version — features grouped by use case, epic breakdown with statuses, and gap analysis. Use when asked to report on a version, milestone, or release scope."
---

# Version Report

Generate a structured milestone report showing what use cases a specific OSAC version covers, which features and epics deliver them, and where gaps exist.

**CRITICAL**: Use `jira` as the jira binary (it may be at `/usr/local/sbin/jira` or `~/go/bin/jira` — use whichever is found via `which jira`). All commands use `--plain --no-headers` for clean output.

## Input

Accept a fix version as argument. Default to `0.1` if not specified.

## Workflow

### Step 1: Query Features

Fetch **open** features for the target version:

```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<VERSION>' AND status != Closed" --plain --no-headers
```

Fetch **closed** features for the target version (completed work), excluding duplicates:

```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<VERSION>' AND status = Closed AND resolution != Duplicate" --plain --no-headers
```

For each feature returned from both queries, extract: key, summary, status. Keep the two lists separate — open features go in the main report, closed features go in the "Completed Work" section.

**IMPORTANT**: Features with resolution "Duplicate" are retired consolidations — they were replaced by unified features and must NOT appear anywhere in the report.

### Step 2: Query Epics per Feature

For each feature from Step 1, fetch its child epics:

```bash
jira issue list --project OSAC -q "type = Epic AND parent = <FEATURE-KEY>" --plain --no-headers
```

For each child epic, extract: key, summary, status.

**Note:** Fix versions are tracked at the Feature level only in this project. Do NOT query or report fix versions on epics.

### Step 3: Group by Use Case

Group features into use-case categories. Use the **component** field from Jira as the primary grouping key. If a feature has no component, fall back to keyword matching on the summary.

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
- Contains "VMaaS" or "VM " → VMaaS
- Contains "Network" or "Subnet" or "VPN" or "Netris" or "CUDN" or "MetalLB" or "VLAN" or "SecurityGroup" or "PublicIP" → Networking
- Contains "Enclave" or "GoRI" or "Plugin" → Enclave & Deployment
- Contains "Helm" or "Install" or "Packaging" or "Productization" → Infrastructure
- Contains "Storage" or "VAST" or "Tier" → Storage
- Contains "Tenant" or "Org" or "Auth" or "RBAC" or "Catalog" → Core
- Contains "Metering" or "Quota" or "Billing" → Metering & Quota
- Otherwise → Uncategorized

### Step 3.5: Analyze Service Offering Readiness

For each of the three core service offerings (CaaS, VMaaS, BMaaS), analyze readiness across five dimensions using data already gathered in Steps 1–3. For each cell, determine a status and write a one-line summary.

**Status indicators:**
- **Done** — capability is delivered (feature/epic closed, DoD items checked)
- **In Progress** — work underway, note what remains
- **Gap** — no feature/epic covers this, or a dependency blocks it
- **N/A** — not applicable for this service in this version

**Dimensions to evaluate:**

1. **API** — Does the service have a core API feature? Check its DoD items (which are checked vs unchecked). Is there CLI support? Are API paths correct?

2. **Multi-Tenancy** — Does the service enforce tenant isolation? Check if the Core feature (tenant onboarding, RBAC, orgs) covers this service. Look for tenant-scoping annotations, namespace isolation, or RBAC references in the service's feature description.

3. **Networking** — Look for a "{Service} Networking Integration" feature or epic. Check its DoD. Determine if networking is **API-driven** (service consumes the OSAC Networking API for VirtualNetwork/Subnet/SecurityGroup/PublicIP) or **backend-coupled** (networking handled by a specific backend like Carbide/Netris without going through the generic API). Note whether the Networking API enhancement proposal lists this service as a current or future integration.

4. **Storage** — Look for storage-related epics under or linked to the service feature (e.g., "VAST for CaaS", "VMaaS Tenant Storage Setup", "StorageBackend CR"). Check their status.

5. **UI** — Look for UI-tagged epics or features related to the service (labels OSAC-UI/OSAC-UX, component UI, or summary containing "UI"/"UX"/"console"/"wizard"). Check if any UI work has started.

### Step 4: Generate Report

The report has four parts: **service offering matrix**, **executive summary**, **detailed breakdown** (optional), and **completed work**. The matrix leads so readers see cross-cutting readiness first, then drill into use-case details.

The **detailed breakdown** (Part 3) is optional. Include it only when the user passes `--detailed` or explicitly asks for epic-level detail. By default, omit Part 3 entirely.

Output the report in this format:

```markdown
# OSAC Version <VERSION> — Milestone Report

Generated: <current date>

---

# Part 1: Service Offering Matrix

## Offering Readiness

| Dimension | CaaS — Cluster Provisioning | VMaaS — VM Management | BMaaS — Bare Metal Lifecycle |
|-----------|----------------------------|----------------------|------------------------------|
| **API** | <status> — <one-line summary> | <status> — <one-line summary> | <status> — <one-line summary> |
| **Multi-Tenancy** | <status> — <one-line summary> | <status> — <one-line summary> | <status> — <one-line summary> |
| **Networking** | <status> — <one-line summary> | <status> — <one-line summary> | <status> — <one-line summary> |
| **Storage** | <status> — <one-line summary> | <status> — <one-line summary> | <status> — <one-line summary> |
| **UI** | <status> — <one-line summary> | <status> — <one-line summary> | <status> — <one-line summary> |

<Fill each cell using the analysis from Step 3.5. Use bold for the status indicator: **Done**, **In Progress**, **Gap**, **N/A**. Keep summaries to one line — e.g., "**In Progress** — ClusterOrder doesn't yet consume Networking API; isolation is backend-coupled (Carbide/Netris)">

## Key Integrations & Dependencies

<List cross-cutting dependencies that affect multiple services. Examples:>
- Networking API (OSAC-XXXX) is a shared dependency for all three service networking integrations
- Core multi-tenancy feature (OSAC-XXXX) provides RBAC/tenant onboarding used by all services
- Storage backend framework (OSAC-XXXX) is a prerequisite for per-service storage integration
<Only list dependencies that actually exist in the data. Don't invent them.>

## Conclusions

<Synthesize the matrix into actionable observations. Cover:>
1. **Maturity ranking** — which service is most/least complete and why
2. **Critical path** — what blocks the most progress across services
3. **Highest-risk gaps** — dimensions where multiple services show Gap status
4. **Recommendations** — what should be prioritized, deferred, or decomposed

<Write 4–6 bullet points. Be specific — reference feature keys. This is the "so what" section.>

---

# Part 2: Executive Summary

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

<Repeat for each use case category. For each feature, read its description and extract the key capabilities as bullet points. If the description has a "Use Cases" or "Feature Goal" section, use that. If the description is empty or a placeholder template, derive capabilities from the feature title and its child epic summaries.>

## Gaps & Observations

<Analyze and list:>
- **Features with multiple fix versions** — features should map to exactly one fix version. If a feature has more than one, it should be split or scoped to a single version. Check with: `jira issue list --project OSAC -q "type = Feature AND fixVersion is not EMPTY" --plain --no-headers` then for each, check if it has more than one fix version via `--raw` and flag any with multiple.
- Features with NO child epics (no work breakdown)
- Features where all child epics are Closed but the feature is still open (should it be closed?)
- Use case categories with no features (if any expected ones are missing)
- Features with placeholder/template descriptions that need to be filled in

---

# Part 3: Detailed Breakdown (only if `--detailed` flag or user requested)


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

# Part 4: Completed Work (always included)

Features in this version that are already closed. Grouped by use case category using the same grouping rules.

## <Use Case Category>

| Feature | Summary |
|---------|---------|
| OSAC-XXXX | <Title> |
| OSAC-YYYY | <Title> |

<Repeat for each use case category that has closed features. If no closed features exist, omit Part 4 entirely.>
```

### Step 5: Present to User

Output the full report as markdown. Do not write it to a file unless the user asks.

After presenting the report, ask:
- "Would you like me to save this report to a file?"
- "Any use case categories that should be adjusted?"

## Parsing Jira Raw Output

Jira's `--raw` flag returns JSON with ADF (Atlassian Document Format) for the `description` field — it's a nested JSON object, **not** a plain string. Use this helper to extract feature details:

```bash
jira issue view <KEY> --raw 2>/dev/null | python3 -c "
import sys, json

def adf_to_text(node):
    \"\"\"Recursively extract plain text from an ADF document.\"\"\"
    if node is None:
        return ''
    if isinstance(node, str):
        return node
    if isinstance(node, dict):
        if node.get('type') == 'text':
            return node.get('text', '')
        parts = []
        for child in node.get('content', []):
            parts.append(adf_to_text(child))
        return ' '.join(parts)
    if isinstance(node, list):
        return ' '.join(adf_to_text(item) for item in node)
    return ''

data = json.load(sys.stdin)
f = data.get('fields', {})
comps = [c.get('name','') for c in f.get('components', [])]
versions = [v.get('name','') for v in f.get('fixVersions', [])]
desc_raw = f.get('description')
desc = adf_to_text(desc_raw)[:500] if desc_raw else ''
print('COMPONENTS:', ','.join(comps) if comps else 'None')
print('FIX_VERSIONS:', ','.join(versions))
print('DESC:', desc)
"
```

**Key points:**
- Always use `adf_to_text()` on the `description` field — never slice it directly
- The `components` and `fixVersions` fields are arrays of objects, extract the `name` key
- Batch these queries (max 5 in parallel) to avoid rate limiting

## Tips

- **Rate limiting**: If there are many features, batch the epic queries. Don't fire more than 5 jira commands in parallel.
- **Large features**: For features with 10+ epics (like Packaging), show all epics but note the count.
- **Closed features**: The query excludes Closed features. If the user wants to include completed work, re-run with `status != Cancelled` or no status filter.
- **Multiple versions**: The user can run this for different versions to compare scope (e.g., `/version-report 0.1` vs `/version-report 0.2`).
