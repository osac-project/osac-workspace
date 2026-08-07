# Enclave Wizard Pipeline

Any feature that adds or modifies Helm values in `osac-installer` must consider the Enclave Wizard pipeline. The Wizard renders configuration controls automatically from the Helm chart's JSON Schema — no custom UI code is needed for standard fields.

**Pipeline:** `osac-installer` schema change → enclave OSAC plugin picks up the change → Enclave Wizard UI renders the control.

**When it applies:** Any feature that adds or modifies installer Helm values that operators configure during deployment (e.g., DNS provider, storage backend, feature toggles).

## Schema-type-to-control mapping

| JSON Schema construct | Wizard UI control | Example |
|----------------------|-------------------|---------|
| `enum` | Dropdown | DNS provider: `route53`, `infoblox` |
| `boolean` | Checkbox | Enable bundled PostgreSQL |
| `string` (no enum) | Free text input | External hostname |
| `integer` / `number` | Numeric input | Worker node count |

The schema file is [`osac-installer/charts/osac/values.schema.json`](https://github.com/osac-project/osac-installer/blob/main/charts/osac/values.schema.json). Validation rules, default values, and descriptions come from the schema — the Wizard enforces them automatically.

## Design decompose artifacts

`/design:decompose` must produce three artifacts when the pipeline applies:

1. **osac-installer story** — add or update the Helm value in both `values.yaml` and `values.schema.json` with proper type, default, and description
2. **Enclave plugin task** — pick up the schema change and expose the parameter, blocked-by the installer story (Component: `Enclave`)
3. **Enclave UI task** — render the control in the Wizard, blocked-by the plugin task (Component: `Enclave`)

## Complex additions

If the feature requires custom UI logic beyond proxying a Helm value (e.g., multi-step wizards, conditional fields, API calls), flag the UI task as needing design discussion — the schema-driven approach won't cover it.
