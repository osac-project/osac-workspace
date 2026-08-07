---
name: release-plan
description: "Generate a forward-looking release plan for an OSAC version — shows what the platform will deliver, cumulative capabilities vs prior version, customer requirements coverage, and use-case cards. Use when asked for a release plan, developer preview plan, or version roadmap."
---

# Release Plan

Generate a forward-looking HTML report showing what an OSAC version will deliver, framed as a target plan rather than a progress tracker. Shows cumulative capabilities (prior version + new), customer requirements coverage, and use-case breakdowns with customer driver tags.

**CRITICAL**: Use `jira` as the jira binary (must be on PATH). All `list` commands use `--plain --no-headers`. Do NOT use `--no-input` on `list` or `view`.

**IMPORTANT**: Only features with resolution "Done" appear as completed. Features resolved as "Duplicate" or other non-Done resolutions must NOT appear anywhere.

## Input

Accept two arguments:
1. **Target version** (required) — the version to plan (e.g., `0.3`)
2. **Prior version** (optional) — the version it builds on (defaults to the version immediately before, e.g., `0.2`)

## Workflow

### Step 1: Query Features for Both Versions

Fetch features for the **target version** (open + closed):

```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<TARGET>' AND status != Closed" --plain --no-headers
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<TARGET>' AND status = Closed AND resolution = Done" --plain --no-headers
```

Fetch features for the **prior version** (to build the "what 0.X already delivers" column):

```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<PRIOR>'" --plain --no-headers
```

For each feature in the target version, fetch details:

```bash
jira issue view <FEATURE-KEY> --plain
```

Extract: key, summary, status, component(s), description, labels. Note any customer-facing labels:
- `rfp-telefonica-gigafactory` → Telefónica
- `customer:moc` → MOC
- `customer:telefonica` → Telefónica
- `NCP` → NCP
- `AIGRID` or `ai-grid-60d-plan` → AI Grid

Then fetch child epics in batches:

```bash
jira issue list --project OSAC -q "type = Epic AND parent in (<KEY-1>, <KEY-2>, ...)" --plain --no-headers
```

### Step 2: Query Customer Requirements

Check coverage against known customer requirement trackers:

**NCP requirements** (OSAC-991):
```bash
jira issue view OSAC-991 --plain
```
Extract the linked issues and their statuses. Map each NCP requirement to its OSAC feature and determine which version covers it.

**Telefónica RFP**:
```bash
jira issue list --project OSAC -q "labels = 'rfp-telefonica-gigafactory' AND type = Feature" --plain --no-headers
```

**MOC**:
```bash
jira issue list --project OSAC -q "labels = 'customer:moc' AND type IN (Feature, Epic)" --plain --no-headers
```

### Step 3: Group by Use Case

Use the same component-based grouping as the milestone-scope skill:

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

Keyword fallback applies if no component is set (scan summary for CaaS, VM, Network, etc.).

### Step 4: Build the "What's New vs Prior" Delta

For each use case category, compare:
- **Prior version features** → these form the "Foundation" column
- **Target version features** → these form the "New in 0.X" column

Summarize each as a concise capability bullet (not just the Jira title — extract the user-facing capability from the description's "Feature Goal" or "Use Cases" section).

### Step 5: Build the Service Offering Matrix

For each of the three core services (CaaS, VMaaS, BMaaS), evaluate five dimensions:

1. **API** — What API capabilities exist (cumulative)?
2. **Multi-Tenancy** — How is tenant isolation handled?
3. **Networking** — What networking capabilities are available?
4. **Storage** — What storage capabilities are available?
5. **UI** — What UI surfaces exist?

For each cell, show:
- `0.X` label for capabilities from the prior version (carried forward)
- `+0.Y` label for new capabilities in the target version
- Use descriptive text, not status indicators — this is aspirational, not tracking

### Step 6: Generate HTML Report

Output a styled HTML report with these sections:

#### Section 1: Release Vision
- One-paragraph summary of what the version delivers
- Metric cards: total features, use cases, customer drivers, epics decomposed

#### Section 2: What's New vs Prior Version
- Two-column layout: "Prior Delivers (Foundation)" vs "Target Adds (New)"
- Bullet points of capabilities, not Jira keys

#### Section 3: Target Service Offering Matrix
- Table with CaaS / VMaaS / BMaaS columns
- Rows: API, Multi-Tenancy, Networking, Storage, UI
- Each cell shows cumulative capabilities with prior/new labels

#### Section 4: Use Case Cards
- Card grid (2 columns) with color-coded borders per use case
- Each card lists capabilities with customer driver tags (NCP, Telefónica, MOC, AI Grid)
- New capabilities marked with a star icon

#### Section 5: Customer Requirements Coverage
- NCP table: all 13 requirements with which version covers each
- Telefónica RFP table: open items with version coverage
- Summary callout showing coverage ratios

#### Section 6: Feature Inventory
- Tables grouped by use case, showing: Jira key, feature name, customer tags

#### Section 7: Notes & Action Items
- Callout boxes for:
  - Items to review (frozen features, spikes, duplicates)
  - Features needing decomposition (no child epics)
  - Features with placeholder descriptions
  - What's deferred to the next version

### HTML Styling

Use a clean, professional style with:
- Red Hat-inspired color palette (red #EE0000 accent, dark #151515 text)
- Color-coded use case cards (Core=red, CaaS=blue, VMaaS=green, BMaaS=orange, Storage=purple, Networking=teal)
- Customer driver tags as colored badges (NCP=blue, Telefónica=orange, MOC=purple, AI Grid=red)
- Metric cards with large numbers
- Print-friendly layout with page breaks at section headers
- Responsive grid layout for cards

### Step 7: Save and Present

Save the HTML file as `OSAC-<VERSION>-release-plan.html` in the workspace root.

Ask the user:
- "Would you like me to open it in the browser?"
- "Any use cases or customer mappings to adjust?"

## Tips

- **Forward-looking framing**: Never say "Gap" or show red status indicators. This is a plan, not a progress tracker. Everything is aspirational — describe what will be delivered, not what's missing.
- **Cumulative view**: Always show what the prior version already delivers alongside what's new. The reader should understand the full platform capability, not just the delta.
- **Customer drivers matter**: Tag features with their customer motivation. This helps prioritization decisions.
- **Prior version context**: The prior version's features provide the "foundation" context. Don't just list Jira titles — summarize the user-facing capabilities.
- **Rate limiting**: Batch epic queries using `parent in (...)`. Don't fire more than 5 jira commands in parallel.
- **Description extraction**: For capability bullets, prefer the feature description's "Feature Goal" or first paragraph over the Jira title. Fall back to the title if the description is empty.
