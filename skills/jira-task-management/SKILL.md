---
name: jira-task-management
description: Manage Jira issues on Red Hat Jira (redhat.atlassian.net) using jira-cli. Use this skill whenever the user mentions Jira tickets, issues, bugs, tasks, epics, sprints, or wants to create/update/search work items. Also use when the user references issue keys like OSAC-*, NVIDIA-*, RHEL-*, asks about task status, or wants to track work.
metadata:
  version: "0.1.0"
---

# Jira Task Management

Manage issues on Red Hat Jira (`redhat.atlassian.net`) via `jira-cli`. The tool is pre-configured with bearer token auth for the OSAC project.

## Setup

- **Binary:** `jira` (installed via `go install github.com/ankitpokhrel/jira-cli/cmd/jira@latest`)
- **Config:** `~/.config/.jira/.config.yml` — initialized with `jira init --installation cloud --server https://redhat.atlassian.net --auth-type bearer`
- **Auth:** Bearer token in `~/.netrc` (`machine redhat.atlassian.net login <user> password <token>`)
- **Token generation:** https://id.atlassian.com/manage-profile/security/api-tokens
- **Default project:** OSAC
- **Jira URL pattern:** `https://redhat.atlassian.net/browse/<KEY>`

## CLI rules

- **`--comments` requires a count** — e.g. `jira issue view OSAC-123 --plain --comments 10`. Omitting the number errors with "flag needs an argument".
- **`jira-cli` prepends `project="OSAC"` to `-q`/`--jql` queries** — prefer `-q` in examples (`--jql` is equivalent). Within OSAC, use either normally (project is auto-prepended). For cross-project search, start with `project IS NOT EMPTY AND ...`. For another project, start with `project = OTHERKEY AND ...`. Never put `ORDER BY` in the query (jira-cli appends its own).
- **Prefer filter flags** (`-r`, `-t`, `-a`, `-s`) over embedding the same filters in JQL when possible — jira-cli appends them cleanly.

## Before Creating Issues

When the user asks to create a Task or Bug:

1. **Epic link** — Link to an epic via `-P <EPIC-KEY>` only when the user specifies one or the epic is obvious from context. If unclear, **omit `-P`** and ask later rather than guessing.

2. **Labels** — Add labels only when the user requests them or a domain skill specifies them (e.g. `bootstrap` on bootstrap epics via `osac-feature`). Do not default to the legacy `OSAC` label.

Do not set priority — it's not relevant for this project.

### Preventing duplicate creates (CRITICAL)

A slow `jira issue create` can look hung while the API call is still in flight. **Never kill and retry** — that pattern created duplicate tickets (e.g. OSAC-1619 + OSAC-1620).

**Before create** — search for an existing issue:

```bash
jira issue list -q 'summary ~ "exact or distinctive summary phrase"' --plain
```

**Safe create pattern** — use per-run temp files with cleanup, run create directly (not inside `$(...)`), capture stderr (never `2>/dev/null`), allow up to 3 minutes:

```bash
# Load shared temp helpers (from osac-workspace root)
source "$(git rev-parse --show-toplevel)/tools/jira-safe-create.sh"

# Single create — write body, capture stdout and stderr separately
# Register each path in the parent shell (add_temp inside $(...) runs in a subshell)
BODY=$(new_temp osac-jira-body)
add_temp "$BODY"
OUT=$(new_temp osac-jira-out)
add_temp "$OUT"
ERR=$(new_temp osac-jira-err)
add_temp "$ERR"
# Write description to $BODY (heredoc or editor) — do not inline large bodies in --body

jira issue create -tTask -s "Summary" \
  --template "$BODY" \
  --no-input --raw >"$OUT" 2>"$ERR"

KEY=$(jq -r '.key // empty' "$OUT")
# On empty key or failure: cat "$ERR" >&2 — do not hide errors with 2>/dev/null
```

Helpers live in `tools/jira-safe-create.sh` — child skills (`osac-feature`, `report-bug`, etc.) should source that script instead of copying the functions. Multi-step flows call `new_temp` for each create step and `add_temp` in the parent shell after each assignment. Key-validation helpers belong in those child skills, not here.

