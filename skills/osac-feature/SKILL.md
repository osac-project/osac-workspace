---
name: osac-feature
description: Create Feature issues in the OSAC Jira project. Use when the user wants to create a Feature, enhancement, or new capability request for OSAC.
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
for **Requires UI work** and **Fix version**, which must always be asked
explicitly (never inferred from the description or summary).

| Input | Required | Default |
|-------|----------|---------|
| Feature summary | Yes | From conversation context |
| Description | Yes | From conversation context |
| Component | Yes | Infer from context: VMaaS, CaaS, BMaaS, Core, Storage, Connectivity&Fabric, UI, Infrastructure, Enclave |
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
- More than 255 characters (Jira summary limit)

Summaries are embedded in exact-match JQL (`summary = "..."`) and shell `-q`
strings; these characters break parsing or expansion. Summaries must be a
single safe line (hyphens, colons, and commas are fine).

Store the validated value in `FEATURE_SUMMARY`.

### Component

Infer from conversation context. Valid values: VMaaS, CaaS, BMaaS, Core,
Storage, Connectivity&Fabric, UI, Infrastructure, Enclave. Ask if ambiguous.
Store in `COMPONENT`.

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

1. Run `list_fix_version_suggestions` (see Reusable bash patterns) to fetch
   unreleased OSAC milestones, excluding `0.0` and the literal `Backlog`
   release (collides with the `backlog` sentinel below — see step 3).
2. Propose the highest version as default, e.g. "Proposed fix version: **0.3**.
   Accept, specify another milestone, or choose **backlog** (no fix version)?"
3. Normalize the user's answer via `validate_fix_version` and store in `FIX_VERSION`:
   - A valid release name from the suggestion list
   - `backlog` when the user explicitly says backlog, none, or skip
4. On `invalid` (including empty input), ask again — do not default to backlog.

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
  Customer:    <name or none>
  UI work:     yes | no
  Fix version: <version> | backlog (unset)
  Labels:      [osac-ux, osac-ui if UI work][, customer, customer:<name>] | none
  Assignee:    <name or unassigned>

  Bootstrap epic:  <FEATURE_SUMMARY> - Bootstrap
    Label: bootstrap; fix version copied from Feature (when not backlog)
  Bootstrap tasks: PRD, Design[, UX Design, UI Design if UI work]

  (Gate tasks do not receive fix version.)

Proceed? (yes/no)
```

Only continue when the user answers yes.

## Reusable bash patterns

Define once before any Jira create: source `tools/jira-safe-create.sh` (see
`jira-task-management` Safe create pattern), then define skill-specific helpers
below. Reference these from each create step instead of duplicating key
validation or `--plain` parsing.

```bash
source "$(git rev-parse --show-toplevel)/tools/jira-safe-create.sh"

# After jq -r '.key // empty' — stop on empty/malformed keys
require_osac_key() {
  local key=$1 label=$2 out=$3 err=$4
  if ! [[ "${key}" =~ ^OSAC-[0-9]+$ ]]; then
    echo "Invalid or empty ${label} key: ${key:-<empty>}" >&2
    cat "$err" >&2
    jq -r '.errorMessages[]? // .errors? // empty' "$out" 2>/dev/null >&2
    exit 1
  fi
}

# Parse KEY column from jira issue list --plain (skip header row).
# jira-cli --plain is tab-separated: TYPE, KEY, SUMMARY, … — column 2 is KEY.
# If layout changes, fall back to first OSAC-NNNN token on the line.
parse_plain_keys() {
  tail -n +2 | while IFS= read -r line; do
    [ -z "$line" ] && continue
    key=$(printf '%s\n' "$line" | awk -F'\t' '$2 ~ /^OSAC-[0-9]+$/ {print $2; exit}')
    if [ -n "$key" ]; then
      echo "$key"
    else
      printf '%s\n' "$line" | grep -Eo 'OSAC-[0-9]+' | head -1
    fi
  done
}

# Collect keys for JQL into variables (bash 3.2 / zsh — no mapfile).
# Usage: read keys from list_keys_for_jql "…" into FIRST_KEY and KEY_COUNT.
list_keys_for_jql() {
  jira issue list -q "$1" --plain | parse_plain_keys
}

