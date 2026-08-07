# Reusable bash patterns

**Read this file before any `jira issue create` or `jira issue edit`.**

Define once before any Jira create: source `tools/jira-safe-create.sh` (see
`jira-task-management` Safe create pattern), then define skill-specific helpers
below. Reference these from each create step instead of duplicating key
validation or `--plain` parsing.

## Source safe-create script

```bash
source "$(git rev-parse --show-toplevel)/tools/jira-safe-create.sh"
```

## Key validation and JQL helpers

```bash
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
# On jira-cli failure, returns non-zero — callers must stop before create/edit.
#
# jira-cli exits 1 for BOTH genuine failures (bad JQL, network/auth errors)
# AND a valid query that simply matches nothing ("No result found for given
# query…" on stderr) — verified against jira-cli v1.7.0. Treat the latter as
# a normal empty result, not a failure, or every first-time duplicate check
# (which by definition finds nothing) would incorrectly abort create.
list_keys_for_jql() {
  local jql=$1 out err rc
  out=$(new_temp osac-jira-list-out)
  add_temp "$out"
  err=$(new_temp osac-jira-list-err)
  add_temp "$err"
  jira issue list -q "$jql" --plain >"$out" 2>"$err"
  rc=$?
  if [ "$rc" -ne 0 ] && ! grep -qi "no result found" "$err"; then
    echo "Jira issue list failed for: ${jql}" >&2
    cat "$err" >&2
    return 1
  fi
  parse_plain_keys <"$out"
}

collect_keys_from_jql() {
  local jql=$1 out k
  FIRST_KEY=""
  KEY_COUNT=0
  out=$(new_temp osac-jira-keys-collect)
  add_temp "$out"
  # Redirect list_keys_for_jql output to a temp file — do not use command
  # substitution ($(…)), which runs in a subshell and prevents add_temp inside
  # list_keys_for_jql from registering with the parent shell's EXIT trap.
  if ! list_keys_for_jql "$jql" >"$out"; then
    return 1
  fi
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    KEY_COUNT=$((KEY_COUNT + 1))
    [ -n "$FIRST_KEY" ] || FIRST_KEY=$k
  done <"$out"
}
```

## Fix version helpers

```bash
# Portable version sort (GNU sort -V or Homebrew gsort). macOS BSD sort lacks -V.
version_sort_desc() {
  if sort -V </dev/null >/dev/null 2>&1; then
    sort -Vr
  elif command -v gsort >/dev/null 2>&1; then
    gsort -Vr
  else
    echo "version sort unavailable — install GNU coreutils (gsort)" >&2
    return 1
  fi
}

# Fetch OSAC fix-version candidates (exclude 0.0 — pre-team legacy bucket —
# and the literal "Backlog" release, which collides with this skill's own
# "backlog" sentinel for "no fix version"; see validate_fix_version).
# jira release list does NOT support useful --plain output; parse tab format.
# Columns: ID, NAME, RELEASED, DESCRIPTION
# Output: one version name per line, newest first.
# Returns non-zero on Jira or sort failure — not the same as an empty list.
list_fix_version_suggestions() {
  local out err
  out=$(new_temp osac-jira-release-out)
  add_temp "$out"
  err=$(new_temp osac-jira-release-err)
  add_temp "$err"
  if ! jira release list -p OSAC >"$out" 2>"$err"; then
    echo "Jira release list failed:" >&2
    cat "$err" >&2
    return 1
  fi
  awk -F'\t' 'NR>1 && $2 != "0.0" && tolower($2) != "backlog" && $3 == "false" {print $2}' <"$out" \
    | version_sort_desc
}

# Validate user-chosen version. Returns: backlog | <version> | invalid
# backlog only when user explicitly says backlog/none/skip (not empty string).
# Returns 1 with "lookup_failed" on stdout when release list fails.
validate_fix_version() {
  local trimmed choice list_out
  trimmed=$(printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  choice=$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')
  case "$choice" in
    backlog|none|skip) echo "backlog"; return 0 ;;
    '') echo "invalid"; return 0 ;;
  esac
  list_out=$(new_temp osac-jira-fixver-list)
  add_temp "$list_out"
  if ! list_fix_version_suggestions >"$list_out"; then
    echo "lookup_failed"
    return 1
  fi
  if grep -Fxq "$trimmed" <"$list_out"; then
    echo "$trimmed"
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
```

## Team helpers