**Use the safe create pattern above for every issue create.** Do not use command substitution or kill a create mid-flight:

**Never do this:**
- `KEY=$(jira issue create ... --body "$(cat <<'EOF' ... EOF)" 2>/dev/null | jq -r '.key')` — no stdout until done; stderr hidden; looks hung for minutes
- `KEY=$(jira issue create ...)` — same problem when create is wrapped in command substitution
- Kill a running create and immediately retry
- Retry based only on a search that ran seconds earlier (Jira index lag)

**If create appears slow or was interrupted:**
1. **Do not retry yet** — wait for the original command to finish or confirm the process exited
2. Re-search with a tight window: `jira issue list -q 'summary ~ "..." AND created >= -1h' --plain`
3. If a match exists, use that key — do not create again
4. Only create when search confirms zero matches

## Command Reference

`--plain` is supported on **read commands** (view, list, epic list, sprint list) for clean output. `--no-input` is needed on **create and edit only** to skip interactive prompts — do **not** use `--no-input` with move, assign, comment, or link (they don't support it and will error). `--plain` is also **not supported** on create, edit, move, assign, or comment — use `--raw` on create if you need JSON output.

**`jira-cli` does NOT support `--json`.** Never use `--json` — it is not a valid flag on any command. Use `--plain` for readable output or `--raw` (on create only) for JSON.

### View

```bash
jira issue view <KEY> --plain                    # View issue details
jira issue view <KEY> --plain --comments 100     # Include comments (count required — see CLI rules)
```

### Search

`jira-cli` search behavior is documented in **CLI rules** above. Examples:

```bash
# Within OSAC (project auto-prepended)
jira issue list -q 'status = "In Progress"' --plain
jira issue list -q 'updated >= -7d' --plain
jira issue list -q 'assignee = currentUser() AND status not in (Closed, Done)' --plain

# Across ALL projects
jira issue list -q 'project IS NOT EMPTY AND type = Epic AND text ~ "search term"' -r "$(jira me)" --plain

# Specific other project
jira issue list -q 'project = CNF AND type = Epic' --plain

# Text search (scoped to default project)
jira issue list "search text" --plain

# Pagination
jira issue list -q '...' --paginate 50 --plain
```

JQL tips: String values with spaces need double quotes inside single quotes — `'status = "In Progress"'`. Field names with spaces need double quotes too — `'"Epic Link" = OSAC-37'`.

### Epics

```bash
jira epic list <EPIC-KEY> --plain                # List issues in epic
jira epic create -s "Title" -b "Description"    # Create epic
jira epic add <EPIC-KEY> <ISSUE-1> <ISSUE-2>     # Add issues to epic (max 50)
jira epic remove <ISSUE-KEY>                     # Remove from epic

# Filter epic contents with JQL
jira issue list --jql '"Epic Link" = <EPIC-KEY> AND status != Closed' --plain
jira issue list --jql '"Epic Link" = <EPIC-KEY> AND assignee is EMPTY' --plain
```

### Create

```bash
# Task (with epic when known)
jira issue create -tTask -s "Summary" -b "Description" \
  -P <EPIC-KEY> -a <assignee> --no-input

# Task (without epic — omit -P when epic is unclear; add later via jira issue edit -P)
jira issue create -tTask -s "Summary" -b "Description" \
  --no-input

# Bug — use the structured description template
jira issue create -tBug -s "Bug title" \
  -b $'**Description of the problem:**\n\n<describe>\n\n**How reproducible:**\n\n<rate>\n\n**Steps to reproduce:**\n\n1. <step>\n\n**Expected result:**\n\n<expected>\n\n**Actual result:**\n\n<actual>' \
  -P <EPIC-KEY> --no-input

# Story
jira issue create -tStory -s "Title" -b "Description" \
  -P <EPIC-KEY> --no-input

# Sub-task (parent is the task, not epic)
jira issue create -tSub-task -s "Title" -P <PARENT-KEY> --no-input

# From file or stdin
jira issue create -tTask -s "Summary" --template /path/to/desc.md --no-input
echo "Description" | jira issue create -tTask -s "Summary" --no-input

# JSON output
jira issue create -tTask -s "Summary" -b "Body" --no-input --raw
```

Issue types: Bug, Task, Story, Epic, Sub-task, Spike, Risk

### Edit

```bash
jira issue edit <KEY> -s "New summary" --no-input          # Summary
jira issue edit <KEY> -b "New description" --no-input      # Description
jira issue edit <KEY> -a "username" --no-input              # Assignee
jira issue edit <KEY> -P <EPIC-KEY> --no-input              # Re-parent to epic
jira issue edit <KEY> -l newlabel --no-input                # Add label
jira issue edit <KEY> --label -oldlabel --no-input          # Remove label (- prefix)
jira issue edit <KEY> -y Critical --no-input                # Priority
jira issue edit <KEY> --fix-version "v1.0" --no-input       # Fix version

# From stdin
echo "Updated desc" | jira issue edit <KEY> --no-input
```

### Transition

```bash
jira issue move <KEY> "In Progress"
jira issue move <KEY> "Code Review"
jira issue move <KEY> "Done"
jira issue move <KEY> "To Do"

# With comment or reassignment
jira issue move <KEY> "In Progress" --comment "Starting work"
jira issue move <KEY> "In Progress" -a username
```

Common statuses: To Do, New, In Progress, Code Review, QE Review, Done, Closed

### Assign

```bash
jira issue assign <KEY> username        # Assign to user
jira issue assign <KEY> $(jira me)      # Assign to self
jira issue assign <KEY> x              # Unassign
```

### Comment

```bash
jira issue comment add <KEY> "Comment text"
jira issue comment add <KEY> $'Line 1\n\nLine 2'          # Multi-line
echo "Comment" | jira issue comment add <KEY>              # From stdin
jira issue comment add <KEY> --template /path/to/file.md   # From file
```

### Link

```bash
jira issue link <KEY-1> <KEY-2> "Blocks"
jira issue link <KEY-1> <KEY-2> "Duplicate"
jira issue link <KEY-1> <KEY-2> "is blocked by"
```

### Sprints

```bash
jira sprint list --plain
jira sprint add <SPRINT_ID> <KEY-1> <KEY-2>
```

### Browser

```bash
jira open <KEY>     # Open issue in browser
jira open           # Open project page
```

## Troubleshooting

- **"No result found for given query in project OSAC":** The query is scoped to the default OSAC project. To search across projects, start `-q` with `project IS NOT EMPTY AND ...`. See the Search section above.
- **"Expecting ',' but got 'ORDER'" JQL error:** You included `ORDER BY` in a `-q` query. Remove it — jira-cli appends its own `ORDER BY created DESC` automatically.
- **"unknown flag: --description":** `jira-cli` has no `--description` flag. Use `-b` / `--body` for issue description, or `--template` to load from a file. See Create section above.
- **"unknown flag: --json":** `jira-cli` has no `--json` flag. Use `--plain` for clean output or `--raw` (create only) for JSON.
- **"flag needs an argument: --comments":** `--comments` requires a numeric count (e.g., `--comments 10`). Never use `--comments` without a number.
- **"unknown flag: --no-input" on move/assign/comment:** `--no-input` is only valid for `create` and `edit`. Remove it — move, assign, comment, and link don't need it.
- **Auth errors / HTML in response:** Token may be expired. Regenerate at https://id.atlassian.com/manage-profile/security/api-tokens, update `~/.netrc`.
- **"API v3" errors:** Config must use `installation: Cloud`. Re-run `jira init --installation cloud`.
- **Interactive prompts hang:** Always pass `--no-input` for create/edit operations.
- **Create looks hung / duplicates:** Large inline `--body` inside `$(...)` with `2>/dev/null` produces no output for minutes while the API works. Use `--template` and `--raw` with mktemp files for stdout and stderr; wait up to 3 min; never kill-and-retry. See "Preventing duplicate creates" above.
- **`--debug` flag:** Shows the actual REST API calls — useful for diagnosing unexpected behavior.
- **Current user:** `jira me` returns the authenticated username.
