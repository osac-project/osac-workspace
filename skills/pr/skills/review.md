---
name: review
description: Check out and review a pull request, producing structured findings.
---

# Review Pull Request Skill

You are a PR code reviewer. Your job is to check out a pull request in a
temporary worktree, review the changes against the project's standards,
and produce structured findings.

## Your Role

Read the PR diff, understand the problem being solved, evaluate the
solution's correctness and quality, and produce actionable findings.
Optionally post the review as GitHub PR comments (with user approval).

## Critical Rules

- **Read-only by default.** Do not modify the component repo's working tree. Use a temporary worktree for checkout.
- **Never post review comments without user approval.** Present findings first, then ask if the user wants them posted.
- **Review the solution, not just the code.** Focus on whether the approach is correct and simple before checking style.

## Process

### Step 1: Resolve Component and PR

The controller provides the component directory and optional PR number.

If no PR number was provided, detect it from the component's current branch:

```bash
cd {component-dir} && gh pr view --json number --jq .number
```

If no PR is found, ask the user for a PR number.

Determine the repo identity:

```bash
cd {component-dir} && gh repo view --json nameWithOwner --jq .nameWithOwner
```

### Step 2: Read Component CLAUDE.md

Read `{component-dir}/CLAUDE.md` if it exists. It contains repo-specific
conventions, architecture patterns, and testing expectations that inform
the review.

### Step 2a: Load Related Context

The controller discovers related PRD and design artifacts by matching the
Jira issue key from the branch name or PR title. If the controller found
related artifacts, load them now:

- **PRD context:** Read `.artifacts/prd/{issue-key}/03-prd.md` if it exists.
  Extract requirements and acceptance criteria — these define what the PR
  should achieve.
- **Design context:** Read `.artifacts/design/{issue-key}/03-design.md` if
  it exists. Extract design decisions, constraints, and architectural
  rationale — these explain why the approach was chosen.

Use this context throughout the review:
- When evaluating **correctness** — does the implementation match the
  requirements?
- When evaluating **completeness** — are all specified requirements
  addressed, or are some missing?
- When writing **findings** — reference specific PRD requirements or
  design decisions where relevant

If no related artifacts are found, proceed without them — this step is
opportunistic.

### Step 3: Create Temporary Worktree

Check out the PR into a temporary worktree to avoid disturbing the user's
working tree:

```bash
cd {component-dir}
mkdir -p ../.artifacts/pr/{component}#{pr-number}
WORKTREE_DIR="../.artifacts/pr/{component}#{pr-number}/worktree"
git fetch origin pull/{pr-number}/head:pr-{pr-number}
git worktree add "$WORKTREE_DIR" pr-{pr-number}
```

If the worktree already exists from a prior review, remove it first:

```bash
git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
```

### Step 4: Get PR Context

Fetch PR metadata and diff:

```bash
gh pr view {pr-number} --repo {owner}/{repo} --json title,body,author,commits,changedFiles,additions,deletions,reviews,labels
```

```bash
gh pr diff {pr-number} --repo {owner}/{repo}
```

Read the PR description and any linked Jira tickets or issues to understand
the intent behind the changes.

### Step 5: Review the Code

Work from the temporary worktree. Read the changed files in full (not just
the diff hunks) to understand context.

Evaluate using these criteria:

**Correctness:**
- Does the solution solve the stated problem?
- Are there edge cases that aren't handled?
- Could the change introduce regressions?

**Simplicity:**
- Is the solution more complex than necessary?
- Could existing utilities or patterns be reused?
- Are there unnecessary abstractions?

**Quality:**
- Does the code follow the repo's conventions (from CLAUDE.md)?
- Is error handling adequate?
- Are there security concerns (injection, auth bypass, etc.)?
- Is there adequate test coverage for the changes?

**Readability:**
- Are names descriptive?
- Is the code self-documenting?
- Are comments used where the "why" is non-obvious?

**Completeness vs. requirements** (when PRD/design context is available):
- Does the PR implement what the PRD specified?
- Are acceptance criteria met?
- Does the approach align with the design document's decisions?
- Is anything from the requirements missing or only partially implemented?

### Step 6: Create Artifact Directory and Write Findings

```bash
mkdir -p .artifacts/pr/{component}#{pr-number}
```

Write `.artifacts/pr/{component}#{pr-number}/03-review-findings.md`:

```markdown
# Review Findings — {component} #{pr-number}

## PR Summary

- **Title:** {title}
- **Author:** {author}
- **Changes:** +{additions} -{deletions} across {changedFiles} files

## Findings

### Finding 1 — {severity}: {short title}
- **File:** {file-path}:{line-range}
- **Category:** {correctness|simplicity|quality|readability}
- **Description:** {what the issue is and why it matters}
- **Suggestion:** {concrete fix or alternative approach}

### Finding 2 — ...

## Overall Assessment

{2-3 sentences: is this PR ready to merge, does it need changes, or does
 it need significant rework? What are the strengths?}
```

Severity levels: `blocker` (must fix), `major` (should fix), `minor` (nice
to fix), `nit` (style only).

### Step 7: Offer to Post Review

Present the findings summary to the user.

Use `AskUserQuestion` to present the next-action choice so the user can
select with the keyboard:

- **Fix findings** — continue to `/fix` to apply code changes for the
  actionable findings (recommended when reviewing your own PR)
- **Post as PR review** — submit the findings as a general GitHub review
  comment
- **Keep local** — just use the artifact file for reference
- **Refine** — adjust findings before posting

If the user approves posting, submit a review summary:

```bash
gh pr review {pr-number} --repo {owner}/{repo} --comment --body "review summary"
```

### Step 8: Clean Up Worktree

The worktree is read-only (no modifications should have been made), so
force-remove is safe:

```bash
cd {component-dir}
git worktree remove "$WORKTREE_DIR" --force
git branch -D pr-{pr-number} 2>/dev/null || true
```

### Step 9: Report to User

Summarize:
- How many findings by severity (blockers, majors, minors, nits)
- Overall assessment (merge-ready, needs changes, needs rework)
- Whether the review was posted to GitHub

## Output

- `.artifacts/pr/{component}#{pr-number}/03-review-findings.md`
- Optionally: GitHub PR review comments (with user approval)

## When This Phase Is Done

Report your findings summary and overall assessment.

Then **re-read the controller** (`controller.md`) for next-step guidance.
