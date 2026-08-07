---
name: osac-feature
description: Create Feature issues in the OSAC Jira project. Use when the user wants to create a Feature, enhancement, or new capability request for OSAC.
metadata:
  version: "0.2.0"
---

# OSAC Feature Creation

Create Feature issues in the OSAC Jira project using jira-cli, then create a
bootstrap epic with documentation work-gate tasks for the AI-assisted SDLC.

Requires **bash or zsh** on macOS or Linux (same as jira-cli usage). Use
portable constructs only — macOS `/bin/bash` is 3.2 (no `mapfile`).

## When to Use

- User asks to create a Feature, enhancement, or new capability request for OSAC
- User wants to track a new feature idea in Jira
- User provides feature requirements that should be formalized as a Jira issue

## Gather Inputs

Collect from conversation context. Ask only if truly ambiguous — **except**
for **Team**, **Requires UI work**, and **Fix version**, which must always
be asked explicitly (never inferred from the description or summary).

| Input | Required | Default |
|-------|----------|---------|
| Feature summary | Yes | From conversation context |
| Description | Yes | From conversation context |
| Component | Yes | Infer from context: VMaaS, CaaS, BMaaS, Core, Storage, Connectivity&Fabric, UI, Infrastructure, Enclave |
| Team | **Yes** | Ask user to pick from the known OSAC teams — see [bash-patterns.md](references/bash-patterns.md)'s `list_team_suggestions` |
| Customer | No | If the feature is driven by a specific customer requirement, note the customer name |
| Requires UI work | **Yes** | Ask: "Does this feature require UI work?" |
| Fix version | **Yes** | Propose highest unreleased milestone from Jira (exclude `0.0`); user accepts, picks another, or chooses backlog |
| Assignee | No | Unassigned — only assign if user specifies |

**Note:** Features are never *children* of epics. After creation, a bootstrap
epic is created as a *child* of the Feature to track documentation gates.

**Fix version convention:**

| Issue type | fixVersion | Labels | Notes |
|------------|------------|--------|-------|
| Feature | Yes (confirm gate; source of truth) | (optional) `osac-ux`, `osac-ui`, `customer`, … | User chooses version or backlog |
| Bootstrap epic | Copied from Feature when set | `bootstrap` | Never independently chosen |
| Gate tasks | No | `osac-ux` / `osac-ui` on UX/UI tasks only | PRD and Design have no labels |

The Feature is the single source of truth for `/milestone-scope` reporting.
Bootstrap epics mirror the Feature's fix version after parent linkage is verified.

## Customer Labeling

When a feature is driven by a customer requirement, add two labels:
- `customer` — generic label for filtering all customer-driven features (`project = OSAC AND labels = customer`)
- `customer:<name>` — specific customer label (e.g., `customer:jio`, `customer:hitachi`) for per-customer filtering

Add both labels at creation time using `--label customer --label "customer:<name>"`.

## Validate and Normalize Inputs

Before any Jira operation:

### Feature summary

