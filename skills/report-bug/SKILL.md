---
name: report-bug
description: Report a bug in Jira without fixing it — creates a Bug ticket with proper description, links it to an epic, and assigns it. Use when the user says 'report a bug', 'file a bug', 'log a bug', 'open a bug ticket', or wants to track a bug without immediately writing a fix.
---

# Report Bug

Create a Jira Bug ticket with a structured description, link it to an epic, and assign it.

## When to Use

- User wants to track a bug without fixing it right now
- User says "report a bug", "file a bug", "log this bug", "open a ticket for this"
- A bug is discovered but the fix is deferred or assigned to someone else

## Gather Inputs

Collect from conversation context. Ask only if truly ambiguous:

| Input | Required | Default |
|-------|----------|---------|
| Bug summary | Yes | From conversation context |
| User-visible symptoms | Yes | From conversation context |
| Steps to reproduce | If known | From conversation context |
| Epic key | If ambiguous | Ask user — e.g. "Which epic should I link this to?" |
| Affects version | No | Suggest from parent Feature's fixVersion (planning hint); user confirms where the bug was found |
| Attachments | No | Logs, screenshots, or config files from conversation context |
| Assignee | No | Unassigned — only assign if user specifies |

**Version convention:** `affectsVersion` on bugs records **where the bug was found**.
Feature `fixVersion` is a planning hint only — never copy it automatically without
user confirmation. Walk to the Feature ancestor for the suggestion — do not read
epic `fixVersion` directly (bootstrap epics mirror the Feature but Feature is the
source of truth).

## Pre-Creation Check

Describe from the user's perspective — what they did (CLI commands, API calls, UI actions), what they expected to happen, and what they saw happening (error messages, wrong behavior, missing data). Use product concepts (cluster, tenant, token), not code concepts (function names, file paths, database columns).

Before creating the ticket, verify you can answer these with user-facing information:

1. What user action triggers the bug?
2. What does the user see that is wrong?
3. What should the user see instead?

If you don't have enough information to answer these, ask the user: "I need more detail to file this bug with user-facing summary, repro steps, and expected vs actual behavior. Can you describe what you did, what you expected, and what went wrong?"

Do not create the ticket until you can fill the template.

## Resolve Affects-Version

Resolve a **suggested** affects-version before the confirm gate. Never pass
`--affects-version` without explicit user approval.

1. If the user already specified a version, use it (`AFFECTS_VERSION_SOURCE=user`)
2. If a parent epic or task is known, walk to the Feature ancestor and read its
   `fixVersion` (planning hint only — not automatic truth about where the bug
   was found):
   ```bash
   suggest_affects_version_from_parent <PARENT-KEY>
   ```
   - **Single fixVersion on Feature** — ask: "Feature **OSAC-XXXX** targets **X.Y**
     (planning). Use **X.Y** as affects-version — where the bug was found?"
   - **No Feature ancestor, no fixVersion, or multiple fixVersions on Feature** —
     list options from `list_fix_version_suggestions` (same parser as `osac-feature`;
     excludes `0.0`) and ask the user to pick or skip
3. If no parent epic — ask whether to set affects-version, listing suggestions
   from `list_fix_version_suggestions`
4. If user declines or skips — omit `--affects-version` (`AFFECTS_VERSION_SOURCE=none`)

Store the resolved value in `AFFECTS_VERSION` (empty when skipped) and
`AFFECTS_VERSION_SOURCE` (`feature`, `release-list`, `user`, or `none`).

## Reusable bash patterns

Requires **bash or zsh** on macOS or Linux. Portable constructs only.

```bash
MAX_PARENT_DEPTH=10

# Same parser as osac-feature — jira release list has no useful --plain output.
list_fix_version_suggestions() {
  jira release list -p OSAC 2>/dev/null \
    | awk -F'\t' 'NR>1 && $2 != "0.0" && $3 == "false" {print $2}' \
    | sort -Vr
}

# Walk parent chain from START_KEY; print Feature key or empty.
find_feature_ancestor() {
  local current=$1 depth=0
  while [ -n "$current" ] && [ "$depth" -lt "$MAX_PARENT_DEPTH" ]; do
    local raw type parent
    raw=$(jira issue view "$current" --raw 2>/dev/null) || break
    type=$(printf '%s' "$raw" | jq -r '.fields.issuetype.name // empty')
    if [ "$type" = "Feature" ]; then
      printf '%s' "$current"
      return 0
    fi
    parent=$(printf '%s' "$raw" | jq -r '.fields.parent.key // empty')
    [ -z "$parent" ] || [ "$parent" = "$current" ] && break
    current=$parent
    depth=$((depth + 1))
  done
  return 1
}

# Suggested affects-version from Feature fixVersion (planning hint only).
# If multiple fixVersions on Feature, return empty — caller must ask user.
suggest_affects_version_from_parent() {
  local parent_key=$1 feature_key count
  feature_key=$(find_feature_ancestor "$parent_key") || return 1
  count=$(jira issue view "$feature_key" --raw 2>/dev/null \
    | jq -r '[.fields.fixVersions[]?.name] | length')
  [ "${count:-0}" -eq 1 ] || return 1
  jira issue view "$feature_key" --raw 2>/dev/null \
    | jq -r '.fields.fixVersions[0].name // empty'
}
```

## Confirm Before Creating

**Do not call `jira issue create` until the user confirms.**

Present a summary and wait for explicit approval:

```text
Ready to report bug in Jira:

  Summary:         <bug summary>
  Epic:            <EPIC-KEY or none>
  Affects version: <version or not set> [<feature|release-list|user|none>]
  Assignee:        <name or unassigned>

Proceed? (yes/no)
```

Only continue when the user answers yes.

## Formatting Rules

