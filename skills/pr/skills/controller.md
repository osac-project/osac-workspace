---
name: controller
description: Top-level workflow controller that manages phase transitions for PR lifecycle.
---

# PR Lifecycle Workflow Controller

You are the workflow controller. Your job is to manage the PR lifecycle
workflow by executing phases and handling transitions between them.

## Phases

1. **Create** (`/create`) — `create.md`
   Validate, push, and open a pull request on a component repo.

2. **Review** (`/review`) — `review.md`
   Check out and review a pull request, producing structured findings.

3. **Respond** (`/respond`) — `respond.md`
   Ingest review comments on your PR and address them with replies and
   code changes.

4. **Fix** (`/fix`) — `fix.md`
   Apply code fixes for review findings, one finding at a time with
   user approval.

## Component Resolution

Before dispatching any phase, resolve the target component:

1. Parse `$ARGUMENTS` — the first non-numeric argument (if any) is the
   component directory name (e.g., `osac-operator`, `fulfillment-service`).
   The first numeric argument (if any) is the PR number.
2. If a component was provided explicitly, verify it exists and is a git
   repository:
   ```bash
   git -C {component-dir} rev-parse --show-toplevel
   ```
3. If no component was provided, **auto-detect** from the current
   working directory:
   ```bash
   TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null)
   COMPONENT=$(basename "$TOPLEVEL")
   ```
   To distinguish a component repo from the workspace root, check
   whether `$TOPLEVEL` contains `bootstrap.sh`. If it does, the user
   is at the workspace root — not inside a component. Otherwise,
   `$COMPONENT` is the target.
4. If auto-detection fails (e.g., user is at the workspace root and not
   inside any component), list the available component directories and
   ask which one to use.
5. Pass the resolved component directory and PR number to the phase skill.

## Related Context Discovery

After resolving the component and PR, discover related PRD and design
artifacts. These provide requirements and design decisions that inform
the review and response process.

1. Extract a Jira issue key from the PR's branch name or title:
   ```bash
   cd {component-dir}
   BRANCH=$(git branch --show-current)
   ISSUE_KEY=$(echo "$BRANCH" | grep -oE '(OSAC|MGMT)-[0-9]+' || true)
   ```
   If no key in the branch, check the PR title:
   ```bash
   ISSUE_KEY=$(gh pr view --json title --jq '.title' | grep -oE '(OSAC|MGMT)-[0-9]+' || true)
   ```
2. If an issue key was found, check for related artifacts:
   - `.artifacts/prd/{issue-key}/03-prd.md` — PRD requirements and acceptance criteria
   - `.artifacts/design/{issue-key}/03-design.md` — design decisions and constraints
3. If `state.json` exists in `.artifacts/pr/{component}#{pr-number}/`,
   read it for the current review round and comment statuses.
4. Report discovered context to the user: *"Found related PRD (OSAC-1111)
   and design document. Will use them for context."* Or: *"No related
   PRD/design artifacts found."*
5. Pass the discovered paths to the phase skill.

## Workspace

All work happens within the component repo directories. The workspace root
is the parent directory containing multiple component repos.

### Artifact directory

Artifacts are stored in `.artifacts/pr/{component}#{pr-number}/`
within the **workspace root** (not inside the component repo):

| Artifact | File | Written by |
|----------|------|------------|
| Review state | `state.json` | `/respond` (created/updated) |
| Review comments | `01-review-comments.md` | `/respond` |
| Response log | `02-response-log.md` | `/respond` |
| Review findings | `03-review-findings.md` | `/review` |

## How to Execute a Phase

1. **Announce** the phase to the user: *"Starting /pr:create for osac-operator."*
2. **Resolve** the component directory (see "Component Resolution" above)
3. **Read** the skill file at `skills/pr/skills/{phase}.md`
4. **Execute** the skill's steps
5. When the skill is done, present results and use "Recommending Next Steps"
   below to offer options.
6. **Stop and wait** for the user to tell you what to do next.

## Recommending Next Steps

### Typical Flows

**Author flow** (creating and iterating on your own PR):
```text
create → [get reviews] → respond → [push changes] → respond loop
```

**Self-review flow** (reviewing and fixing your own PR):
```text
review → fix → [push changes]
```

**Reviewer flow** (reviewing someone else's PR):
```text
review
```

### What to Recommend

- `/create` completed → suggest sharing the PR URL, then `/respond` when
  reviews arrive
- `/review` completed → suggest `/fix` to apply code changes for the
  findings. Also offer posting the review or refining it.
- `/respond` completed → read `state.json` to report progress (e.g.,
  "5 of 8 comments addressed, 3 pending"). Recommend pushing changes
  if code was modified, then another `/respond` round if pending comments
  remain. Offer `/create` if the user needs to update the PR.

### How to Present Options

Lead with your top recommendation, then list alternatives briefly:

```text
Recommended next step: /respond — address the review comments.

Other options:
- /create — if you need to push updates and create a new PR
- /review — to review a different PR
```

## Starting the Workflow

Before dispatching any phase, check if the component repo has its own
`CLAUDE.md`. If so, read it — it contains repo-specific validation
commands, branching conventions, and other guidance.

If the user invokes a specific command (e.g., `/review`), execute that
phase directly — don't force them through earlier phases.

## Error Handling

If any phase fails (`gh` CLI errors, validation failures, push rejections):

1. **Stop immediately.** Do not advance to the next phase.
2. **Report the error** with the specific error message.
3. **Offer options:** retry, fix the issue, or escalate.

Do not fabricate results when a tool call fails.

## Rules

- **Never auto-advance.** Always wait for the user between phases.
- **Recommendations come from this file, not from skills.**
- **Never post responses without user approval.**
- **Never push to `origin`.** Always push to `fork`.
