---
name: release-plan
description: "Generate a forward-looking release plan for an OSAC version — shows what the platform will deliver, cumulative capabilities across all prior versions, customer requirements coverage, and use-case cards. Use when asked for a release plan, developer preview plan, or version roadmap."
---

# Release Plan

Generate a forward-looking HTML report (and companion markdown) showing what an OSAC version will deliver. Shows cumulative capabilities across ALL prior versions (0.1, 0.2, +0.3 style), customer requirements coverage, and use-case breakdowns with customer driver tags.

**CRITICAL**: Use `jira` as the jira binary (must be on PATH). All `list` commands use `--plain --no-headers`. Do NOT use `--no-input` on `list` or `view`.

**CRITICAL — FILENAMES**: Always include date AND time in output filenames. Get the current time using `date +%Y-%m-%d-%H%M` and use it in both filenames. Never use date-only filenames — this causes overwrites on multiple runs per day. Example: `OSAC-0.3-release-plan-2026-08-19-1435.md` and `OSAC-0.3-release-plan-2026-08-19-1435.html`.

**IMPORTANT**: Only features with resolution "Done" appear as completed in prior versions. Fix versions are tracked at the **Feature level only** (not epics). Do not query epics for fix versions.

## Input

Accept two arguments:
1. **Target version** (required) — the version to plan (e.g., `0.3`)
2. **Prior version** (optional) — the immediately preceding version (defaults to one step back, e.g., `0.2` for `0.3`)

The skill automatically queries ALL versions before the target to build the full cumulative history.

## Workflow

### Step 1: Query Features for Target and All Prior Versions

Fetch features for the **target version** (open + closed):
```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<TARGET>' AND status != Closed" --plain --no-headers
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<TARGET>' AND status = Closed AND resolution = Done" --plain --no-headers
```

Fetch features for **each prior version** using different rules depending on how far back:

**N-1 (the immediately preceding version)** — include ALL features regardless of status (Closed, In Progress, Review, New). These are expected to land before the target version ships:
```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<N-1>'" --plain --no-headers
```

**N-2 and older** — include only completed features (Closed + resolution = Done). These versions have already shipped; incomplete items never landed:
```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<N-2_OR_OLDER>' AND status = Closed AND resolution = Done" --plain --no-headers
```

For example, for a 0.3 report: query 0.2 (N-1) with ALL statuses, query 0.1 (N-2) with Closed+Done only.
For a 0.4 report: query 0.3 (N-1) with ALL statuses, query 0.1 and 0.2 (N-2 and older) with Closed+Done only.

For each feature in ALL versions, fetch full details:
```bash
jira issue view <FEATURE-KEY> --plain
```

Extract per feature: key, summary, status, component(s), labels, description.

**Step 1.5 — Enrich from child epics**: For ALL features across ALL versions (target and prior), also fetch child epics to surface capabilities that the feature description may not enumerate:
```bash
jira issue list --project OSAC -q "type = Epic AND parent = <FEATURE-KEY>" --plain --no-headers
```

From the child epics, extract **only epics that represent user-facing capabilities** — new APIs, new UI surfaces, new integrations, new service behaviors. **Skip epics that are purely internal work**: E2E tests, demo recordings, CI/CD pipelines, performance benchmarks, documentation, bootstrap/planning epics (those titled "Bootstrap", "PRD", "Design", "UX Design", "UI Design"). These provide no external value and should not appear in the report.

Pay special attention to:
- **Epics with a different component than the parent feature** — e.g. UI epics (component=UI, labels=OSAC-UI) under a Core feature reveal a UI dimension the feature description may not mention. Surface these as a separate capability bullet in the matrix under the appropriate dimension (UI row for UI epics, API row for API epics, etc.). This applies to ALL versions — if OSAC-2992 (a 0.2 Core feature) has 6 UI child epics covering tenant management UI, those must appear in the **0.2 row of the UI dimension** of the matrix.
- **Epics with no fixVersion inherit the parent feature's version for matrix placement**. In OSAC, fixVersions are set on Features, not Epics. When an epic has no fixVersion, use its parent feature's fixVersion to determine where it belongs in the cumulative matrix. Example: OSAC-3344–3349 are UI epics with no fixVersion, but their parent OSAC-2992 has `fixVersion=0.2` — so these UI epics belong in the **0.2 row** of the UI dimension.
- **Epics that reveal specific sub-capabilities** — e.g. "Vault Configuration & Tenant NS Lifecycle", "M360 Adapter", "MaaS Inference Metering" are specific capabilities worth naming rather than just "Secret Management" or "Metering".

