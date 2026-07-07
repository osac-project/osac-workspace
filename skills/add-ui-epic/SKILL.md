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

### Step 3: Ask user for UI work descriptions

Present the four personas and ask the user to provide a short description
of the UI work for each, or mark as "not affected":

```
Feature: <feature-key> — <summary>
Version: <fixVersion>
Components: <components>

Please provide a short UI task description for each persona
(or "skip" if not affected):

1. Cloud Provider Admin (Console):
2. Cloud Infrastructure Admin (Enclave):
3. Tenant Admin (Console):
4. Tenant User (Console):
```

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