`jira-cli` converts the body to Atlassian Document Format (ADF). Use **Markdown only** — Jira wiki markup (`*bold*`, `{{code}}`, `{code}`, `[text|url]`) renders incorrectly.

- `**bold**` for section headers
- `` `code` `` for inline code
- `- item` for bullet lists
- `[text](url)` for links
- ` ```lang ` fenced blocks for code snippets

## Create the Bug

Use the safe create pattern in `jira-task-management` — source `tools/jira-safe-create.sh`, write the body to a temp file, run create directly (not inside `$(...)`), capture stdout/stderr separately:

```bash
source "$(git rev-parse --show-toplevel)/tools/jira-safe-create.sh"

BODY=$(new_temp osac-bug-body)
add_temp "$BODY"
OUT=$(new_temp osac-jira-out)
add_temp "$OUT"
ERR=$(new_temp osac-jira-err)
add_temp "$ERR"

cat >"$BODY" <<'EOF'
**Description of the problem:**

<describe the problem>

**Root cause:**

<the underlying technical reason, if known. If the cause is unknown, write "Unknown / under investigation" — do not put symptoms here; keep those in Description or Actual result.>

**How reproducible:**

<Always / Sometimes / Rare>

**Steps to reproduce:**

1. <create prerequisite resources — show the exact osac/oc command or YAML manifest>
2. <trigger the bug — show the exact command>
3. <observe the failure — show the verification command, e.g. oc get/describe/logs>

**Expected result:**

<what the user expected to see or experience — include expected command output if helpful>

**Actual result:**

<what the user actually sees (error messages, wrong output, missing data) — include actual command output showing the error>

**Environment:**

- Cluster: <cluster type or sanitized identifier — avoid raw internal hostnames unless the user approves>
- OCP version: <version if known>
- Relevant component versions: <e.g. CNV, OVN-K>

---

_This bug was reported with AI assistance. Review for accuracy_
EOF

AFFECTS_VERSION_ARGS=()
[ -n "${AFFECTS_VERSION:-}" ] && AFFECTS_VERSION_ARGS=(--affects-version "$AFFECTS_VERSION")

jira issue create -t Bug --project OSAC \
  --summary "<concise bug title>" \
  --template "$BODY" \
  "${AFFECTS_VERSION_ARGS[@]}" \
  --no-input --raw >"$OUT" 2>"$ERR" </dev/null

KEY=$(jq -r '.key // empty' "$OUT")
if [ -z "$KEY" ]; then
  cat "$ERR" >&2
  # Stop here — report the failure to the user and do not proceed with
  # epic linking, attachments, or diagnostic comments.
fi
```

`AFFECTS_VERSION_ARGS` is empty when no version was resolved (user declined or
skipped), so `--affects-version` is omitted automatically — never pass a literal
placeholder or empty value.

**Key extraction notes:**
- Use `--raw` with stdout/stderr temps; parse with `jq -r '.key // empty' "$OUT"` — not from a command substitution around `jira issue create`.
- Do **not** wrap create in `$(...)` or hide stderr with `2>/dev/null`.
- Do **not** use `grep -oP` on the text output — it can match multiple keys in the URL or fail silently.

### Link to epic

```bash
jira issue edit $KEY -P <EPIC-KEY> --no-input </dev/null
```

If user specified an assignee (no `--no-input` flag — `assign` does not support it):
```bash
jira issue assign $KEY <assignee>
```

### Attach files

If logs, screenshots, or other files came up during the conversation, list them and ask the user which ones to attach. Ask if there is anything else they want to add.

**Do not attach files containing sensitive data (credentials, tokens, keys, secrets, passwords, API keys, PII, or internal hostnames). Read the file content before attaching. If in doubt, ask the user.**

```bash
curl -s --fail -K - \
  -H "X-Atlassian-Token: no-check" \
  -F "file=@<path>" \
  "https://redhat.atlassian.net/rest/api/3/issue/$KEY/attachments" <<EOF
user = "$(grep '^login:' ~/.config/.jira/.config.yml | awk '{print $2}'):${JIRA_API_TOKEN}"
EOF
```

If the upload fails (missing `$JIRA_API_TOKEN`, auth error, or network issue), skip it and tell the user to attach files manually via the Jira link.

### Adding diagnostic output as a comment

If diagnostic output (command output, logs, resource descriptions) was gathered during the conversation, add it as a comment on the ticket. Every output block must be preceded by the command that produced it, with sensitive argument values redacted — never dump output without identifying the command. If no diagnostic output was collected, skip this section.

Before posting, review and redact both each command and its output for secrets, credentials, tokens, API keys, PII, and internal hostnames. Replace sensitive values with `<REDACTED>` while preserving the command shape. If either cannot be safely sanitized, skip the comment entirely and ask the user to add diagnostics manually via the Jira link.

Present the diagnostic comment content to the user and wait for explicit approval before posting. If the user declines, skip the comment.

````bash
DIAG_BODY=$(new_temp osac-diag-comment)
add_temp "$DIAG_BODY"
cat >"$DIAG_BODY" <<'DIAGEOF'
## Diagnostic Output

### <command 1, e.g.: oc describe pod -n namespace pod-name>
```text
<output with sensitive data redacted>
```

### <command 2, e.g.: oc get events -n namespace --sort-by='.lastTimestamp'>
```text
<output with sensitive data redacted>
```
DIAGEOF

jira issue comment add $KEY --template "$DIAG_BODY" </dev/null
````

If the comment fails (auth error, network issue), skip it and tell the user to add diagnostics manually via the Jira link.

## Report

Output to user:

```
Bug reported:

Jira:              https://redhat.atlassian.net/browse/<KEY>
Epic:              <EPIC-KEY>
Affects version:   <version or "not set">
Version source:    <feature | release-list | user | none>
Status:            New
```
