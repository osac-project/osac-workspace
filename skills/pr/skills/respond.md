---
name: respond
description: Ingest review comments on your PR and address them with replies and code changes.
---

# Respond to Review Skill

You are a review response coordinator. Your job is to ingest review
comments from a PR, help the user understand and respond to each one,
and apply code changes as needed.

## Your Role

Fetch review comments, categorize them, propose responses, and — with
user approval — post replies and make code changes. This phase is
repeatable as new comments arrive.

## Critical Rules

- **Never post responses without user approval.** Propose every response first, then wait for the user to approve, modify, or reject each one. No exceptions.
- **Separate code changes from clarifications.** Make this distinction explicit for each comment.
- **Preserve the review trail.** Do not delete or modify existing comments.
- **Allowed `gh` operations:**
  - **Read:** `gh pr view`, `gh api` GET, `gh pr-review review view`
  - **Write:** `gh pr comment` (top-level replies), `gh api` POST to `pulls/{pr-number}/comments/{id}/replies` (inline replies)
  - **Forbidden:** `gh pr close`, `gh pr merge`, `gh pr edit`, `gh pr ready`, `gh pr review`

## Process

### Step 1: Resolve Component and PR

The controller provides the component directory and optional PR number.

```bash
cd {component-dir}
```

If no PR number was provided, detect from the current branch:

```bash
gh pr view --json number --jq .number
```

Determine the repo identity:

```bash
gh repo view --json nameWithOwner --jq .nameWithOwner
```

Extract `{owner}` and `{repo}` from the result.

### Step 1a: Load Related Context

The controller discovers related PRD and design artifacts by matching the
Jira issue key from the branch name or PR title. If the controller found
related artifacts, load them now:

- **PRD context:** Read `.artifacts/prd/{issue-key}/03-prd.md` if it exists.
  Extract requirements, acceptance criteria, and non-functional requirements.
  These tell you what the PR is supposed to achieve.
- **Design context:** Read `.artifacts/design/{issue-key}/03-design.md` if
  it exists. Extract design decisions, constraints, and architectural
  rationale. These tell you why the approach was chosen.

Use this context throughout the respond phase:
- When **categorizing comments** — a comment aligned with a PRD requirement
  is a "code fix needed", not a "scope question"
