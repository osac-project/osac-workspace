# Create bootstrap epic

**Read this file after Feature create** (fix version set when not backlog; assign if requested).

**Requires [bash-patterns.md](bash-patterns.md) sourced first** — helpers (`collect_keys_from_jql`,
`require_osac_key`, `new_temp`, `apply_bootstrap_epic_metadata`) must already be defined.

After the Feature is created, fix version is set (when not backlog), and
optionally assigned, create a bootstrap epic under the Feature. Use
`jira issue create -t Epic` — **not** `jira epic create`
(that subcommand has no parent flag).

Set `EPIC_SUMMARY="${FEATURE_SUMMARY} - Bootstrap"` for searches and create.

## Duplicate check

Exact summary, scoped to parent; also check **orphan** epics (no parent) from a
failed create-then-parent run:

```bash
collect_keys_from_jql "parent = ${KEY} AND type = Epic AND summary = \"${EPIC_SUMMARY}\"" \
  || { echo "Bootstrap epic duplicate-check failed — stopping before create" >&2; exit 1; }
if [ "$KEY_COUNT" -gt 1 ]; then
  echo "Multiple bootstrap epics under ${KEY} — ask user which to use" >&2
  exit 1
fi
if [ "$KEY_COUNT" -eq 1 ]; then
  EPIC_KEY=$FIRST_KEY
else
  collect_keys_from_jql "project = OSAC AND type = Epic AND summary = \"${EPIC_SUMMARY}\" AND parent is EMPTY" \
    || { echo "Orphan epic duplicate-check failed — stopping before create" >&2; exit 1; }
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

A failed lookup must stop the workflow here — falling through with `KEY_COUNT=0`
would look identical to "no duplicate found" and risk creating a duplicate epic.

If `EPIC_KEY` is set from duplicate search, skip epic create below; run **Set
parent** if parent is not yet `"${KEY}"`, then verify before creating tasks.

## Create epic

Create-then-parent is required (skip if `EPIC_KEY` already set).

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
    --component "${COMPONENT}" \
    --label bootstrap --no-input --raw >"$OUT" 2>"$ERR" </dev/null

  EPIC_KEY=$(jq -r '.key // empty' "$OUT")
  require_osac_key "$EPIC_KEY" "epic" "$OUT" "$ERR"
fi
```

Allow up to 3 minutes for epic create to complete (typically seconds with `</dev/null`).

## Set parent

Run when parent is not yet `"${KEY}"`:

```bash
EPIC_ERR=$(new_temp osac-jira-epic-err)
add_temp "$EPIC_ERR"
EPIC_VIEW=$(new_temp osac-jira-epic-view)
add_temp "$EPIC_VIEW"
if ! jira issue view "${EPIC_KEY}" --raw >"$EPIC_VIEW" 2>>"$EPIC_ERR"; then
  echo "Could not read ${EPIC_KEY} for parent check — stopping before edit" >&2
  cat "$EPIC_ERR" >&2
  exit 1
fi
if ! jq -e . <"$EPIC_VIEW" >/dev/null 2>>"$EPIC_ERR"; then
  echo "Could not parse ${EPIC_KEY} JSON — stopping before edit" >&2
  exit 1
fi
PARENT=$(jq -r '.fields.parent.key // empty' <"$EPIC_VIEW")
if [ "$PARENT" != "$KEY" ]; then
  if ! jira issue edit "${EPIC_KEY}" -P "${KEY}" --no-input 2>>"$EPIC_ERR" </dev/null; then
    echo "Parent edit failed for ${EPIC_KEY} — stopping" >&2
    cat "$EPIC_ERR" >&2
    exit 1
  fi
fi
```

Allow up to 3 minutes for parent edit (smoke test: ~4s with `</dev/null`).

## Verify parent linkage

Re-check once after 30s if still empty — edit may lag:

```bash
if ! jira issue view "${EPIC_KEY}" --raw >"$EPIC_VIEW" 2>>"$EPIC_ERR"; then
  echo "Could not re-read ${EPIC_KEY} for parent verify — stopping" >&2
  cat "$EPIC_ERR" >&2
  exit 1
fi
if ! jq -e . <"$EPIC_VIEW" >/dev/null 2>>"$EPIC_ERR"; then
  echo "Could not parse ${EPIC_KEY} JSON — stopping" >&2
  exit 1
fi
PARENT=$(jq -r '.fields.parent.key // empty' <"$EPIC_VIEW")
if [ "$PARENT" != "$KEY" ]; then
  sleep 30
  if ! jira issue view "${EPIC_KEY}" --raw >"$EPIC_VIEW" 2>>"$EPIC_ERR"; then
    echo "Could not re-read ${EPIC_KEY} after parent-edit wait — stopping" >&2
    cat "$EPIC_ERR" >&2
    exit 1
  fi
  if ! jq -e . <"$EPIC_VIEW" >/dev/null 2>>"$EPIC_ERR"; then
    echo "Could not parse ${EPIC_KEY} JSON after wait — stopping" >&2
    exit 1
  fi
  PARENT=$(jq -r '.fields.parent.key // empty' <"$EPIC_VIEW")
fi
```

If `PARENT` is still not `"${KEY}"`, stop. Report Feature key, epic key, `$EPIC_ERR`,
and suggest manual fix: `jira issue edit "${EPIC_KEY}" -P "${KEY}" --no-input </dev/null`.
Do not create bootstrap tasks.

## Apply bootstrap metadata

Label + copied fix version (when not backlog) + copied team (when the epic
doesn't already have one):

```bash
apply_bootstrap_epic_metadata "$EPIC_KEY" "$KEY" "$BOOTSTRAP_FIX_VERSION" "$TEAM"
```

Run after parent verify succeeds — including when reusing an epic from duplicate search.