**Customer label detection** — auto-discover all customer labels dynamically:
- Any label matching `customer:*` → extract the customer name after the colon (e.g. `customer:moc` → MOC, `customer:telenor` → Telenor, `customer:jio` → Jio). Capitalize the name for display.
- `rfp-telefonica-gigafactory` → Telefónica (legacy label, maps to same customer as `customer:telefonica`)
- `NCP` → NCP (NVIDIA Cloud Partners)
- `AIGRID` or `ai-grid-60d-plan` → AI Grid

Do not hard-code specific customer names — discover them from the labels on each feature. This ensures new customers (e.g. `customer:nebius`, `customer:vz`) are automatically included without skill changes.

### Step 2: Query Customer Requirements

**NCP requirements** (OSAC-991):
```bash
jira issue view OSAC-991 --plain
```
Extract the linked issues and map each NCP requirement to its OSAC feature and which version covers it.

Then also search by label as a fallback to catch any NCP-related features not linked back to OSAC-991, but **only for the target version**:
```bash
jira issue list --project OSAC -q "labels = 'NCP' AND type = Feature AND fixVersion = '<TARGET>'" --plain --no-headers
```
Merge the two result sets — label-based results may surface features (like breakfix/BFX02 tickets) that were created after OSAC-991 and not explicitly linked back. Do NOT include NCP-labeled features from other versions or with fixVersion=Backlog.

**All customers with `customer:*` labels** — query each customer dynamically. First discover which customer labels exist on features in scope:
```bash
jira issue list --project OSAC -q "type = Feature AND labels is not EMPTY AND (fixVersion = '<TARGET>' OR fixVersion = '<N-1>')" --plain --no-headers
```
Then for each unique `customer:*` label found, query that customer's full feature list:
```bash
jira issue list --project OSAC -q "labels = 'customer:<NAME>' AND type = Feature" --plain --no-headers
```

**Telefónica RFP** (legacy label — always include):
```bash
jira issue list --project OSAC -q "labels = 'rfp-telefonica-gigafactory' AND type = Feature" --plain --no-headers
```

### Step 3: Group Features by Use Case

Use the **component** field as the primary grouping key:

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
| Metering, Billing and Quota | Metering & Quota |
| UI | UI |
| MaaS | MaaS — Model as a Service |

Keyword fallback applies if no component is set (scan summary).

**Spikes**: Any feature whose title starts with "Spike:" or "[spike]" is an investigation, not a delivered capability. **Do not include spikes in the Service Offering Matrix.** They may appear in the Use Case Cards and Feature Inventory with a clear "Spike" label, but never as a capability in a matrix cell.

**Component takes precedence over summary keywords**: If a feature has a component set, always use the component for grouping — never override with summary-based inference. Example: a feature titled "Key Management Service" with `component=Core` belongs in "Core — Multi-Tenancy & Platform", not Storage, regardless of the word "storage" being related to its function.

### Step 4: Build the Cumulative Capability View

For each use case category, organize features across ALL versions showing the full history:

**Version labels to use:**
- `0.1` — shipped in 0.1
- `0.2` — shipped in 0.2
- `0.3` — shipped/planned in 0.3
- `+<TARGET>` — what this version adds (the focus of the report)

Example for a 0.3 report:
```
CaaS API:
  0.1: Cluster provisioning via HyperShift + Metal3
  0.2: Managed cluster versions, cluster upgrade, CaaS networking (Netris/VLAN)
  +0.3: Scale CLI, cluster status report, VM worker nodes, upgrade progress
```

Example for a 0.4 report:
```
Core Security:
  0.1: Keycloak auth, OPA RBAC
  0.2: Secret Management foundation, Vault integration
  0.3: Per-Project KMS, cross-cluster auth and TLS trust
  +0.4: Audit Log API, Breakfix Event API (NCP BFX02)
```

### Step 5: Build the Service Offering Matrix

For each of the three core services (CaaS, VMaaS, BMaaS), evaluate five dimensions across all versions:

1. **API** — Core API capabilities
2. **Multi-Tenancy** — Tenant isolation
3. **Networking** — Networking capabilities
4. **Storage** — Storage capabilities
5. **UI** — UI surfaces

Each cell shows cumulative layers with version labels. Use human-readable capability descriptions only — **never put Jira keys (e.g., OSAC-1436) in the matrix cells**. Extract a concise description from the feature title or description.

The matrix has **4 service columns**: CaaS, VMaaS, BMaaS, MaaS. Include MaaS even if it only has content in one or two versions.

```
0.1: <base capability description>
0.2: + <added capability description>
+0.3: + <new capability description>
```

### Step 6: Generate Both Markdown and HTML Reports

#### Markdown

Save to: `OSAC-<VERSION>-release-plan-<YYYY-MM-DD-HHMM>.md`

Include generation timestamp in the report header: `Generated: <YYYY-MM-DD HH:MM>` (use current date and time).

Structure:
```markdown
# OSAC <VERSION> — Release Plan
Generated: <date>

## Release Vision
<one-paragraph summary>

## Service Offering Matrix
...

## Use Case Cards
...

## Customer Requirements Coverage
...

## Cumulative Capability Progression
### <Use Case>
| Version | Capabilities |
|---------|-------------|
| 0.1 | ... |
| 0.2 | ... |
| +<TARGET> | ... |

## Feature Inventory
...

## Notes & Action Items
...
```

#### HTML

Save to: `OSAC-<VERSION>-release-plan-<YYYY-MM-DD-HHMM>.html`

Include generation timestamp in the HTML subtitle bar: `Generated: <YYYY-MM-DD HH:MM>`.

**Use the following CSS verbatim in the `<style>` tag** — do not invent your own styling:

```css
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: "Red Hat Display", "RedHatDisplay", Helvetica, Arial, sans-serif; font-size: 14px; color: #151515; background: #f5f5f5; line-height: 1.6; }
    a { color: #06c; text-decoration: none; }
    a:hover { text-decoration: underline; }
    h1 { font-size: 2rem; font-weight: 700; }
    h2 { font-size: 1.4rem; font-weight: 600; margin-bottom: 0.75rem; }
    h3 { font-size: 1.1rem; font-weight: 600; margin-bottom: 0.5rem; }
    .page { max-width: 1200px; margin: 0 auto; padding: 2rem 1.5rem; }
    .section { margin-bottom: 3rem; }
    .header { background: #151515; color: #fff; padding: 2.5rem 2rem; margin-bottom: 2rem; border-bottom: 4px solid #EE0000; }
    .header h1 { color: #fff; }
    .header .subtitle { color: #c0c0c0; font-size: 1rem; margin-top: 0.5rem; }
    .header .meta { color: #888; font-size: 0.85rem; margin-top: 0.75rem; }
    .header .badge { display: inline-block; background: #EE0000; color: #fff; padding: 0.2rem 0.75rem; border-radius: 12px; font-size: 0.8rem; font-weight: 600; margin-top: 0.5rem; }
    .metrics { display: flex; gap: 1rem; flex-wrap: wrap; margin-bottom: 2rem; }
    .metric-card { background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 1.25rem 1.5rem; flex: 1; min-width: 140px; text-align: center; border-top: 4px solid #EE0000; }
    .metric-card .num { font-size: 2.5rem; font-weight: 700; color: #EE0000; }
    .metric-card .label { font-size: 0.8rem; color: #555; margin-top: 0.25rem; text-transform: uppercase; letter-spacing: 0.05em; }
    .section-header { background: #151515; color: #fff; padding: 0.6rem 1rem; border-radius: 6px 6px 0 0; font-weight: 600; font-size: 1rem; margin-bottom: 0; display: flex; align-items: center; gap: 0.5rem; }
    .section-body { background: #fff; border: 1px solid #ddd; border-top: none; border-radius: 0 0 6px 6px; padding: 1.5rem; }
    .delta-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; }
    .delta-col h3 { color: #151515; border-bottom: 2px solid #EE0000; padding-bottom: 0.35rem; margin-bottom: 0.75rem; }
    .delta-col.prior h3 { border-color: #888; }
    .delta-col ul { list-style: none; padding: 0; }
    .delta-col ul li { padding: 0.4rem 0; padding-left: 1.1rem; position: relative; border-bottom: 1px solid #f0f0f0; font-size: 0.9rem; }
    .delta-col ul li::before { content: "▸"; position: absolute; left: 0; color: #888; }
    .delta-col.new ul li::before { content: "★"; color: #EE0000; }
    .matrix-table { width: 100%; border-collapse: collapse; font-size: 0.88rem; }
    .matrix-table th, .matrix-table td { border: 1px solid #ddd; padding: 0.6rem 0.8rem; vertical-align: top; }
    .matrix-table thead th { background: #151515; color: #fff; font-weight: 600; }
    .matrix-table thead th:first-child { background: #333; }
    .matrix-table tbody tr:nth-child(even) td:not(:first-child) { background: #fafafa; }
    .matrix-table td:first-child { background: #f0f0f0; font-weight: 600; color: #151515; white-space: nowrap; }
    .v-badge { display: inline-block; font-size: 0.68rem; font-weight: 700; padding: 0.1rem 0.35rem; border-radius: 3px; margin-right: 0.25rem; vertical-align: middle; white-space: nowrap; }
    .badge-v01 { background: #6c757d; color: #fff; }
    .badge-v02 { background: #0066cc; color: #fff; }
    .badge-v03 { background: #00838f; color: #fff; }
    .badge-target { background: #3d7a00; color: #fff; font-weight: 800; }
    .v02 { background: #e8f4f8; color: #005f8e; border: 1px solid #a0d4ea; }
    .v03 { background: #fff0e0; color: #a05000; border: 1px solid #f0c070; font-weight: 800; }
    .matrix-item { margin-bottom: 0.3rem; font-size: 0.85rem; }
    .card-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1.25rem; }
    .uc-card { background: #fff; border: 1px solid #ddd; border-radius: 8px; border-left: 5px solid #888; padding: 1rem 1.1rem; }
    .uc-card.core     { border-left-color: #EE0000; }
    .uc-card.caas     { border-left-color: #1b6fb8; }
    .uc-card.vmaas    { border-left-color: #3a7d3f; }
    .uc-card.bmaas    { border-left-color: #e07400; }
    .uc-card.storage  { border-left-color: #7b3b9e; }
    .uc-card.network  { border-left-color: #0a8073; }
    .uc-card.metering { border-left-color: #c23c78; }
    .uc-card.infra    { border-left-color: #555; }
    .uc-card.maas     { border-left-color: #a30000; }
    .uc-card.ui       { border-left-color: #2a69b0; }
    .uc-card h3 { font-size: 0.95rem; margin-bottom: 0.6rem; }
    .uc-card ul { list-style: none; padding: 0; }
    .uc-card ul li { font-size: 0.85rem; padding: 0.3rem 0; border-bottom: 1px solid #f0f0f0; display: flex; align-items: flex-start; gap: 0.4rem; }
    .uc-card ul li:last-child { border-bottom: none; }
    .star { color: #EE0000; font-size: 0.9rem; flex-shrink: 0; }
    .prev { color: #888; font-size: 0.9rem; flex-shrink: 0; }
    .tags { display: flex; gap: 0.3rem; flex-wrap: wrap; margin-top: 0.2rem; }
    .tag { display: inline-block; font-size: 0.65rem; font-weight: 700; padding: 0.1rem 0.45rem; border-radius: 10px; text-transform: uppercase; letter-spacing: 0.04em; }
    .tag-ncp      { background: #dde8fb; color: #1a4db0; }
    .tag-tel      { background: #ffe8cc; color: #a05000; }
    .tag-moc      { background: #edddf7; color: #6a1f9e; }
    .tag-telenor  { background: #d1ede9; color: #0a5c52; }
    .tag-aigrid   { background: #fce4e4; color: #a00000; }
    .req-table { width: 100%; border-collapse: collapse; font-size: 0.88rem; margin-bottom: 1.5rem; }
    .req-table th { background: #333; color: #fff; padding: 0.5rem 0.75rem; text-align: left; }
    .req-table td { border: 1px solid #ddd; padding: 0.45rem 0.75rem; vertical-align: top; }
    .req-table tr:nth-child(even) td { background: #fafafa; }
    .status-partial { color: #e07400; font-weight: 600; }
    .status-gap { color: #EE0000; font-weight: 600; }
    .status-done { color: #2a7a2a; font-weight: 600; }
    .version-pill { display: inline-block; font-size: 0.72rem; font-weight: 600; padding: 0.1rem 0.45rem; border-radius: 10px; white-space: nowrap; }
    .vp-01 { background: #f0f0f0; color: #555; }
    .vp-02 { background: #e8f4f8; color: #005f8e; }
    .vp-03 { background: #fff0e0; color: #a05000; }
    .vp-future { background: #f5f5f5; color: #777; }
    .inv-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin-bottom: 1.5rem; }
    .inv-table th { background: #2d2d2d; color: #fff; padding: 0.4rem 0.7rem; text-align: left; }
    .inv-table td { border: 1px solid #e0e0e0; padding: 0.4rem 0.7rem; vertical-align: top; }
    .inv-table tr:nth-child(even) td { background: #fafafa; }
    .jira-key { font-family: monospace; font-size: 0.8rem; color: #555; white-space: nowrap; }
    .jira-key a { color: #1b6fb8; }
    .status-badge { display: inline-block; font-size: 0.68rem; padding: 0.1rem 0.4rem; border-radius: 3px; font-weight: 600; }
    .st-new { background: #e8f4f8; color: #005f8e; }
    .st-inprog { background: #fff8d6; color: #7a6000; }
    .st-review { background: #eaf4e8; color: #2a6e1a; }
    .st-done { background: #d4edda; color: #155724; }
    .callout { border-left: 4px solid #1b6fb8; background: #e8f4f8; padding: 1rem 1.25rem; border-radius: 0 6px 6px 0; margin-bottom: 1rem; }
    .callout.warn { border-color: #e07400; background: #fff8ed; }
    .callout.info { border-color: #0a8073; background: #e6f4f2; }
    .callout h4 { margin-bottom: 0.4rem; font-size: 0.95rem; }
    .callout ul { margin-left: 1.2rem; font-size: 0.88rem; }
    .callout ul li { margin-bottom: 0.25rem; }
    .cumulative-table { width: 100%; border-collapse: collapse; font-size: 0.87rem; margin-bottom: 1.5rem; }
    .cumulative-table th { background: #333; color: #fff; padding: 0.45rem 0.75rem; text-align: left; }
    .cumulative-table td { border: 1px solid #ddd; padding: 0.5rem 0.75rem; vertical-align: top; }
    .cumulative-table tr.target-row td { background: #fffbf0; border-left: 3px solid #3d7a00; }
    .cumulative-table tr.target-row td:first-child { font-weight: 700; color: #3d7a00; }
    .coverage-summary { display: flex; gap: 1rem; flex-wrap: wrap; margin-top: 1rem; }
    .cov-card { background: #fff; border: 1px solid #ddd; border-radius: 6px; padding: 0.75rem 1rem; flex: 1; min-width: 160px; text-align: center; }
    .cov-card .cov-num { font-size: 1.8rem; font-weight: 700; color: #0a8073; }
    .cov-card .cov-label { font-size: 0.78rem; color: #555; }
    .text-muted { color: #777; font-size: 0.82rem; }
    @media print { body { background: #fff; font-size: 11px; } .page { padding: 0.5rem; } .section { page-break-inside: avoid; } .card-grid, .delta-grid { grid-template-columns: 1fr 1fr; } }
```