collect_keys_from_jql() {
  local jql=$1
  FIRST_KEY=""
  KEY_COUNT=0
  local k
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    KEY_COUNT=$((KEY_COUNT + 1))
    FIRST_KEY=$k
  done < <(list_keys_for_jql "$jql")
}

# Fetch OSAC fix-version candidates (exclude 0.0 — pre-team legacy bucket —
# and the literal "Backlog" release, which collides with this skill's own
# "backlog" sentinel for "no fix version"; see validate_fix_version).
# jira release list does NOT support useful --plain output; parse tab format.
# Columns: ID, NAME, RELEASED, DESCRIPTION
# Output: one version name per line, newest first (sort -Vr).
list_fix_version_suggestions() {
  jira release list -p OSAC 2>/dev/null \
    | awk -F'\t' 'NR>1 && $2 != "0.0" && tolower($2) != "backlog" && $3 == "false" {print $2}' \
    | sort -Vr
}

# Validate user-chosen version. Returns: backlog | <version> | invalid
# backlog only when user explicitly says backlog/none/skip (not empty string).
validate_fix_version() {
  local choice
  choice=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  case "$choice" in
    backlog|none|skip) echo "backlog"; return 0 ;;
    '') echo "invalid"; return 0 ;;
  esac
  if list_fix_version_suggestions | grep -Fxq "$1"; then
    echo "$1"
  else
    echo "invalid"
  fi
}

# Set fixVersion on Feature when FIX_VERSION is not backlog.
# Run after require_osac_key on Feature KEY, before assign/bootstrap; use </dev/null>.
# jira issue edit --fix-version appends; safe on new Features (empty fixVersions).
# Returns 1 on edit failure (non-fatal — does not exit) so the caller can avoid
# copying an unset version onto the bootstrap epic. Backlog is not a failure.
apply_feature_fix_version() {
  local key=$1 version=$2
  [ "$version" = "backlog" ] && return 0
  local err
  err=$(new_temp osac-jira-fixver-err)
  add_temp "$err"
  if ! jira issue edit "$key" --fix-version "$version" --no-input 2>"$err" </dev/null; then
    echo "Fix version edit failed for ${key} (${version}) — set manually:" >&2
    echo "  jira issue edit ${key} --fix-version \"${version}\" --no-input </dev/null" >&2
    cat "$err" >&2
    return 1
  fi
}

# After bootstrap epic parent verified. Label at create; copy fix version here.
# Re-run safe on reuse: add label if missing; set fix version only when epic has none.
# Caller passes "backlog" for fix_version when the Feature edit did not succeed,
# so a failed Feature update never results in a copied version on the epic.
apply_bootstrap_epic_metadata() {
  local epic_key=$1 feature_key=$2 fix_version=$3
  local err
  err=$(new_temp osac-jira-bootstrap-meta-err)
  add_temp "$err"

  if ! jira issue edit "$epic_key" -l bootstrap --no-input 2>>"$err" </dev/null; then
    echo "Bootstrap label edit failed for ${epic_key} — set manually:" >&2
    echo "  jira issue edit ${epic_key} -l bootstrap --no-input </dev/null" >&2
    cat "$err" >&2
  fi

  [ "$fix_version" = "backlog" ] && return 0

  local epic_version_count
  epic_version_count=$(jira issue view "$epic_key" --raw 2>/dev/null \
    | jq -r '[.fields.fixVersions[]?.name] | length')
  [ "${epic_version_count:-0}" -gt 0 ] && return 0

  if ! jira issue edit "$epic_key" --fix-version "$fix_version" --no-input 2>>"$err" </dev/null; then
    echo "Bootstrap fix version copy failed for ${epic_key} (${fix_version}) — set manually:" >&2
    echo "  jira issue edit ${epic_key} --fix-version \"${fix_version}\" --no-input </dev/null" >&2
    cat "$err" >&2
    return 0
  fi
}
```

Safe-create rules (all create/edit steps):
- Append **`</dev/null`** to every `jira issue create` and `jira issue edit` — jira-cli
  blocks on stdin in non-TTY shells ([jira-cli#948](https://github.com/ankitpokhrel/jira-cli/issues/948))
- Run `jira issue create` directly — not inside `$(...)`
- Write bodies to `--template` files; capture stdout/stderr to temps
- Allow up to 3 minutes per operation; **never kill** and retry
- Before retry, re-search Jira — duplicate creates are worse than slow creates
- If stdout is slow, poll Jira (`jira issue view`) instead of killing the in-flight command

```bash
BODY=$(new_temp osac-feature-body)
add_temp "$BODY"
OUT=$(new_temp osac-jira-out)
add_temp "$OUT"
ERR=$(new_temp osac-jira-err)
add_temp "$ERR"
# ... jira issue create ... >"$OUT" 2>"$ERR" </dev/null
KEY=$(jq -r '.key // empty' "$OUT")
require_osac_key "$KEY" "Feature" "$OUT" "$ERR"
```

Duplicate search pattern:

```bash
collect_keys_from_jql "parent = ${EPIC_KEY} AND type = Task AND summary = \"PRD\""
# KEY_COUNT == 1 → reuse FIRST_KEY; KEY_COUNT > 1 → ask user; 0 → create
```

## Create the Feature

The User Stories section must include a subsection for each OSAC persona
defined in [`docs/personas.md`](https://github.com/osac-project/docs/blob/main/personas.md).
For each persona, either write an outcome-focused story ("As a X, I want Y
so that Z") or explicitly mark the persona as not affected by this feature.

Write the Feature body to `$BODY` using this structure (`BODY=$(new_temp osac-feature-body)` first). Use a blank line before
each `###` persona heading so jira-cli preserves separate subsections in Jira.

