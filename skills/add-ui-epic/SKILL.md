---
name: add-ui-epic
description: Create a UI epic under an OSAC Feature with one Task per persona, properly labeled and component-tagged.
---

# Add UI Epic to Feature

Create a UI epic under an existing OSAC Feature with one Task per OSAC
persona, properly labeled and component-tagged.

## When to Use

- After a PRD and design document (EP) have been approved for the Feature
- User says "add UI epic", "create UI tasks", "add UI work to feature"

## Gather Inputs

| Input | Required | Source |
|-------|----------|--------|
| Feature key | Yes | User provides (e.g., `OSAC-1433`) |
| UI work per persona | Yes | Ask user for a short description per persona |

## Process

### Step 1: Fetch Feature metadata

```bash
jira issue view <feature-key> --raw 2>/dev/null | jq '{
  key: .key,
  summary: .fields.summary,
  fixVersions: [.fields.fixVersions[].name],
  components: [.fields.components[].name]
}'
```

Extract:
- **`fixVersion`** — used to derive the label version (e.g., `0.2`)
- **`components`** — inherited by all tasks
- **`summary`** — used in the epic title

If `fixVersions` is empty, ask the user for the fix version.

### Step 2: Determine labels and components per persona

Create one Task per persona defined in
[`docs/personas.md`](https://github.com/osac-project/docs/blob/main/personas.md).

All tasks inherit the Feature's components. In addition:
- **Cloud Infrastructure Admin** tasks get `Enclave` component added
  and use `ENCLAVE-UI-<fixVersion>` label.
- **All other persona** tasks get `UI` component added and use
  `OSAC-UI-<fixVersion>` label.

### Step 3: Extract UI work per persona from existing documents

Before asking the user, try to extract per-persona UI descriptions from
the Feature's approved PRD and design document:

1. **Feature description** — read the Feature issue body from Jira
   (`jira issue view <feature-key> --raw`). Look for User Stories
   grouped by persona.
2. **PRD** — check if an approved PRD exists at
   `enhancement-proposals/enhancements/<feature-slug>/prd.md`. Look for
   user stories, acceptance criteria, or requirements that describe
   UI-observable capabilities per persona.
3. **Design document (EP)** — check if an approved design exists at
   `enhancement-proposals/enhancements/<feature-slug>/README.md`. Look
   for the Workflow Description section which describes what each persona
   does, and the API Extensions section for user-facing surfaces.

From these sources, draft a short UI task description per persona. Then
present to the user for confirmation:

```
Feature: <feature-key> — <summary>
Version: <fixVersion>
Components: <components>

Based on the PRD and design document, here are the proposed UI tasks:

1. Cloud Provider Admin (Console): <extracted description>
2. Cloud Infrastructure Admin (Enclave): <extracted description>
3. Tenant Admin (Console): <extracted description>
4. Tenant User (Console): <extracted description>

Please confirm, edit, or mark any persona as "skip" if not affected.
```

If no PRD or design document is found, ask the user to provide
descriptions directly.

### Step 4: Create the UI Epic

```bash
EPIC_KEY=$(jira issue create -t Epic --project OSAC \
  --summary "[UI] <feature summary>" \
  --body "UI work items for <feature-key>.

One task per OSAC persona. See parent Feature for requirements." \
  --parent <feature-key> \
  --component <component1> --component <component2> \
  --no-input --raw 2>/dev/null | jq -r '.key')
```

The epic gets the same components as the Feature (no `UI` or `Enclave` added).

Verify the epic was created and has the correct parent.

### Step 5: Create one Task per persona

For each persona that is not skipped, create a Task under the Epic.

**Cloud Provider Admin, Tenant Admin, Tenant User:**

```bash
jira issue create -t Task --project OSAC \
  --summary "[UI] <Persona>: <user-provided description>" \
  --body "<user-provided description>

Persona: <persona name>
Feature: <feature-key>
Epic: $EPIC_KEY" \
  --parent $EPIC_KEY \
  --label OSAC-UI-<version> \
  --component <feature-component1> --component <feature-component2> --component UI \
  --no-input --raw 2>/dev/null | jq -r '.key'
```

**Cloud Infrastructure Admin (Enclave):**

```bash
jira issue create -t Task --project OSAC \
  --summary "[UI] Cloud Infrastructure Admin: <user-provided description>" \
  --body "<user-provided description>

Persona: Cloud Infrastructure Admin
Feature: <feature-key>
Epic: $EPIC_KEY" \
  --parent $EPIC_KEY \
  --label ENCLAVE-UI-<version> \
  --component <feature-component1> --component <feature-component2> --component Enclave \
  --no-input --raw 2>/dev/null | jq -r '.key'
```

### Step 6: Report

```
UI Epic created:

Epic:     https://redhat.atlassian.net/browse/<EPIC_KEY>
Feature:  https://redhat.atlassian.net/browse/<feature-key>
Version:  <fixVersion>

Tasks:
  <TASK_KEY>  [UI] Cloud Provider Admin: <description>     (OSAC-UI-<ver>, <feature-components> + UI)
  <TASK_KEY>  [UI] Cloud Infrastructure Admin: <description> (ENCLAVE-UI-<ver>, <feature-components> + Enclave)
  <TASK_KEY>  [UI] Tenant Admin: <description>             (OSAC-UI-<ver>, <feature-components> + UI)
  <TASK_KEY>  [UI] Tenant User: <description>              (OSAC-UI-<ver>, <feature-components> + UI)
```

## Notes

- OSAC project key: `OSAC`
- The label version comes from the Feature's `fixVersion`, not from user input
- If a Feature has multiple `fixVersions`, use the first one
- jira-cli handles markdown-to-ADF conversion automatically
- Skipped personas do not get Tasks created — this is expected for features
  that don't affect all personas