Use a clean, professional style with:
- Red Hat-inspired color palette (`#EE0000` red accent, `#151515` dark text)
- Color-coded version badges with fixed colors: 0.1=`#6c757d` (gray), 0.2=`#0066cc` (blue), 0.3=`#00838f` (teal), target version=`#3d7a00` (green) with `+` prefix
- **Feature names must be clickable links** to `https://redhat.atlassian.net/browse/<KEY>`
- Cumulative capability table for each use case showing version history
- Color-coded use case cards (Core=red, CaaS=blue, VMaaS=green, BMaaS=orange, Storage=purple, Networking=teal)
- Customer driver badges (NCP=blue, Telefónica=orange, MOC=purple, Telenor=dark blue, AI Grid=red)
- Service offering matrix with layered version labels
- Print-friendly layout
- All CSS self-contained in `<head>`

**Section 1: Release Vision**
- One-paragraph summary of what the version delivers
- Metric cards: total features, use cases, customer drivers, epics

**Section 2: Service Offering Matrix**
- CaaS / VMaaS / BMaaS / MaaS columns, API / Multi-Tenancy / Networking / Storage / UI rows
- Each cell shows layered history with version labels
- **Write capability descriptions only — no Jira keys or ticket numbers in the matrix.** Use the feature description or summary to extract a concise, user-facing capability name (e.g., "Cluster networking via Ansible VLAN" not "OSAC-1436"). Jira keys belong in the Feature Inventory section only.
- If MaaS has no features for a given dimension in any version, use `—` for that cell.

