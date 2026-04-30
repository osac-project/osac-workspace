<purpose>
Lifecycle hooks that integrate GSD workflow commands with Jira. Each hook is guarded by `command -v jira &>/dev/null` — skip entirely if jira CLI is absent. Mapping is stored in `.planning/config.json` under the `jira` key.
</purpose>

<process>

## After `/gsd:new-milestone` — Create or Link Epic

After the roadmap is committed (before presenting next steps), create a Jira Epic for the milestone or skip if one is already linked:

```bash
if command -v jira &>/dev/null; then
  EXISTING_EPIC=$(node -e "try { const c=JSON.parse(require('fs').readFileSync('.planning/config.json','utf8')); console.log(c.jira?.epic || ''); } catch(e) { console.log(''); }")

  if [ -n "$EXISTING_EPIC" ]; then
    echo "Jira Epic already linked: ${EXISTING_EPIC} — skipping creation"
  else
    MILESTONE_TITLE="<milestone version and name from PROJECT.md>"
    MILESTONE_GOAL="<one-sentence goal from the milestone>"

    EPIC_OUTPUT=$(jira epic create -s "${MILESTONE_TITLE}" -n "${MILESTONE_TITLE}" -b "GSD Milestone: ${MILESTONE_GOAL}" -l OSAC --no-input 2>&1)
    EPIC_KEY=$(echo "$EPIC_OUTPUT" | grep -oE 'MGMT-[0-9]+' | head -1)

    if [ -n "$EPIC_KEY" ]; then
      node -e "
      const fs = require('fs');
      const cfg = JSON.parse(fs.readFileSync('.planning/config.json', 'utf8'));
      cfg.jira = cfg.jira || { epic: '', phases: {} };
      cfg.jira.phases = (cfg.jira.phases && typeof cfg.jira.phases === 'object') ? cfg.jira.phases : {};
      cfg.jira.epic = '${EPIC_KEY}';
      fs.writeFileSync('.planning/config.json', JSON.stringify(cfg, null, 2) + '\n');
      "
      echo "Jira Epic created: ${EPIC_KEY}"
    else
      echo "Warning: Could not create Jira epic (jira CLI may not be configured)"
    fi
  fi
fi
```

## After `/gsd:plan-phase` — Create Task for Phase

After plans are verified (before presenting final status), create a Jira Task under the Epic for this phase:

```bash
if command -v jira &>/dev/null; then
  EPIC_KEY=$(node -e "try { const c=JSON.parse(require('fs').readFileSync('.planning/config.json','utf8')); console.log(c.jira?.epic || ''); } catch(e) { console.log(''); }")
  EXISTING=$(node -e "try { const c=JSON.parse(require('fs').readFileSync('.planning/config.json','utf8')); console.log(c.jira?.phases?.['${PHASE}'] || ''); } catch(e) { console.log(''); }")

  if [ -n "$EPIC_KEY" ] && [ -z "$EXISTING" ]; then
    TASK_OUTPUT=$(jira issue create -tTask -s "Phase ${PHASE}: ${phase_name}" \
      -b "GSD Phase ${PHASE}: ${phase_name}" \
      -P "$EPIC_KEY" -l OSAC --no-input 2>&1)
    TASK_KEY=$(echo "$TASK_OUTPUT" | grep -oE 'MGMT-[0-9]+' | head -1)

    if [ -n "$TASK_KEY" ]; then
      node -e "
      const fs = require('fs');
      const cfg = JSON.parse(fs.readFileSync('.planning/config.json', 'utf8'));
      if (!cfg.jira) cfg.jira = { epic: '', phases: {} };
      if (!cfg.jira.phases) cfg.jira.phases = {};
      cfg.jira.phases['${PHASE}'] = '${TASK_KEY}';
      fs.writeFileSync('.planning/config.json', JSON.stringify(cfg, null, 2) + '\n');
      "
      echo "Jira Task created: ${TASK_KEY} (linked to ${EPIC_KEY})"
    fi
  fi
fi
```

## During `/gsd:execute-phase` — Move Task to In Progress

Before spawning executor agents, move the phase's Jira Task to "In Progress":

```bash
if command -v jira &>/dev/null; then
  JIRA_KEY=$(node -e "try { const c=JSON.parse(require('fs').readFileSync('.planning/config.json','utf8')); console.log(c.jira?.phases?.['${PHASE_NUMBER}'] || ''); } catch(e) { console.log(''); }")
  if [ -n "$JIRA_KEY" ]; then
    jira issue move "$JIRA_KEY" "In Progress" 2>/dev/null || true
    echo "Jira ${JIRA_KEY} → In Progress"
  fi
fi
```

## During `/gsd:execute-plan` — Jira-Prefixed Commits

When committing task code, resolve the Jira key for the current phase and use it as the commit prefix:

```bash
JIRA_KEY=$(node -e "
try {
  const fs = require('fs');
  const c = JSON.parse(fs.readFileSync('.planning/config.json', 'utf8'));
  const phase = '${PHASE}'.split('-')[0].replace(/^0+/, '');
  console.log(c.jira?.phases?.[phase] || '');
} catch(e) { console.log(''); }
" 2>/dev/null)
```

**If JIRA_KEY is set**, use Jira-prefixed format for all commits:
- `MGMT-12346: create user registration endpoint`
- `MGMT-12346: add failing test for password hashing`
- `MGMT-12346: complete [plan-name] plan` (metadata commit)

**If JIRA_KEY is empty**, fall back to conventional commit format:
- `feat({phase}-{plan}): description`
- `test({phase}-{plan}): description`
- `docs({phase}-{plan}): description`

## After `/gsd:complete-milestone` — Move Epic to Done

After the milestone is archived and tagged, move the Jira Epic to "Done":

```bash
if command -v jira &>/dev/null; then
  EPIC_KEY=$(node -e "try { const c=JSON.parse(require('fs').readFileSync('.planning/config.json','utf8')); console.log(c.jira?.epic || ''); } catch(e) { console.log(''); }")
  if [ -n "$EPIC_KEY" ]; then
    jira issue move "$EPIC_KEY" "Done" 2>/dev/null || true
    echo "Jira Epic ${EPIC_KEY} → Done"
  fi
fi
```

</process>