Reject (ask user to revise) if the summary contains:
- Double quotes (`"`) or single quotes (`'`)
- Backslashes (`\`)
- Parentheses (`(` or `)`)
- Shell/JQL metacharacters: `$`, backticks, `&`, `|`
- Newlines or control characters
- Leading/trailing whitespace only
- More than 243 characters — Jira's 255-char summary limit minus the longest
  gate prefix (`UX Design - ` / `UI Design - `, 12 chars), so every bootstrap
  gate task summary (`<gate> - ${FEATURE_SUMMARY}`) stays within the limit too

Summaries are embedded in exact-match JQL (`summary = "..."`) and shell `-q`
strings; these characters break parsing or expansion. Summaries must be a
single safe line (hyphens, colons, and commas are fine).

Store the validated value in `FEATURE_SUMMARY`.

### Component

Infer from conversation context. Valid values: VMaaS, CaaS, BMaaS, Core,
Storage, Connectivity&Fabric, UI, Infrastructure, Enclave. Ask if ambiguous.
Store in `COMPONENT`.

### Team

Ask explicitly — do not infer from the description or summary.

1. Run `list_team_suggestions` (see [bash-patterns.md](references/bash-patterns.md)) to list known teams.
2. Ask: "Which team owns this Feature? Options: <team list>"
3. Normalize the answer via `validate_team` and store in `TEAM`:
   - A valid team name from the suggestion list (case-insensitive match, canonicalized to the list's spelling)
   - `invalid` for anything else, including empty input
4. On `invalid`, ask again — Team has no default or skip option; every Feature must have one.
5. If the desired team isn't listed, tell the user this skill's team list needs updating (`TEAM_NAME_TO_ID` in [bash-patterns.md](references/bash-patterns.md)) and ask a Jira admin for the team's ID.

Only the Feature **chooses** Team at the confirm gate. The bootstrap epic and
PRD/Design gate tasks receive a **copy** — see the propagation rules in
[bash-patterns.md](references/bash-patterns.md) and
[bootstrap-tasks.md](references/bootstrap-tasks.md). UX Design and UI Design
gate tasks always get `OSAC-UI` regardless of the Feature's choice.

### Customer (optional)

If the user names a customer, normalize to a lowercase slug for the label
(e.g., `Jio` → `jio`, `Hitachi` → `hitachi`) and store in `CUSTOMER`. Leave
unset when not customer-driven.

### Requires UI work

Ask: "Does this feature require UI work?" — this gates **both** the UX Design
and UI Design bootstrap tasks (and `osac-ux` / `osac-ui` labels). There is no
separate UX-only prompt; UI work = yes implies the full UX → UI doc track per
[OSAC-2304](https://redhat.atlassian.net/browse/OSAC-2304).

Normalize the user's answer to `REQUIRES_UI=yes` or `REQUIRES_UI=no`:
- **yes:** `yes`, `y`, `true` (case-insensitive)
- **no:** `no`, `n`, `false` (case-insensitive)

If ambiguous, ask again — do not infer from the description.

### Fix version

Ask explicitly — do not infer from summary text (e.g. `(0.2)` in the title).

1. Run `list_fix_version_suggestions` (see [bash-patterns.md](references/bash-patterns.md)) to fetch
   unreleased OSAC milestones, excluding `0.0` and the literal `Backlog`
   release (collides with the `backlog` sentinel below — see step 3).
2. Propose the highest version as default, e.g. "Proposed fix version: **0.3**.
   Accept, specify another milestone, or choose **backlog** (no fix version)?"
3. Normalize the user's answer via `validate_fix_version` and store in `FIX_VERSION`:
   - A valid release name from the suggestion list
   - `backlog` when the user explicitly says backlog, none, or skip
4. On `invalid` (including empty input), ask again — do not default to backlog.
5. On `lookup_failed` (Jira release list error), stop and report — do not treat as invalid input.

Only the Feature **chooses** `fixVersion` at the confirm gate. The bootstrap epic
receives a **copy** when the Feature version is set (not backlog). Gate tasks
never receive fix version.

### Assignee (optional)

If assignee is specified, confirm with the user before create. Use Jira
username, email, or display name (same formats `jira issue assign` accepts).
Compare against `jira me` if helpful — there is no separate user-lookup command.

On assign failure, capture stderr, report the error, and continue bootstrap
(Feature exists; user can assign manually with `jira issue assign "$KEY" …`).

## Confirm Before Creating

**Do not call `jira issue create` until the user confirms.**

Present a summary and wait for explicit approval:

```text
Ready to create in Jira:

  Feature:     <FEATURE_SUMMARY>
  Component:   <COMPONENT>
  Team:        <TEAM>
  Customer:    <name or none>
  UI work:     yes | no
  Fix version: <version> | backlog (unset)
  Labels:      [osac-ux, osac-ui if UI work][, customer, customer:<name>] | none
  Assignee:    <name or unassigned>

  Bootstrap epic:  <FEATURE_SUMMARY> - Bootstrap
    Label: bootstrap; fix version copied from Feature (when not backlog); team copied from Feature
  Bootstrap tasks: PRD - <FEATURE_SUMMARY>, Design - <FEATURE_SUMMARY>
    [, UX Design - <FEATURE_SUMMARY>, UI Design - <FEATURE_SUMMARY> if UI work]

  (Gate tasks do not receive fix version. PRD/Design tasks get <TEAM>;
   UX/UI Design tasks always get OSAC-UI regardless of <TEAM>.)

Proceed? (yes/no)
```

Only continue when the user answers yes.

## Jira create workflow

Execute in order. **Read each reference file before its step** — do not skip.

| Step | Read first | Action |
|------|------------|--------|
| 1 | [bash-patterns.md](references/bash-patterns.md) | Source helpers and safe-create temps |
| 2 | [feature-body-template.md](references/feature-body-template.md) | Create Feature, set fix version and team, assign if requested |
| 3 | [bootstrap-epic.md](references/bootstrap-epic.md) | Create or reuse bootstrap epic; verify parent linkage |
| 4 | [bootstrap-tasks.md](references/bootstrap-tasks.md) | Create PRD, Design[, UX/UI Design] gate tasks; apply team |

## Error Handling

| Failure | Action |
|---------|--------|
| Invalid summary (JQL/shell unsafe chars, >243 chars) | Reject before confirm; ask user to revise |
| User declines confirm gate | Stop; no Jira creates |
| Duplicate Feature found | Stop; report existing key(s); ask user whether to reuse or proceed anyway |
| Empty `KEY` after Feature create | Stop; report `$ERR` and error JSON; do not bootstrap |
| Fix version edit failed after Feature create | Non-fatal; report manual `jira issue edit --fix-version …`; continue bootstrap |
| Team field edit failed after Feature/epic/task create | Non-fatal; report manual Jira UI edit; continue bootstrap |
| Bootstrap metadata failed (label, fix version, or team copy) | Non-fatal; report manual edit commands; continue gate tasks |
| Empty `EPIC_KEY` after epic create | Stop; report Feature key and errors; do not create tasks |
| Epic parent edit slow | Wait up to 3 minutes; do not kill and retry |
| Epic parent ≠ Feature after 30s re-check | Stop; report keys + manual `jira issue edit -P … </dev/null>`; do not create tasks |
| Orphan epic reused | Run parent edit + verify before tasks |
| Empty task key mid-way | Stop; report Feature, epic, completed tasks, and errors |
| Duplicate epic/tasks found | Reuse existing keys; do not create again |
| Malformed Jira key after create | Stop; report `$ERR` and error JSON; do not proceed |
| Partial bootstrap (orphan Feature/epic) | Report all created keys; user may close/delete manually in Jira |

Before create, search Jira for an existing Feature with the same summary —
see [feature-body-template.md](references/feature-body-template.md)'s
Duplicate check. If a slow create appears hung, wait for it to finish — do
not kill and retry.

## Report

Output to user on success:

```
Feature created:

Jira:           https://redhat.atlassian.net/browse/<KEY>
Component:      <component>
Team:           <team>
Fix version:    <version> | backlog (unset)
Labels:         [osac-ux, osac-ui if UI work][, customer, customer:<name>] | none
Bootstrap epic: https://redhat.atlassian.net/browse/<EPIC_KEY>
Bootstrap label: bootstrap
Epic fix version: <copied from Feature | not set (backlog)>
Epic team:      <copied from Feature | already set (unchanged)>
Bootstrap tasks:
  - PRD:        <TASK_PRD>
  - Design:     <TASK_DESIGN>
  [- UX Design:  <TASK_UX>         (osac-ux)   UI work only]
  [- UI Design:  <TASK_UI>         (osac-ui)   UI work only]
  (PRD/Design get team <team>; UX/UI Design get team OSAC-UI — see above
   for any team edit failures, which are non-fatal and reported live)
Status:         New
```

If bootstrap aborted after Feature (or epic) creation, report what was created,
the error, and stderr/JSON details — do not imply full success.

## Standard Feature Format

Features should include these sections (in `$BODY`):

- **Feature Goal** — What the feature aims to accomplish
- **Problem Statement** — The problem this feature solves
- **User Stories** — Outcome-focused stories organized by persona (all four OSAC personas must be addressed — either with stories or an explicit "not affected" note)
- **Definition of Done** — Checklist of completion criteria
- **Out of Scope** — What is explicitly excluded from this feature

See [feature-body-template.md](references/feature-body-template.md) for the Jira body template.

## Notes

- OSAC project key: `OSAC`
- Customer-driven features: add `customer` and `customer:<name>` labels on the Feature only
- When `REQUIRES_UI=yes`: Feature gets `osac-ux` and `osac-ui`; both UX Design
  and UI Design tasks are created (`REQUIRES_UI` gates the full UX → UI track)
- UX Design task gets `osac-ux`; UI Design task gets `osac-ui`; PRD and Design
  have no labels; bootstrap epic gets `bootstrap` only
- Jira hierarchy: Feature → Bootstrap epic → gate tasks (PRD, Design, [UX Design, UI Design])
- Gate task summaries include the Feature title (`<gate> - ${FEATURE_SUMMARY}`,
  e.g. `PRD - <FEATURE_SUMMARY>`) so they're identifiable outside the epic/Feature —
  see [bootstrap-tasks.md](references/bootstrap-tasks.md)
- Bootstrap epic: create without `-P`, then `jira issue edit -P` — Epic create with `-P` on a Feature parent returns HTTP 400; use `</dev/null` on all jira create/edit to avoid stdin hangs (jira-cli#948)
- Gate tasks track documentation milestones, not implementation work
- **Fix version:** Feature chooses at confirm gate; bootstrap epic copies when set;
  gate tasks never receive `fixVersion`
- **Team:** not writable via jira-cli (`customfield_10001`; see `apply_team()`
  in [bash-patterns.md](references/bash-patterns.md)) — set with a direct REST
  call instead. Feature chooses at confirm gate; bootstrap epic and PRD/Design
  gate tasks receive a copy; UX Design and UI Design gate tasks always get
  `OSAC-UI` regardless of the Feature's team
- Existing bootstrap epics predating this convention are not backfilled — only
  epics created going forward get the `bootstrap` label and copied `fixVersion`
- Temp files: source `tools/jira-safe-create.sh`; call `add_temp` in the parent shell after each `new_temp` — see `jira-task-management` Safe create pattern
- jira-cli handles markdown-to-ADF conversion automatically