**Section 3: Use Case Cards**
- Color-coded cards per use case
- Each card lists new capabilities in the target version with customer tags
- Feature names are links

**Section 4: Customer Requirements Coverage**
- NCP: all 13 requirements table, which version covers each
- Telefónica RFP: open items with version coverage
- MOC: features grouped by addressed (0.3/0.4) vs backlog
- Telenor: features with `customer:telenor` label by version

**Section 5: Cumulative Capability Progression**
- For each use case: a table showing what was added version by version
- Each row: version label | bullet list of capabilities added in that version
- Feature names are links to Jira: `<a href="https://redhat.atlassian.net/browse/OSAC-XXXX">Feature Title</a>`
- Target version row highlighted (different background, `+VERSION` prefix)
- Omit rows for versions that added nothing to a given use case

**Section 6: Feature Inventory**
- Tables grouped by use case
- Columns: Jira key (as link), Feature title (**plain text, NOT a link**), Customer tags, Status
- The Key column already links to Jira — do NOT repeat the link in the Feature column. Feature title is plain text only.
- **ONLY features queried in Step 1 with `fixVersion = '<TARGET>'`** — this section is a clean list of what this version delivers. Never add features here based on customer label queries (Step 2). If a feature has `fixVersion=0.4` or `fixVersion=Backlog`, it must NOT appear here regardless of its customer labels. OSAC-63 is an example: it has customer labels but fixVersion=0.4, so it belongs only in the NCP/MOC tables in Section 5, never in Section 6.

**Section 7: Notes & Action Items**
- Features needing epic decomposition
- Frozen features, spikes, duplicates
- Deferred items

### Step 7: Open and Present

After saving both files:
1. Print the output paths to the user
2. Suggest opening with: `open OSAC-<VERSION>-release-plan-<DATE>.html`

## Tips

- **Cumulative history**: The key differentiator of this skill. Always show what was built in 0.1, 0.2, etc. before showing what's new. A reader should understand the full journey, not just the delta. **If a prior version has no features in a given use case category, omit that version row entirely** — never write "Foundation maintained" or "No new features" as a row. Only include rows where something was actually delivered.
- **Feature links**: Every feature name in the HTML must be a clickable link to `https://redhat.atlassian.net/browse/<KEY>`. Never display a feature name as plain text.
- **Customer tags**: Check ALL labels on each feature. A feature can have multiple customer tags.
- **Rate limiting**: Batch epic queries using `parent in (...)`. Don't fire more than 5 jira commands in parallel.
- **Shell variable names**: Never use `status` as a bash/zsh variable name — it is a read-only reserved variable in zsh and causes `(eval): read-only variable: status` errors. Use `jira_status`, `issue_status`, or similar instead.
- **macOS bash compatibility**: macOS ships bash 3.2 which does NOT support associative arrays (`declare -A`). Never use associative arrays in shell scripts. Use Python for any data aggregation, grouping, or key-value mapping instead — e.g. `jira issue list ... | python3 -c "..."`. All complex data processing should be done in Python, not bash.
- **No M1/M2 granularity**: Treat 0.2-M1 and 0.2-M2 as part of 0.2. Query `fixVersion = '0.2'` and treat all 0.2 features together.
- **Component-based grouping**: Use component field, not Team field, for grouping (Team may not be set on all features).
- **N-1 vs N-2+ distinction**: For the immediately preceding version (N-1), include ALL features regardless of status — they are expected to ship before the target version. For N-2 and older, include only Closed+Done features. This ensures in-flight work like a storage framework being built in 0.2 appears correctly when generating a 0.3 report.
- **Target version scope**: Only features where `fixVersion = '<TARGET>'` belong in the "New in N" sections. Never include features from prior versions in the target version's use case cards, even if they are still In Progress. Those are prior version items regardless of their current status.
