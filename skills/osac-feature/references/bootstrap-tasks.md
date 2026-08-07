# Create bootstrap tasks

**Read this file after bootstrap epic parent linkage is verified.**

**Requires [bash-patterns.md](bash-patterns.md) sourced first** — helpers (`collect_keys_from_jql`,
`require_osac_key`, `new_temp`) must already be defined.

## Gate task summary

Create documentation gate tasks under the bootstrap epic. Each task's Jira
summary is prefixed with its gate name and suffixed with the Feature title
(`<gate> - ${FEATURE_SUMMARY}`) so it's identifiable in flat Jira views
(backlog, board, "my issues") without opening the epic/Feature. Each body
uses blank lines between blocks (jira-cli preserves them). Non-empty lines
in order:

1. AC text (matches gate name)
2. `/prd` or `/design` workflow hint — PRD and Design only
3. `Feature: ${KEY}`

Do **not** reference `/ux-design` or `/ui-design`.

| Summary | Labels | Body (non-empty lines in `$TASK_BODY`) | When |
|---------|--------|----------------------------------------|------|
| `PRD - ${FEATURE_SUMMARY}` | (none) | 1: Draft, submit, and merge the Product Requirements Document. 2: Use `/prd` workflow. 3: Feature: ${KEY} | Always |
| `Design - ${FEATURE_SUMMARY}` | (none) | 1: Draft, submit, and merge the technical Design / Enhancement Proposal. 2: Use `/design` workflow. 3: Feature: ${KEY} | Always |
| `UX Design - ${FEATURE_SUMMARY}` | `osac-ux` | 1: Draft, submit, and merge the UX specification. 2: Feature: ${KEY} | `REQUIRES_UI=yes` |
| `UI Design - ${FEATURE_SUMMARY}` | `osac-ui` | 1: Draft, submit, and merge the UI design document. 2: Feature: ${KEY} | `REQUIRES_UI=yes` |

Apply gate-task labels only on the task they describe — do **not** put `osac-ux`
on UI Design or `osac-ui` on UX Design. PRD and Design have no labels
(universal gates, not UX- or UI-specific work).

## Duplicate check

For each gate task, duplicate-check with exact summary (substitute gate name in
JQL — full summaries are literal: `PRD - ${FEATURE_SUMMARY}`, `Design - ${FEATURE_SUMMARY}`,
`UX Design - ${FEATURE_SUMMARY}`, `UI Design - ${FEATURE_SUMMARY}`).

Also match the **bare legacy gate name** (`PRD`, `Design`, `UX Design`, `UI Design`
with no Feature-title suffix) in the same query — epics bootstrapped before this
naming convention have gate tasks titled that way, and an exact-match on only the
titled summary would miss them and create a duplicate:

```bash
TASK_SUMMARY="PRD - ${FEATURE_SUMMARY}"   # or Design, UX Design, UI Design
GATE_NAME="PRD"                            # bare gate word — same substitution
collect_keys_from_jql "parent = ${EPIC_KEY} AND type = Task AND (summary = \"${TASK_SUMMARY}\" OR summary = \"${GATE_NAME}\")" \
  || { echo "Task duplicate-check failed for ${TASK_SUMMARY} — stopping before create" >&2; exit 1; }
if [ "$KEY_COUNT" -gt 1 ]; then
  echo "Multiple tasks named ${TASK_SUMMARY} under epic — ask user" >&2
  exit 1
fi
if [ "$KEY_COUNT" -eq 1 ]; then
  TASK_PRD=$FIRST_KEY   # substitute TASK_DESIGN, TASK_UX, or TASK_UI per summary
else
  # create block below (only when KEY_COUNT == 0)
fi
```

A failed lookup must stop here — do not fall through and create a task on an
unconfirmed duplicate state. When reusing `FIRST_KEY` (titled or legacy match),
skip the create command for that summary — do not rename a reused legacy task;
the one-time bulk rename covers backfilling those.

## Task creation order

Create tasks in order: **PRD → Design → UX Design → UI Design** (last two only
when `REQUIRES_UI=yes`). Reuse temps via `new_temp` each iteration.

Task create with `-P "${EPIC_KEY}"` is safe — Jira only rejects `-P` on **Epic
create** when the parent is a Feature; tasks under an epic accept `-P` normally.

## PRD task

```bash
TASK_SUMMARY="PRD - ${FEATURE_SUMMARY}"
GATE_NAME="PRD"
collect_keys_from_jql "parent = ${EPIC_KEY} AND type = Task AND (summary = \"${TASK_SUMMARY}\" OR summary = \"${GATE_NAME}\")" \
  || { echo "Task duplicate-check failed for ${TASK_SUMMARY} — stopping before create" >&2; exit 1; }
if [ "$KEY_COUNT" -gt 1 ]; then
  echo "Multiple tasks named ${TASK_SUMMARY} under epic — ask user" >&2
  exit 1
fi
if [ "$KEY_COUNT" -eq 1 ]; then
  TASK_PRD=$FIRST_KEY
else
TASK_BODY=$(new_temp osac-bootstrap-task)
add_temp "$TASK_BODY"
OUT=$(new_temp osac-jira-task-out)
add_temp "$OUT"
ERR=$(new_temp osac-jira-task-err)
add_temp "$ERR"

cat >"$TASK_BODY" <<EOF
Draft, submit, and merge the Product Requirements Document.

Use \`/prd\` workflow.

Feature: ${KEY}
EOF

jira issue create -t Task --project OSAC -s "${TASK_SUMMARY}" \
  --template "$TASK_BODY" \
  -P "${EPIC_KEY}" --no-input --raw >"$OUT" 2>"$ERR" </dev/null

TASK_PRD=$(jq -r '.key // empty' "$OUT")
if ! [[ "${TASK_PRD}" =~ ^OSAC-[0-9]+$ ]]; then
  echo "PRD task create failed — Feature: ${KEY}, epic: ${EPIC_KEY}" >&2
  cat "$ERR" >&2
  jq -r '.errorMessages[]? // .errors? // empty' "$OUT" 2>/dev/null >&2
  exit 1
fi
apply_team "$TASK_PRD" "$TEAM"
fi
```

