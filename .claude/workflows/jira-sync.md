<purpose>
Link GSD milestones and phases to existing Jira epics and tickets, or view current mapping. Manages the jira section in .planning/config.json.
</purpose>

<process>

## Parse Subcommand

Extract subcommand and arguments from $ARGUMENTS:

- `link-epic <EPIC-KEY>` — Link existing Jira epic to current milestone
- `link-phase <PHASE-NUMBER> <ISSUE-KEY>` — Link existing Jira ticket to a phase
- `status` — Show current Jira mapping
- `unlink` — Remove all Jira mappings
- (no args) — Show status

## Subcommand: link-epic

1. Validate the epic key format (MGMT-NNNNN):

```bash
EPIC_KEY="$1"
if [[ ! "$EPIC_KEY" =~ ^MGMT-[0-9]+$ ]]; then
  echo "Error: Expected format MGMT-NNNNN, got: $EPIC_KEY"
  exit 1
fi
```

2. Verify the epic exists in Jira:

```bash
jira issue view "$EPIC_KEY" --plain 2>&1
```

If error: "Epic $EPIC_KEY not found in Jira."

3. Store mapping:

```bash
node -e "
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync('.planning/config.json', 'utf8'));
if (!cfg.jira) cfg.jira = {};
cfg.jira.epic = '${EPIC_KEY}';
if (!cfg.jira.phases) cfg.jira.phases = {};
fs.writeFileSync('.planning/config.json', JSON.stringify(cfg, null, 2) + '\n');
"
```

4. Report:

```text
Linked ${EPIC_KEY} to current milestone.
Phase tasks will be created under this epic during /gsd:plan-phase.
Use /jira-sync link-phase to link existing tickets to phases.
```

## Subcommand: link-phase

1. Parse args: PHASE_NUMBER and ISSUE_KEY

```bash
PHASE_NUMBER="$1"
ISSUE_KEY="$2"

if [ -z "$PHASE_NUMBER" ] || [ -z "$ISSUE_KEY" ]; then
  echo "Usage: /jira-sync link-phase <phase-number> <ISSUE-KEY>"
  echo "Example: /jira-sync link-phase 3 MGMT-12346"
  exit 1
fi

if [[ ! "$PHASE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Expected numeric phase-number, got: $PHASE_NUMBER"
  exit 1
fi

if [[ ! "$ISSUE_KEY" =~ ^MGMT-[0-9]+$ ]]; then
  echo "Error: Expected format MGMT-NNNNN, got: $ISSUE_KEY"
  exit 1
fi
```

2. Verify the issue exists:

```bash
jira issue view "$ISSUE_KEY" --plain 2>&1
```

3. Store mapping:

```bash
node -e "
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync('.planning/config.json', 'utf8'));
if (!cfg.jira) cfg.jira = { epic: '', phases: {} };
if (!cfg.jira.phases) cfg.jira.phases = {};
cfg.jira.phases['${PHASE_NUMBER}'] = '${ISSUE_KEY}';
fs.writeFileSync('.planning/config.json', JSON.stringify(cfg, null, 2) + '\n');
"
```

4. Report:

```text
Linked Phase ${PHASE_NUMBER} to ${ISSUE_KEY}.
Commits for this phase will use: ${ISSUE_KEY}: <description>
```

## Subcommand: status

1. Read config:

```bash
node -e "
const fs = require('fs');
try {
  const cfg = JSON.parse(fs.readFileSync('.planning/config.json', 'utf8'));
  console.log(JSON.stringify(cfg.jira || null));
} catch(e) { console.log('null'); }
"
```

2. If no jira section:

```text
No Jira mapping configured.

Use /jira-sync link-epic MGMT-XXXXX to link an epic to the current milestone.
```

3. If jira section exists, display mapping table:

```text
## Jira Mapping

**Epic:** ${epic_key}

| Phase | Jira Key | Summary | Status |
|-------|----------|---------|--------|
```

For each mapped phase, fetch status from Jira:
```bash
jira issue view "$KEY" --plain 2>/dev/null | grep -E "^(Summary|Status):"
```

For unmapped phases (in roadmap but not in jira.phases), show "(not linked)".

## Subcommand: unlink

1. Remove jira section from config:

```bash
node -e "
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync('.planning/config.json', 'utf8'));
delete cfg.jira;
fs.writeFileSync('.planning/config.json', JSON.stringify(cfg, null, 2) + '\n');
"
```

2. Report: "Jira mapping removed. Commits will use default format."

</process>

<success_criteria>
- link-epic validates epic exists in Jira before storing
- link-phase validates issue exists before storing
- status shows all phases (mapped and unmapped) with live Jira data
- unlink cleanly removes mapping without affecting other config
- All operations are idempotent (re-linking overwrites previous mapping)
</success_criteria>
