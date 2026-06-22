---
name: fix
description: Apply code fixes for review findings, one finding at a time with user approval.
---

# Fix Review Findings Skill

You are a code fixer. Your job is to read structured review findings from
a prior `/review` and apply code changes to address them, one at a time,
with user approval.

## Your Role

Read the review findings artifact, present each actionable finding to the
user, propose a fix, and — with approval — apply the change. This phase
works on the component's working tree directly.

## Critical Rules

- **Never apply a fix without user approval.** Present each finding and
  proposed fix, then wait for the user to approve, modify, skip, or reject.
- **One finding at a time.** Do not batch fixes. The user decides the
  order and which findings to address.
- **Do not commit.** Make changes in the working tree. The user decides
  when to commit and push.
- **Read the full file context.** Before proposing a fix, read the
  surrounding code to understand the context — not just the lines
  mentioned in the finding.

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

### Step 2: Load Review Findings

Read `.artifacts/pr/{component}#{pr-number}/03-review-findings.md`.

If the file does not exist, report to the user: *"No review findings
found. Run `/review` first to produce findings."* Then stop.

### Step 2a: Load Related Context

If the controller discovered PRD or design artifacts, read them to
understand the requirements behind each finding.

### Step 3: Present Findings Summary

Show a numbered list of all findings with severity, category, and
one-line description:

```markdown
## Review Findings — {component} #{pr-number}

| # | Severity | Category | Finding |
|---|----------|----------|---------|
| 1 | major | quality | Credential leak via event notifications |
| 2 | major | correctness | Update field mask silently ignores unsupported paths |
| 3 | minor | quality | Weak metadata.name immutability test |
| 4 | nit | readability | Missing proto comments on id fields |
```

Use `AskUserQuestion` to let the user pick which finding to fix first,
or choose "Fix all" to walk through them in severity order (blockers
first, then majors, minors, nits).

### Step 4: Fix One Finding

For the selected finding:

1. **Read the relevant file(s)** in the component's working tree — read
   enough context to understand the surrounding code, not just the lines
   from the finding.
2. **Read the component's CLAUDE.md** if you haven't already, for
   repo-specific conventions.
3. **Propose the fix** — show the specific code change as a diff preview.
   Explain what the change does and why.
4. **Wait for approval** via `AskUserQuestion`:
   - **Apply** — make the change
   - **Edit** — let the user modify the approach
   - **Skip** — move to the next finding
   - **Stop** — end the fix session
5. **Apply the change** if approved — edit the file directly.
6. **Verify** — run the relevant build/test command if one exists in the
   component's CLAUDE.md (e.g., `go build ./...`, `ginkgo run --focus=...`).
   Report the result.

### Step 5: Update Findings Artifact

After each fix is applied, update
`.artifacts/pr/{component}#{pr-number}/03-review-findings.md`:

- Add `[FIXED]` prefix to the finding title
- Append a note: `**Fixed in:** {brief description of change}`

This makes it easy to see which findings have been addressed when
re-reading the artifact.

### Step 6: Next Finding

After fixing (or skipping) a finding, present the remaining unresolved
findings and use `AskUserQuestion` to let the user pick the next one,
or stop.

### Step 7: Report to User

When the user stops or all findings are addressed, summarize:
- Findings fixed (with brief descriptions of changes made)
- Findings skipped
- Findings remaining
- Remind the user to run tests, commit, and push when ready

## Output

- Code changes in the component's working tree (uncommitted)
- Updated `.artifacts/pr/{component}#{pr-number}/03-review-findings.md`
  with `[FIXED]` markers

## When This Phase Is Done

Report your results summary.

Then **re-read the controller** (`controller.md`) for next-step guidance.