```markdown
## Feature Goal
<What this feature aims to accomplish>

## Problem Statement
<The problem this feature solves>

## User Stories

### Cloud Provider Admin

- As a Cloud Provider Admin, I want <outcome> so that <reason>
- (or: not affected by this feature)

### Cloud Infrastructure Admin

- As a Cloud Infrastructure Admin, I want <outcome> so that <reason>
- (or: not affected by this feature)

### Tenant Admin

- As a Tenant Admin, I want <outcome> so that <reason>
- (or: not affected by this feature)

### Tenant User

- As a Tenant User, I want <outcome> so that <reason>
- (or: not affected by this feature)

## Definition of Done
- [ ] <criterion>

## Out of Scope
<What is excluded>
```

Safe-create — use patterns above (`new_temp`, `require_osac_key`):

```bash
BODY=$(new_temp osac-feature-body)
add_temp "$BODY"
# write markdown body to $BODY, then:
OUT=$(new_temp osac-jira-feature-out)
add_temp "$OUT"
ERR=$(new_temp osac-jira-feature-err)
add_temp "$ERR"

FEATURE_LABELS=()
[ "$REQUIRES_UI" = "yes" ] && FEATURE_LABELS+=(--label osac-ux --label osac-ui)
[ -n "${CUSTOMER:-}" ] && FEATURE_LABELS+=(--label customer --label "customer:${CUSTOMER}")

jira issue create -t Feature --project OSAC \
  -s "${FEATURE_SUMMARY}" \
  --template "$BODY" \
  --component "${COMPONENT}" \
  "${FEATURE_LABELS[@]}" \
  --no-input --raw >"$OUT" 2>"$ERR" </dev/null

KEY=$(jq -r '.key // empty' "$OUT")
require_osac_key "$KEY" "Feature" "$OUT" "$ERR"
if apply_feature_fix_version "$KEY" "$FIX_VERSION"; then
  BOOTSTRAP_FIX_VERSION="$FIX_VERSION"
else
  echo "Feature fix version not applied — bootstrap epic will not receive a copy; set both manually" >&2
  BOOTSTRAP_FIX_VERSION="backlog"
fi
```

Allow up to 3 minutes for create to complete.

Order after Feature create: **fix version → assign (if any) → bootstrap epic**.
Gate tasks never receive `--fix-version`. Use `$BOOTSTRAP_FIX_VERSION` (not
`$FIX_VERSION`) when applying bootstrap epic metadata below — it reflects
whether the Feature edit actually succeeded.

### Assign if specified

If user specified an assignee:

```bash
ASSIGN_ERR=$(new_temp osac-jira-assign-err)
add_temp "$ASSIGN_ERR"
if ! jira issue assign "$KEY" "$ASSIGNEE" 2>"$ASSIGN_ERR"; then
  echo "Assign failed for ${KEY} — continuing bootstrap" >&2
  cat "$ASSIGN_ERR" >&2
fi
```

## Create Bootstrap Epic

After the Feature is created, fix version is set (when not backlog), and
optionally assigned, create a bootstrap epic under the Feature. Use
`jira issue create -t Epic` — **not** `jira epic create`
(that subcommand has no parent flag).

Set `EPIC_SUMMARY="${FEATURE_SUMMARY} - Bootstrap"` for searches and create.

**Duplicate check** — exact summary, scoped to parent; also check **orphan**
epics (no parent) from a failed create-then-parent run:

```bash
collect_keys_from_jql "parent = ${KEY} AND type = Epic AND summary = \"${EPIC_SUMMARY}\""
if [ "$KEY_COUNT" -gt 1 ]; then
  echo "Multiple bootstrap epics under ${KEY} — ask user which to use" >&2
  exit 1
fi
if [ "$KEY_COUNT" -eq 1 ]; then
  EPIC_KEY=$FIRST_KEY
else
  collect_keys_from_jql "type = Epic AND summary = \"${EPIC_SUMMARY}\" AND parent is EMPTY"
  if [ "$KEY_COUNT" -gt 1 ]; then
    echo "Multiple orphan bootstrap epics — ask user which to use" >&2
    exit 1
  fi
  if [ "$KEY_COUNT" -eq 1 ]; then
    EPIC_KEY=$FIRST_KEY
    # Link orphan to Feature before creating tasks (see Set parent below)
  fi
fi
```

If `EPIC_KEY` is set from duplicate search, skip epic create below; run **Set
parent** if parent is not yet `"${KEY}"`, then verify before creating tasks.

**Create epic — create-then-parent is required** (skip if `EPIC_KEY` already set):

Jira rejects Epic create with `-P` when the parent is a Feature (HTTP 400:
`Issue '…' must be of type 'Epic'`). Create the epic **without** a parent, then
set the parent via `jira issue edit -P`. Use `</dev/null` on both commands so
jira-cli does not block on stdin in agent shells. **Never kill** an in-flight
create or edit and retry — wait for completion or poll Jira; re-search before
any retry.

```bash
if [ -z "${EPIC_KEY:-}" ]; then
  OUT=$(new_temp osac-jira-epic-out)
  add_temp "$OUT"
  ERR=$(new_temp osac-jira-epic-err)
  add_temp "$ERR"

  jira issue create -t Epic --project OSAC \
    -s "${EPIC_SUMMARY}" \
    -b "Documentation work gates for ${KEY}. These tasks track drafting, submitting, and merging planning documents — not implementation." \
    --label bootstrap --no-input --raw >"$OUT" 2>"$ERR" </dev/null

  EPIC_KEY=$(jq -r '.key // empty' "$OUT")
  require_osac_key "$EPIC_KEY" "epic" "$OUT" "$ERR"
fi
```

Allow up to 3 minutes for epic create to complete (typically seconds with `</dev/null`).

**Set parent to the Feature** (run when parent is not yet `"${KEY}"`):

```bash
EPIC_ERR=$(new_temp osac-jira-epic-err)
add_temp "$EPIC_ERR"
PARENT=$(jira issue view "${EPIC_KEY}" --raw | jq -r '.fields.parent.key // empty')
if [ "$PARENT" != "$KEY" ]; then
  jira issue edit "${EPIC_KEY}" -P "${KEY}" --no-input 2>>"$EPIC_ERR" </dev/null
fi
```

Allow up to 3 minutes for parent edit (smoke test: ~4s with `</dev/null`).

**Verify parent linkage** (re-check once after 30s if still empty — edit may lag):

```bash
PARENT=$(jira issue view "${EPIC_KEY}" --raw | jq -r '.fields.parent.key // empty')
if [ "$PARENT" != "$KEY" ]; then
  sleep 30
  PARENT=$(jira issue view "${EPIC_KEY}" --raw | jq -r '.fields.parent.key // empty')
fi
```

