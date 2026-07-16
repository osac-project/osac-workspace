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
| Affects version | No | Detect from epic's fixVersion, confirm with user |
| Label | No | `OSAC` |
| Attachments | No | Logs, screenshots, or config files from conversation context |
| Assignee | No | Unassigned — only assign if user specifies |

## Pre-Creation Check

Describe from the user's perspective — what they did (CLI commands, API calls, UI actions), what they expected to happen, and what they saw happening (error messages, wrong behavior, missing data). Use product concepts (cluster, tenant, token), not code concepts (function names, file paths, database columns).

Before creating the ticket, verify you can answer these with user-facing information:

1. What user action triggers the bug?
2. What does the user see that is wrong?
3. What should the user see instead?

If you don't have enough information to answer these, ask the user: "I need more detail to file this bug with user-facing summary, repro steps, and expected vs actual behavior. Can you describe what you did, what you expected, and what went wrong?"

Do not create the ticket until you can fill the template.

## Resolve Affects-Version

Once the epic is known, detect the version before confirming inputs with the user:

1. If the user already specified a version, use it
2. If an epic is known, read `fixVersions` from the epic:
   ```bash
   jira issue view <EPIC> --raw 2>/dev/null | jq -r '.fields.fixVersions[0].name // empty'
   ```
   - **Found** — include in the confirmation: "Epic targets **X.Y**, use as affects-version?"
   - **Not found** — ask: "No version on the epic. Set affects-version? Available: `0.0`, `0.1`, `0.2`, `0.3` (or skip)"
3. If no epic — ask the user if they want to set one, listing available versions
4. If user declines or skips — omit `--affects-version` from the create command

## Formatting Rules

`jira-cli` converts the body to Atlassian Document Format (ADF). Use **Markdown only** — Jira wiki markup (`*bold*`, `{{code}}`, `{code}`, `[text|url]`) renders incorrectly.

- `**bold**` for section headers
- `` `code` `` for inline code
- `- item` for bullet lists
- `[text](url)` for links
- ` ```lang ` fenced blocks for code snippets

## Create the Bug

Use the safe create pattern from `jira-task-management` — write the body to a template file, run create directly (not inside `$(...)`), then parse the key from the output file:

```bash
# 1. Write body to a temp file (see jira-task-management for why)
cat > /tmp/bug-body.md <<'EOF'
**Description of the problem:**

<describe the problem>

**How reproducible:**

<Always / Sometimes / Rare>

**Steps to reproduce:**

- <step>

**Expected result:**

<what the user expected to see or experience>

**Actual result:**

<what the user actually sees (error messages, wrong output, missing data)>

---

_This bug was reported with AI assistance. Review for accuracy_
EOF

# 2. Create directly; allow up to 3 minutes — do not kill and retry
jira issue create -t Bug --project OSAC \
  --summary "<concise bug title>" \
  --template /tmp/bug-body.md \
  --label OSAC \
  --affects-version "<version>" \
  --no-input --raw > /tmp/jira-create.out

# 3. Parse key from output file
KEY=$(jq -r '.key' /tmp/jira-create.out)
```

Omit `--affects-version` if no version was resolved.

**Key extraction notes:**
- Use `--raw` and parse with `jq -r '.key'` from the output file — not from a command substitution around `jira issue create`.
- Do **not** use `grep -oP` on the text output — it can match multiple keys in the URL or fail silently.

### Link to epic

```bash
jira issue edit $KEY -P <EPIC-KEY> --no-input
```

If user specified an assignee (no `--no-input` flag — `assign` does not support it):
```bash
jira issue assign $KEY <assignee>
```

### Attach files

If logs, screenshots, or other files came up during the conversation, list them and ask the user which ones to attach. Ask if there is anything else they want to add.

**Do not attach files containing sensitive data (credentials, tokens, keys, secrets, passwords). Read the file content before attaching. If in doubt, ask the user.**

```bash
curl -s --fail -K - \
  -H "X-Atlassian-Token: no-check" \
  -F "file=@<path>" \
  "https://redhat.atlassian.net/rest/api/3/issue/$KEY/attachments" <<EOF
user = "$(grep '^login:' ~/.config/.jira/.config.yml | awk '{print $2}'):${JIRA_API_TOKEN}"
EOF
```

If the upload fails (missing `$JIRA_API_TOKEN`, auth error, or network issue), skip it and tell the user to attach files manually via the Jira link.

## Report

Output to user:

```
Bug reported:

Jira:    https://redhat.atlassian.net/browse/<KEY>
Epic:    <EPIC-KEY>
Version: <version or "not set">
Status:  New
```
