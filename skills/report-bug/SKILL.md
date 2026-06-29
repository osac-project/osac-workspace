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
| Description / root cause | Yes | From conversation context or investigation |
| Steps to reproduce | If known | From conversation context |
| Epic key | If ambiguous | Ask user — e.g. "Which epic should I link this to?" |
| Affects version | No | Detect from epic's fixVersion, confirm with user |
| Label | No | `OSAC` |
| Assignee | No | Unassigned — only assign if user specifies |

## Resolve Affects-Version

Once the epic is known, detect the version before confirming inputs with the user:

1. If the user already specified a version, use it
2. If an epic is known, try to detect from its `fixVersions`:
   ```bash
   jira issue view <EPIC> --raw 2>/dev/null | jq -r '.fields.fixVersions[0].name // empty'
   ```
   - **Found** — include in the confirmation: "Epic targets **X.Y**, use as affects-version?"
   - **Not found** — ask: "No version on the epic. Set affects-version? Available: `0.0`, `0.1`, `0.2`, `0.3` (or skip)"
3. If no epic — ask the user if they want to set one, listing available versions
4. If user declines or skips — omit `--affects-version` from the create command

## Create the Bug

```bash
KEY=$(jira issue create -t Bug --project OSAC \
  --summary "<concise bug title>" \
  --body "**Description of the problem:**

<what is broken>

**How reproducible:**

<Always / Sometimes / Rare>

**Steps to reproduce:**

1. <step>

**Expected result:**

<what should happen>

**Actual result:**

<what actually happens>" \
  --label OSAC \
  --affects-version "<version>" \
  --no-input --raw | jq -r '.key')
```

Omit `--affects-version` if no version was resolved.

**Key extraction notes:**
- Use `--raw` to get JSON output on stdout, then `jq -r '.key'` to extract the issue key reliably.
- Do **not** use `grep -oP` on the text output — it can match multiple keys in the URL or fail silently.

### Link to epic

```bash
jira issue edit $KEY -P <EPIC-KEY> --no-input
```

If user specified an assignee (no `--no-input` flag — `assign` does not support it):
```bash
jira issue assign $KEY <assignee>
```

## Report

Output to user:

```
Bug reported:

Jira:    https://redhat.atlassian.net/browse/<KEY>
Epic:    <EPIC-KEY>
Version: <version or "not set">
Status:  New
```