If `PARENT` is still not `"${KEY}"`, stop. Report Feature key, epic key, `$EPIC_ERR`,
and suggest manual fix: `jira issue edit "${EPIC_KEY}" -P "${KEY}" --no-input </dev/null`.
Do not create bootstrap tasks.

**Apply bootstrap metadata** (label + copied fix version when not backlog):

```bash
apply_bootstrap_epic_metadata "$EPIC_KEY" "$KEY" "$BOOTSTRAP_FIX_VERSION"
```

Run after parent verify succeeds — including when reusing an epic from duplicate search.

## Create Bootstrap Tasks

Create documentation gate tasks under the bootstrap epic. Line 1 of each body
matches Jira AC text; PRD and Design add a workflow hint on line 2. Every task
body includes `Feature: ${KEY}` on its own line. Do **not** reference
`/ux-design` or `/ui-design`.

| Summary | Labels | Body (lines in `$TASK_BODY`) | When |
|---------|--------|------------------------------|------|
| PRD | (none) | 1: Draft, submit, and merge the Product Requirements Document. 2: Use `/prd` workflow. 3: Feature: ${KEY} | Always |
| Design | (none) | 1: Draft, submit, and merge the technical Design / Enhancement Proposal. 2: Use `/design` workflow. 3: Feature: ${KEY} | Always |
| UX Design | `osac-ux` | 1: Draft, submit, and merge the UX specification. 2: Feature: ${KEY} | `REQUIRES_UI=yes` |
| UI Design | `osac-ui` | 1: Draft, submit, and merge the UI design document. 2: Feature: ${KEY} | `REQUIRES_UI=yes` |

Apply gate-task labels only on the task they describe — do **not** put `osac-ux`
on UI Design or `osac-ui` on UX Design. PRD and Design have no labels
(universal gates, not UX- or UI-specific work).

For each gate task, duplicate-check with exact summary (substitute task name in
JQL — summaries are literal: `PRD`, `Design`, `UX Design`, `UI Design`):

```bash
TASK_SUMMARY="PRD"   # or Design, UX Design, UI Design
collect_keys_from_jql "parent = ${EPIC_KEY} AND type = Task AND summary = \"${TASK_SUMMARY}\""
if [ "$KEY_COUNT" -gt 1 ]; then
  echo "Multiple tasks named ${TASK_SUMMARY} under epic — ask user" >&2
  exit 1
fi
if [ "$KEY_COUNT" -eq 1 ]; then
  # reuse FIRST_KEY as TASK_* for this summary; skip create
fi
```

Create tasks in order: **PRD → Design → UX Design → UI Design** (last two only
when `REQUIRES_UI=yes`). Reuse temps via `new_temp` each iteration.

Task create with `-P "${EPIC_KEY}"` is safe — Jira only rejects `-P` on **Epic
create** when the parent is a Feature; tasks under an epic accept `-P` normally.

```bash
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

jira issue create -t Task --project OSAC -s "PRD" \
  --template "$TASK_BODY" \
  -P "${EPIC_KEY}" --no-input --raw >"$OUT" 2>"$ERR" </dev/null

TASK_PRD=$(jq -r '.key // empty' "$OUT")
require_osac_key "$TASK_PRD" "task PRD" "$OUT" "$ERR"
```

Repeat for Design (change summary, body, and labels per the table); when
`REQUIRES_UI=yes`, repeat for UX Design and UI Design — example for UX Design:

```bash
cat >"$TASK_BODY" <<EOF
Draft, submit, and merge the UX specification.

Feature: ${KEY}
EOF

jira issue create -t Task --project OSAC -s "UX Design" \
  --template "$TASK_BODY" \
  -P "${EPIC_KEY}" --label osac-ux --no-input --raw >"$OUT" 2>"$ERR" </dev/null

TASK_UX=$(jq -r '.key // empty' "$OUT")
require_osac_key "$TASK_UX" "task UX Design" "$OUT" "$ERR"
```

For UI Design:

