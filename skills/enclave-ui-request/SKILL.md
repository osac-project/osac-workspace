---
name: enclave-ui-request
description: Request a new configuration item in the OSAC Enclave UI Wizard. Creates a Jira Task with the ENCLAVE-UI-0.1 label describing the Helm value to add, and guides the user through the full workflow (Jira ticket → values.schema.json PR → UI renders automatically). Use when the user wants to add a field, option, or control to the Enclave Wizard, or asks how to get something into the Enclave UI.
---

# Enclave UI Request

Create a Jira Task requesting a new configuration item in the OSAC Enclave UI Wizard, and guide the contributor through the end-to-end workflow.

## How the Wizard Works

The Enclave Wizard renders configuration controls automatically from the OSAC installer Helm chart's JSON Schema. No custom UI code is needed for standard values — the schema drives the control type:

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

## Workflow Overview

There are four steps — the skill handles step 1 (Jira ticket). Steps 2–4 are guidance for the contributor.

1. **Open a Jira Task** with label `ENCLAVE-UI-0.1` describing the config value
2. **Add the Helm value** to `osac-installer/charts/osac/values.schema.json` with proper schema definition (contributor PR)
3. **Enclave OSAC plugin picks it up** — based on the schema, the plugin exposes the parameters to the Wizard
4. **Wizard renders the control** — the right UI control (dropdown, checkbox, free text, etc.) is rendered automatically with no custom UI logic needed

**The Jira ticket is mandatory.** The `ENCLAVE-UI-0.1` label is how the UI team tracks and prioritizes Wizard requests — without a labeled ticket, the request is invisible to them and will not be picked up. Always create the ticket first, even if the schema change is trivial or already in progress.

## Gather Inputs

Collect from conversation context. Ask only if truly ambiguous:

| Input | Required | Default |
|-------|----------|---------|
| Config item summary | Yes | From conversation context |
| Description of the value | Yes | What it controls, why it's needed |
| Schema type | No | Inferred from description (string, boolean, enum, etc.) |
| Default value | If known | From conversation context |
| Enum options | If applicable | From conversation context |
| Parent epic key | If ambiguous | Ask user |
| Assignee | No | Unassigned |
| Additional labels | No | None — `ENCLAVE-UI-0.1` is always applied |

## Create the Jira Task

```bash
KEY=$(jira issue create -t Task --project OSAC \
  --summary "<concise title — e.g. 'Add DNS service configuration support for enclave'>" \
  --body "## Enclave Wizard Configuration Request

**Config value:** \`<helm.values.path>\`

**Description:**

<What this config value controls and why it should be in the Wizard>

**Schema definition:**

| Property | Value |
|----------|-------|
| Type | <string / boolean / integer / enum> |
| Default | <default value, if any> |
| Enum options | <list, if applicable> |
| Required | <yes / no> |

**Acceptance criteria:**

- [ ] Value added to \`charts/osac/values.schema.json\` with proper schema definition
- [ ] Wizard renders the appropriate control (dropdown/checkbox/text/etc.)
- [ ] Default value works correctly when not overridden" \
  --label ENCLAVE-UI-0.1 \
  --label OSAC \
  --affects-version "OSAC" \
  --no-input --raw 2>/dev/null | jq -r '.key')
```

**Key extraction notes:**
- Use `--raw` to get JSON output on stdout, then `jq -r '.key'` to extract the issue key reliably.
- Redirect stderr to `/dev/null` — the success message goes to stderr and is not needed.
- Do **not** use `grep -oP` on the text output — it can match multiple keys in the URL or fail silently.

### Link to epic

If a parent epic was identified:
```bash
jira issue edit $KEY -P <EPIC-KEY> --no-input
```

### Assign if specified

If user specified an assignee:
```bash
jira issue assign $KEY <assignee>
```

## Report

Output to user:

```
Enclave UI request created:

Jira:   https://redhat.atlassian.net/browse/<KEY>
Epic:   <EPIC-KEY or "none">
Status: New
```

## Next Steps

After the ticket is created, guide the contributor:

1. Add the value to `osac-installer/charts/osac/values.schema.json` ([link](https://github.com/osac-project/osac-installer/blob/main/charts/osac/values.schema.json))
2. Open a PR on `osac-installer` with the schema change
3. The Enclave OSAC plugin will pick up the new parameters from the schema and expose them to the Wizard
4. The Wizard renders the appropriate control automatically — no custom UI logic needed

## Complex Additions (Post-M1)

If the user's request requires custom UI logic beyond proxying a Helm value (e.g., multi-step wizards, conditional fields, API calls), inform them:

> This requires custom logic in the Enclave UI, which is out of scope for the current milestone (M1). After M1 delivery, these can be discussed and planned. For now, I'll create a ticket to track the request, but flag it as needing design discussion.

For these cases, add an additional label `ENCLAVE-UI-CUSTOM` and note in the description that this requires custom UI work beyond the schema-driven approach.

## Notes

- OSAC project key: `OSAC`
- Required label: `ENCLAVE-UI-0.1` (milestone label — always apply)
- The Wizard is schema-driven: adding the value to `values.schema.json` is all that's needed for standard controls
- jira-cli handles markdown-to-ADF conversion automatically