Jira's `Team` field (`customfield_10001` in this Jira instance, schema
datatype `any`/`team`) has no working write path through `jira-cli` v1.7.0 —
`--custom Team=<value>` falls through to jira-cli's plain-string handling,
which Jira Cloud rejects for this field type (`jira-cli` issue
[#637](https://github.com/ankitpokhrel/jira-cli/issues/637) reports this
exact `customfield_10001` field returning a 400; the upstream fix,
[jira-cli#927](https://github.com/ankitpokhrel/jira-cli/pull/927), is still
open and unmerged). Team's write shape is also different from an ordinary
custom field: Jira expects the team's ID (a UUID), not its display name, and
neither `jira-cli` nor JQL can resolve a team name to its ID. This skill
sets Team with a direct REST call instead, following the same `curl -K -`
credential pattern `report-bug` already uses for attachment uploads (reads
the Jira username from `~/.config/.jira/.config.yml` and the token from
`$JIRA_API_TOKEN`, passed via stdin so neither appears in the process list).

```bash
# Hardcoded team name -> team ID (UUID), harvested read-only from existing
# OSAC issues' Team field (jira-cli/JQL cannot resolve names to IDs; Jira's
# Teams REST/GraphQL APIs need an org ID this skill doesn't have). Update
# this table manually when Jira teams are renamed or added — ask a Jira
# admin for the new team's ID. Indexed array (not associative) for bash 3.2
# compatibility, matching this skill's existing portability requirement.
TEAM_NAME_TO_ID=(
  "OSAC-Connectivity & Fabric:a63c4ba4-a73c-41ea-a397-0a4020253953"
  "OSAC-Core:ab57b451-a878-4901-aee7-6a0e40e6c594"
  "OSAC-Infrastructure:683a4065-b74b-4e79-b57e-effdea29b508"
  "OSAC-Storage:79daf97e-198e-43e4-b2a8-00925442bcd2"
  "OSAC-UI:b2085ca5-d82c-4751-801f-45c921840840"
  "OSAC-VMaaS:fb86f568-c9c8-4a18-9b55-7e270ac40278"
  "Osac-Caas:b29325e5-601a-4d53-b84b-0170920db548"
)

# List known team names, one per line, for prompting the user.
list_team_suggestions() {
  local entry
  for entry in "${TEAM_NAME_TO_ID[@]}"; do
    echo "${entry%%:*}"
  done
}

# Look up a team's ID by its exact canonical name. Returns 1 if not found.
team_id_for_name() {
  local name=$1 entry
  for entry in "${TEAM_NAME_TO_ID[@]}"; do
    if [ "${entry%%:*}" = "$name" ]; then
      echo "${entry#*:}"
      return 0
    fi
  done
  return 1
}

# Case-insensitively validate a raw user answer against TEAM_NAME_TO_ID.
# Echoes the canonical team name, or "invalid" (including for empty input).
# Unlike validate_fix_version, there is no "backlog"/skip sentinel — every
# Feature must have a Team (AC-1).
validate_team() {
  local trimmed choice entry
  trimmed=$(printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  choice=$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')
  for entry in "${TEAM_NAME_TO_ID[@]}"; do
    if [ "$(printf '%s' "${entry%%:*}" | tr '[:upper:]' '[:lower:]')" = "$choice" ]; then
      echo "${entry%%:*}"
      return 0
    fi
  done
  echo "invalid"
}

# Set the Team field via direct REST call — jira-cli has no write path for
# this field (see prose above). Non-fatal: reports the failure and a link
# to fix it manually, returns 1, does not exit. Caller passes a canonical
# name from TEAM_NAME_TO_ID (already validated via validate_team).
apply_team() {
  local key=$1 team_name=$2 team_id err out
  team_id=$(team_id_for_name "$team_name") || {
    echo "Unknown team '${team_name}' for ${key} — set manually in Jira UI" >&2
    return 1
  }
  err=$(new_temp osac-jira-team-err)
  add_temp "$err"
  out=$(new_temp osac-jira-team-out)
  add_temp "$out"
  if ! curl -s --fail-with-body --max-time 30 -K - -X PUT -H "Content-Type: application/json" \
    --data "{\"fields\":{\"customfield_10001\":\"${team_id}\"}}" \
    "https://redhat.atlassian.net/rest/api/3/issue/${key}" \
    >"$out" 2>"$err" <<EOF
user = "$(jira_login):${JIRA_API_TOKEN}"
EOF
  then
    echo "Team field edit failed for ${key} (${team_name}) — jira-cli has no write path for this field, so set it manually if the REST call above didn't succeed:" >&2
    echo "  https://redhat.atlassian.net/browse/${key}" >&2
    cat "$out" >&2
    cat "$err" >&2
    return 1
  fi
}
```

## Bootstrap epic metadata

```bash
# After bootstrap epic parent verified. Label at create; copy fix version and
# team here. Re-run safe on reuse: add label if missing; set fix version/team
# only when the epic has none. Caller passes "backlog" for fix_version when
# the Feature edit did not succeed, so a failed Feature update never results
# in a copied version on the epic. Team has no such sentinel (always passed).
#
# The epic's raw JSON is read once and used for both the fixVersion and Team
# checks below — fix_version's "backlog" case must not skip the Team copy,
# so the two checks run independently rather than one short-circuiting both.
apply_bootstrap_epic_metadata() {
  local epic_key=$1 feature_key=$2 fix_version=$3 team_name=$4
  local err
  err=$(new_temp osac-jira-bootstrap-meta-err)
  add_temp "$err"

  if ! jira issue edit "$epic_key" -l bootstrap --no-input 2>>"$err" </dev/null; then
    echo "Bootstrap label edit failed for ${epic_key} — set manually:" >&2
    echo "  jira issue edit ${epic_key} -l bootstrap --no-input </dev/null" >&2
    cat "$err" >&2
  fi

  local raw
  if ! raw=$(jira issue view "$epic_key" --raw 2>>"$err"); then
    echo "Could not read ${epic_key} for fix version/team check — set both manually if needed" >&2
    cat "$err" >&2
    return 0
  fi
  if ! jq -e . >/dev/null 2>&1 <<<"$raw"; then
    echo "Could not parse ${epic_key} JSON for fix version/team check — set both manually if needed" >&2
    return 0
  fi

  if [ "$fix_version" != "backlog" ]; then
    local epic_version_count
    epic_version_count=$(printf '%s' "$raw" | jq -r '[.fields.fixVersions[]?.name] | length')
    if [ "${epic_version_count:-0}" -eq 0 ]; then
      if ! jira issue edit "$epic_key" --fix-version "$fix_version" --no-input 2>>"$err" </dev/null; then
        echo "Bootstrap fix version copy failed for ${epic_key} (${fix_version}) — set manually:" >&2
        echo "  jira issue edit ${epic_key} --fix-version \"${fix_version}\" --no-input </dev/null" >&2
        cat "$err" >&2
      fi
    fi
  fi

  local epic_team
  epic_team=$(printf '%s' "$raw" | jq -r '.fields.customfield_10001.name // empty')
  if [ -z "$epic_team" ]; then
    apply_team "$epic_key" "$team_name"
  fi
}
```

## Safe-create rules

Safe-create rules (all create/edit steps):
- Append **`</dev/null`** to every `jira issue create` and `jira issue edit` — jira-cli
  blocks on stdin in non-TTY shells ([jira-cli#948](https://github.com/ankitpokhrel/jira-cli/issues/948))
- Run `jira issue create` directly — not inside `$(...)`
- Write bodies to `--template` files; capture stdout/stderr to temps
- Allow up to 3 minutes per operation; **never kill** and retry
- Before retry, re-search Jira — duplicate creates are worse than slow creates
- If stdout is slow, poll Jira (`jira issue view`) instead of killing the in-flight command

## Example create pattern

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

## Duplicate search pattern

```bash
# Match the titled summary AND the bare legacy gate name (pre-dating the
# "<gate> - ${FEATURE_SUMMARY}" convention) so epics bootstrapped before the
# rename don't get a duplicate gate task created alongside the old one.
collect_keys_from_jql "parent = ${EPIC_KEY} AND type = Task AND (summary = \"PRD - ${FEATURE_SUMMARY}\" OR summary = \"PRD\")" \
  || { echo "Duplicate-check lookup failed — stopping before create" >&2; exit 1; }
# KEY_COUNT == 1 → reuse FIRST_KEY; KEY_COUNT > 1 → ask user; 0 → create
```

**Always check the return value.** `collect_keys_from_jql` sets `KEY_COUNT=0`
before running the lookup, so a failed `jira issue list` looks identical to
"no duplicate found" if the caller doesn't check the exit status — that would
silently defeat the failure propagation above and risk creating a duplicate
issue on a transient Jira error.