Repeat for Design, UX Design, and UI Design (change `TASK_SUMMARY` — always
`<gate> - ${FEATURE_SUMMARY}` — and `GATE_NAME` to the bare gate word, plus
body, labels, and target variable per the table). Use the same duplicate-check
+ reuse/skip pattern before each create block. Use the same empty-key guard
before exiting — include every completed task key in the context line. Call
`apply_team` right after the empty-key guard, same as the PRD task above —
`"$TEAM"` for the Design task, hardcoded `"OSAC-UI"` for UX Design and UI
Design regardless of `$TEAM` (see UX/UI Design task blocks below). Only
newly-created tasks get this call — reused tasks (from the duplicate check
above) are left as-is, matching this file's existing reuse behavior for
labels and body.

## UX Design task

When `REQUIRES_UI=yes`:

```bash
TASK_SUMMARY="UX Design - ${FEATURE_SUMMARY}"
GATE_NAME="UX Design"
collect_keys_from_jql "parent = ${EPIC_KEY} AND type = Task AND (summary = \"${TASK_SUMMARY}\" OR summary = \"${GATE_NAME}\")" \
  || { echo "Task duplicate-check failed for ${TASK_SUMMARY} — stopping before create" >&2; exit 1; }
if [ "$KEY_COUNT" -gt 1 ]; then
  echo "Multiple tasks named ${TASK_SUMMARY} under epic — ask user" >&2
  exit 1
fi
if [ "$KEY_COUNT" -eq 1 ]; then
  TASK_UX=$FIRST_KEY
else
cat >"$TASK_BODY" <<EOF
Draft, submit, and merge the UX specification.

Feature: ${KEY}
EOF

jira issue create -t Task --project OSAC -s "${TASK_SUMMARY}" \
  --template "$TASK_BODY" \
  -P "${EPIC_KEY}" --label osac-ux --no-input --raw >"$OUT" 2>"$ERR" </dev/null

TASK_UX=$(jq -r '.key // empty' "$OUT")
if ! [[ "${TASK_UX}" =~ ^OSAC-[0-9]+$ ]]; then
  echo "UX Design task create failed — Feature: ${KEY}, epic: ${EPIC_KEY}, PRD: ${TASK_PRD}, Design: ${TASK_DESIGN}" >&2
  cat "$ERR" >&2
  jq -r '.errorMessages[]? // .errors? // empty' "$OUT" 2>/dev/null >&2
  exit 1
fi
apply_team "$TASK_UX" "OSAC-UI"
fi
```

## UI Design task

When `REQUIRES_UI=yes`:

```bash
TASK_SUMMARY="UI Design - ${FEATURE_SUMMARY}"
GATE_NAME="UI Design"
collect_keys_from_jql "parent = ${EPIC_KEY} AND type = Task AND (summary = \"${TASK_SUMMARY}\" OR summary = \"${GATE_NAME}\")" \
  || { echo "Task duplicate-check failed for ${TASK_SUMMARY} — stopping before create" >&2; exit 1; }
if [ "$KEY_COUNT" -gt 1 ]; then
  echo "Multiple tasks named ${TASK_SUMMARY} under epic — ask user" >&2
  exit 1
fi
if [ "$KEY_COUNT" -eq 1 ]; then
  TASK_UI=$FIRST_KEY
else
cat >"$TASK_BODY" <<EOF
Draft, submit, and merge the UI design document.

Feature: ${KEY}
EOF

jira issue create -t Task --project OSAC -s "${TASK_SUMMARY}" \
  --template "$TASK_BODY" \
  -P "${EPIC_KEY}" --label osac-ui --no-input --raw >"$OUT" 2>"$ERR" </dev/null

TASK_UI=$(jq -r '.key // empty' "$OUT")
if ! [[ "${TASK_UI}" =~ ^OSAC-[0-9]+$ ]]; then
  echo "UI Design task create failed — Feature: ${KEY}, epic: ${EPIC_KEY}, PRD: ${TASK_PRD}, Design: ${TASK_DESIGN}, UX: ${TASK_UX}" >&2
  cat "$ERR" >&2
  jq -r '.errorMessages[]? // .errors? // empty' "$OUT" 2>/dev/null >&2
  exit 1
fi
apply_team "$TASK_UI" "OSAC-UI"
fi
```

UX/UI task bodies omit the `/prd` or `/design` workflow line — see table above.

## Error handling

On any empty task key, stop and report Feature key, epic key, completed task
keys, plus `$ERR` and error JSON from `$OUT`. The explicit guards above emit
that bootstrap context before exit; Design failures should include `PRD: ${TASK_PRD}`;
UX failures include PRD + Design; UI failures include PRD, Design, and UX.