```bash
cat >"$TASK_BODY" <<EOF
Draft, submit, and merge the UI design document.

Feature: ${KEY}
EOF

jira issue create -t Task --project OSAC -s "UI Design" \
  --template "$TASK_BODY" \
  -P "${EPIC_KEY}" --label osac-ui --no-input --raw >"$OUT" 2>"$ERR" </dev/null

TASK_UI=$(jq -r '.key // empty' "$OUT")
require_osac_key "$TASK_UI" "task UI Design" "$OUT" "$ERR"
```

UX/UI task bodies omit the `/prd` or `/design` workflow line — see table above.

On any empty task key, stop and report Feature key, epic key, completed task
keys, plus `$ERR` and error JSON from `$OUT`.

## Error Handling

| Failure | Action |
|---------|--------|
| Invalid summary (JQL/shell unsafe chars, >255 chars) | Reject before confirm; ask user to revise |
| User declines confirm gate | Stop; no Jira creates |
| Empty `KEY` after Feature create | Stop; report `$ERR` and error JSON; do not bootstrap |
| Fix version edit failed after Feature create | Non-fatal; report manual `jira issue edit --fix-version …`; continue bootstrap |
| Bootstrap metadata failed (label or fix version copy) | Non-fatal; report manual edit commands; continue gate tasks |
| Empty `EPIC_KEY` after epic create | Stop; report Feature key and errors; do not create tasks |
| Epic parent edit slow | Wait up to 3 minutes; do not kill and retry |
| Epic parent ≠ Feature after 30s re-check | Stop; report keys + manual `jira issue edit -P … </dev/null>`; do not create tasks |
| Orphan epic reused | Run parent edit + verify before tasks |
| Empty task key mid-way | Stop; report Feature, epic, completed tasks, and errors |
| Duplicate epic/tasks found | Reuse existing keys; do not create again |
| Malformed Jira key after create | Stop; report `$ERR` and error JSON; do not proceed |
| Partial bootstrap (orphan Feature/epic) | Report all created keys; user may close/delete manually in Jira |

Before create, search Jira for an existing issue with the same summary. If a
slow create appears hung, wait for it to finish — do not kill and retry.

## Report

Output to user on success:

```
Feature created:

Jira:           https://redhat.atlassian.net/browse/<KEY>
Component:      <component>
Fix version:    <version> | backlog (unset)
Labels:         [osac-ux, osac-ui if UI work][, customer, customer:<name>] | none
Bootstrap epic: https://redhat.atlassian.net/browse/<EPIC_KEY>
Bootstrap label: bootstrap
Epic fix version: <copied from Feature | not set (backlog)>
Bootstrap tasks:
  - PRD:        <TASK_PRD>
  - Design:     <TASK_DESIGN>
  [- UX Design:  <TASK_UX>         (osac-ux)   UI work only]
  [- UI Design:  <TASK_UI>         (osac-ui)   UI work only]
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

## Notes

- OSAC project key: `OSAC`
- Customer-driven features: add `customer` and `customer:<name>` labels on the Feature only
- When `REQUIRES_UI=yes`: Feature gets `osac-ux` and `osac-ui`; both UX Design
  and UI Design tasks are created (`REQUIRES_UI` gates the full UX → UI track)
- UX Design task gets `osac-ux`; UI Design task gets `osac-ui`; PRD and Design
  have no labels; bootstrap epic gets `bootstrap` only
- Jira hierarchy: Feature → Bootstrap epic → gate tasks (PRD, Design, [UX Design, UI Design])
- Bootstrap epic: create without `-P`, then `jira issue edit -P` — Epic create with `-P` on a Feature parent returns HTTP 400; use `</dev/null` on all jira create/edit to avoid stdin hangs (jira-cli#948)
- Gate tasks track documentation milestones, not implementation work
- **Fix version:** Feature chooses at confirm gate; bootstrap epic copies when set;
  gate tasks never receive `fixVersion`
- Existing bootstrap epics predating this convention are not backfilled — only
  epics created going forward get the `bootstrap` label and copied `fixVersion`
- Temp files: source `tools/jira-safe-create.sh`; call `add_temp` in the parent shell after each `new_temp` — see `jira-task-management` Safe create pattern
- jira-cli handles markdown-to-ADF conversion automatically