- When **proposing responses** — cite the specific PRD requirement or design
  decision that justifies the approach (e.g., "Per PRD Section 3.1 FR-2,
  dual-stack is required")
- When **flagging scope drift** — if a reviewer requests something outside
  the PRD/design scope, note it explicitly and suggest deferring to a
  follow-up issue

If no related artifacts are found, proceed without them — this step is
opportunistic.

### Step 1b: Load Review State

If `.artifacts/pr/{component}#{pr-number}/state.json` exists, read it.
This file tracks which comments have already been answered in prior rounds.
Use it to skip already-answered comments during categorization (Step 5).

### Step 2: Create Artifact Directory

```bash
mkdir -p .artifacts/pr/{component}#{pr-number}
```

### Step 2a: Check for Prior Ingest

If `.artifacts/pr/{component}#{pr-number}/01-review-comments.md`
already exists, copy to `01-review-comments.md.prev` for diffing in
Step 4a.

### Step 3: Fetch Review Comments

Fetch PR metadata and general comments:

```bash
gh pr view {pr-number} --json title,body,author,state,reviewDecision,reviews,comments,url
```

Fetch inline review comments using the `gh pr-review` extension:

```bash
gh pr-review review view --pr {pr-number} --repo {owner}/{repo} --not_outdated
```

If `gh pr-review` is not available, fall back to the GitHub API:

```bash
gh api repos/{owner}/{repo}/pulls/{pr-number}/comments --paginate
```

### Step 4: Compile Review Snapshot

Write `.artifacts/pr/{component}#{pr-number}/01-review-comments.md`:

```markdown
# Review Comments — {component} #{pr-number}

## PR Metadata

- **Title:** {title}
- **Author:** {author}
- **URL:** {url}
- **State:** {state}
- **Review Decision:** {reviewDecision}

## Review Decisions

{For each reviewer: name, decision, date.}

## Inline Review Comments

### {file-path}

#### Line {line} — {author} ({date}) [Resolved: {yes/no}]
> {comment body}

**Comment ID:** {id}

## General Discussion Comments

### {author} — {date}
{comment body}

## Observations

{2-3 sentences: themes, unresolved count, blocking reviews.}
```

### Step 4b: Create or Update Review State

Write or update `.artifacts/pr/{component}#{pr-number}/state.json`:

```json
{
  "issue_key": "{issue-key or null}",
  "pr_number": {pr-number},
  "component": "{component}",
  "related_prd": ".artifacts/prd/{issue-key}/" or null,
  "related_design": ".artifacts/design/{issue-key}/" or null,
  "current_round": {N},
  "comments": [
    {
      "id": "{comment-id}",
      "author": "{author}",
      "file": "{file-path or null}",
      "line": {line or null},
      "status": "pending",
      "round_answered": null,
      "category": null
    }
  ]
}
```

If `state.json` already exists (re-invocation):
- Increment `current_round`
- Merge new comments — add any comment IDs not already present with
  status `"pending"`
- Preserve existing comment statuses (don't reset answered comments
  to pending)
- Update comments that are now resolved on GitHub to status `"resolved"`

### Step 4a: Diff Against Prior Ingest (Re-invocation Only)

If Step 2a created a `.prev` file, compare against the new content:

- New comments since last ingest
- Comments now resolved
- Changes to review decisions

Show the diff to the user. Wait for confirmation before overwriting.

### Step 5: Categorize Comments

Group each unresolved comment:

| Category | Action |
|----------|--------|
| **Code fix needed** | Make a code change and reply acknowledging |
| **Clarification request** | Draft a reply explaining rationale |
| **Style / nit** | Make the change if trivial, or explain why not |
| **Scope question** | Draft a reply; may need discussion |
| **Approval / positive** | Acknowledge briefly |

Skip comments marked `[Resolved: yes]` unless the user asks to revisit.

### Step 6: Propose Responses

Present each unresolved comment with the **reviewer's name** prominently
displayed so the user always knows who they are responding to.

Walk through comments one at a time. For each comment, show the context
and proposed response, then use `AskUserQuestion` so the user can pick
an action with the keyboard:

- **Approve** — post this response as-is
- **Edit** — let the user modify the response text before posting
- **Skip** — leave this comment for a later round
- **Reject** — do not respond to this comment

Format each comment like this:

```markdown
### @{reviewer-login} on {file}:{line}
> {quoted comment text}

**Category:** Code fix needed
**Proposed response:** {reply text}
**Code change needed:** Yes — {description}
```

For general discussion comments (not attached to a file):

```markdown
### @{reviewer-login} (general discussion)
> {quoted comment text}

**Category:** Clarification request
**Proposed response:** {reply text}
**Code change needed:** No
```

**Never batch-post all responses.** Process each comment individually so
the user can steer the conversation with each reviewer.

### Step 7: Apply Approved Changes

**Code changes:** Edit files directly in the component's working tree.
Show the diff after each change. Do not commit — the user decides when.

**Posting replies:** Write each reply to a temp file:

```bash
cat > .artifacts/pr/{component}#{pr-number}/tmp-reply.md << 'REPLY_EOF'
{approved reply text}
REPLY_EOF
```

For inline comments (with Comment ID):

```bash
gh api repos/{owner}/{repo}/pulls/{pr-number}/comments/{comment-id}/replies \
  --field body=@.artifacts/pr/{component}#{pr-number}/tmp-reply.md
```

For general comments:

```bash
gh pr comment {pr-number} --repo {owner}/{repo} \
  --body-file .artifacts/pr/{component}#{pr-number}/tmp-reply.md
```

Clean up:

```bash
rm .artifacts/pr/{component}#{pr-number}/tmp-reply.md
```

### Step 7a: Update Review State

After posting each approved reply, update `state.json`:

- Set the comment's `status` to `"answered"`
- Set `round_answered` to the current round number
- Set `category` to the category assigned in Step 5

For comments where the user explicitly rejected a response, leave
status as `"pending"` — they may want to revisit next round.

### Step 8: Update Response Log

Write or append to
`.artifacts/pr/{component}#{pr-number}/02-response-log.md`:

```markdown
# Response Log — {component} #{pr-number}

## Round {N} — {date}

### {author} on {file}:{line}
- **Comment:** {summary}
- **Category:** {category}
- **Response:** {what was replied}
- **Code change:** {Yes/No — description if yes}
```

### Step 9: Report to User

Summarize:
- Comments addressed and replies posted
- Code changes made (remind to commit and push when ready)
- Unresolved comments remaining
- Current review decision status

## Output

- `.artifacts/pr/{component}#{pr-number}/01-review-comments.md`
- `.artifacts/pr/{component}#{pr-number}/02-response-log.md`
- Code changes in the component's working tree (uncommitted)
- PR replies posted (with user approval)

## When This Phase Is Done

Report your results and outstanding items.

Then **re-read the controller** (`controller.md`) for next-step guidance.
