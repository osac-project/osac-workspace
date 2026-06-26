---
name: enclave-ui-request
description: Request a new configuration item in the OSAC Enclave UI Wizard. Creates an osac-installer PR with the Helm schema change, a Jira Task for the enclave plugin to pick up the change, and a Jira Task for the enclave UI to expose the plugin settings. Use when the user wants to add a field, option, or control to the Enclave Wizard, or asks how to get something into the Enclave UI.
---

# Enclave UI Request

Add a new configuration item to the OSAC Enclave UI Wizard by performing three actions:

1. **osac-installer PR** — add the Helm value to `values.schema.json`
2. **Jira Task for enclave plugin** — pick up the osac-installer change and expose it
3. **Jira Task for enclave UI** — expose the enclave plugin's settings in the Wizard

## How the Wizard Works

The Enclave Wizard renders configuration controls automatically from the OSAC installer Helm chart's JSON Schema. The pipeline is: **osac-installer schema → enclave OSAC plugin → enclave UI Wizard**.

| Schema type | UI control |
|-------------|-----------|
| `enum` | Dropdown |
| `boolean` | Checkbox |
| `string` (no enum) | Free text input |
| `integer` / `number` | Numeric input |

The schema file: [`osac-installer/charts/osac/values.schema.json`](https://github.com/osac-project/osac-installer/blob/main/charts/osac/values.schema.json)

## When to Use

- User wants to add a new option to the Enclave Wizard UI
- User asks "how do I get X into the Enclave UI?"
- User wants a new Helm value exposed in the Wizard
- User mentions adding a config field, toggle, or dropdown to the enclave setup

## Gather Inputs

Collect from conversation context. Ask only if truly ambiguous:

| Input | Required | Default |
|-------|----------|---------|
| Config item summary | Yes | From conversation context |
| Description of the value | Yes | What it controls, why it's needed |
| Helm values path | Yes | e.g. `osac.dns.service` |
| Schema type | No | Inferred from description (string, boolean, enum, etc.) |
| Default value | If known | From conversation context |
| Enum options | If applicable | From conversation context |
| Parent epic key | If ambiguous | Ask user |
| Assignee | No | Unassigned |

## Action 1: Create osac-installer PR

Add the new value to the Helm chart's JSON schema and open a PR.

### 1a. Read the current schema

```bash
cat osac-installer/charts/osac/values.schema.json
```

### 1b. Edit the schema

Add the new property to the appropriate location in the JSON schema. Follow the existing structure — match naming conventions, nesting, and descriptions already in the file.

### 1c. Create the PR

Use the `create-pr` skill (`/create-pr`) from the `osac-installer/` directory. The PR title should reference the config item being added (e.g., "Add DNS service configuration to values schema").

Record the PR URL for use in the Jira tickets.

## Action 2: Jira Task for Enclave Plugin

Create a task for the enclave plugin team to pick up the osac-installer schema change and expose the new parameters.

```bash
PLUGIN_KEY=$(jira issue create -t Task --project OSAC \
  --summary "Enclave plugin: expose <config item> from osac-installer" \
  --body "## Enclave Plugin — Expose New OSAC Config

**osac-installer PR:** <PR-URL>

**Helm value path:** \`<helm.values.path>\`

**Description:**

<What this config value controls>

**Schema definition:**

| Property | Value |
|----------|-------|
| Type | <string / boolean / integer / enum> |
| Default | <default value, if any> |
| Enum options | <list, if applicable> |
| Required | <yes / no> |

**What needs to happen:**

Pick up the values.schema.json change from the osac-installer PR above and expose the new parameter(s) through the enclave OSAC plugin so the Wizard can render them.

**Acceptance criteria:**

- [ ] Plugin reads the new value(s) from the osac-installer Helm schema
- [ ] Parameter(s) are exposed to the enclave Wizard" \
  --label ENCLAVE-UI-0.1 \
  --label OSAC \
  --no-input --raw 2>/dev/null | jq -r '.key')
```

## Action 3: Jira Task for Enclave UI

Create a task for the enclave UI team to expose the plugin's settings in the Wizard.

```bash
UI_KEY=$(jira issue create -t Task --project OSAC \
  --summary "Enclave UI: render <config item> in Wizard" \
  --body "## Enclave UI — Render New Config in Wizard

**Depends on:** [$PLUGIN_KEY](https://redhat.atlassian.net/browse/$PLUGIN_KEY) (enclave plugin must expose the parameter first)

**osac-installer PR:** <PR-URL>

**Helm value path:** \`<helm.values.path>\`

**Description:**

<What this config value controls and how it should appear in the Wizard>

**Expected UI control:** <dropdown / checkbox / text input / numeric input>

**What needs to happen:**

Once the enclave plugin exposes this parameter ($PLUGIN_KEY), the Wizard should render the appropriate control for it.

**Acceptance criteria:**

- [ ] Wizard renders the appropriate control (dropdown/checkbox/text/etc.)
- [ ] Default value works correctly when not overridden
- [ ] Control is placed in the correct Wizard section" \
  --label ENCLAVE-UI-0.1 \
  --label OSAC \
  --no-input --raw 2>/dev/null | jq -r '.key')
```

### Link the UI ticket as blocked by the plugin ticket

```bash
jira issue link $UI_KEY $PLUGIN_KEY "is blocked by"
```

### Link to epic

If a parent epic was identified, link both tickets:
```bash
jira issue edit $PLUGIN_KEY -P <EPIC-KEY> --no-input
jira issue edit $UI_KEY -P <EPIC-KEY> --no-input
```

### Assign if specified

If user specified an assignee:
```bash
jira issue assign $PLUGIN_KEY <assignee>
jira issue assign $UI_KEY <assignee>
```

**Key extraction notes:**
- Use `--raw` to get JSON output on stdout, then `jq -r '.key'` to extract the issue key reliably.
- Redirect stderr to `/dev/null` — the success message goes to stderr and is not needed.
- Do **not** use `grep -oP` on the text output — it can match multiple keys in the URL or fail silently.

## Report

Output to user:

```
Enclave UI request completed — 3 actions:

1. osac-installer PR: <PR-URL>
   Schema change adding `<helm.values.path>`

2. Enclave plugin ticket: https://redhat.atlassian.net/browse/<PLUGIN_KEY>
   Pick up the schema change and expose the parameter

3. Enclave UI ticket: https://redhat.atlassian.net/browse/<UI_KEY>
   Render the control in the Wizard (blocked by plugin ticket)

Epic: <EPIC-KEY or "none">
```

## Complex Additions (Post-M1)

If the user's request requires custom UI logic beyond proxying a Helm value (e.g., multi-step wizards, conditional fields, API calls), inform them:

> This requires custom logic in the Enclave UI, which is out of scope for the current milestone (M1). After M1 delivery, these can be discussed and planned. For now, I'll create the tickets to track the request, but flag them as needing design discussion.

For these cases, add an additional label `ENCLAVE-UI-CUSTOM` to the UI ticket and note in the description that this requires custom UI work beyond the schema-driven approach.

## Notes

- OSAC project key: `OSAC`
- Required label: `ENCLAVE-UI-0.1` (milestone label — always apply to both tickets)
- The pipeline is: osac-installer schema → enclave plugin → enclave UI Wizard
- The UI ticket is blocked by the plugin ticket — the plugin must expose the parameter before the UI can render it
- jira-cli handles markdown-to-ADF conversion automatically
