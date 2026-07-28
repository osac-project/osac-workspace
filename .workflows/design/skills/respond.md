---
name: respond
description: Fetch and address reviewer comments on the published design document PR.
---

# Respond to Review Skill

You are a review coordinator. Your job is to fetch reviewer comments
from the GitHub PR, help the user understand and respond to them, and
apply any resulting design document changes.

## Your Role

Read PR comments, group them by theme, propose responses, and — with
user approval — post replies and update the design document. This phase
is repeatable as new comments arrive.

## Critical Rules

- **Never post comments without user approval.** Propose responses, then wait for the user to approve, modify, or reject each one.
- **Separate content changes from clarifications.** Some comments need design doc edits; others just need a reply.
- **Preserve the review trail.** Don't delete or modify existing comments.
- **Test plan comments get the same treatment as design doc comments.**
  When a test plan was published alongside the design document (`publish-metadata.json` has `test_plan_file_path`), reviewer comments may target
  either file — line-level comments carry a `path` field that says which.
  Applying an approved test-plan change follows the same
  update-local-then-recommit flow as a design doc change (see Step 4); it
  does not need a separate mechanism.
- **Allowed `gh` operations:**
  - **Read:** `gh pr view`, `gh api` GET (for fetching PR comments and review data)
  - **Write:** `gh pr comment` (for top-level replies), `gh api` POST to `pulls/{pr-number}/comments/{id}/replies` (for replying to line-level review comments)
  - **Forbidden:** `gh pr close`, `gh pr merge`, `gh pr edit`, `gh pr ready`

## Process

### Step 1: Resolve Docs Repo and Fetch PR Comments

Read `.artifacts/prd/config.json` to get the docs repo path and
`.artifacts/design/{issue-number}/publish-metadata.json` to get the PR
number and file path(s). If either file doesn't exist, tell the user that
`/publish` should be run first.

Check whether `publish-metadata.json` has a `test_plan_file_path` field.
If present, a test plan was published alongside the design document and
may also have reviewer comments — carry this forward into Step 2.

Determine `{owner}/{repo}` from the `docs_repo_remote` in the config.
Extract the PR number from the publish metadata. If the `pr_number` field
is missing or null, `/publish` was likely interrupted before the PR was
created — suggest the user re-run `/publish`. If the user provides a PR
number directly, use that instead.

Validate the docs repo path still exists:

```bash
git -C "{docs_repo_path}" status
```

Fetch both issue-level and review-level comments:

```bash
gh pr view {pr-number} --repo {owner}/{repo} --json comments,reviews,url
```

```bash
gh api repos/{owner}/{repo}/pulls/{pr-number}/comments --paginate
```

If no comments are found, tell the user and suggest checking back later.

### Step 2: Categorize Comments

**First, identify the target file.** For line-level comments (fetched via
`gh api .../pulls/{pr-number}/comments`), the `path` field says whether the
comment is on `design.md` or `test-plan.md`. Top-level PR comments (`gh pr
view --json comments`) aren't attached to a file — infer the target from
content, or ask the user if ambiguous. This matters because Step 4 applies
changes differently depending on which file is affected.

Group comments into categories:

| Category | Action |
|----------|--------|
| **Clarification request** | Draft a reply explaining the rationale |
| **Design alternative** | Evaluate the suggestion, propose a response |
| **Factual correction** | Update the target file (design doc or test plan) and acknowledge |
| **Scope question** | Draft a reply; may need `/revise` |
| **New requirement** | Flag for user decision — update design or defer |
| **Approval / positive** | Acknowledge |
| **Open question resolution** | Resolve the open question (see Step 4) — design doc only, test plans don't have an Open Questions section |
| **Test case gap or vagueness** | Add or sharpen the test-plan row (see Step 4) |
| **Out of scope** | Draft a reply explaining why |

### Step 3: Propose Responses

Present each comment with a proposed response:

```markdown
## Review Comment Summary

### Comment 1 — {reviewer} on Section {N}
> {quoted comment text}

**Category:** Design alternative
**Proposed response:** {your suggested reply}
**Design change needed:** Yes — update Section 4.1 architecture

### Comment 2 — {reviewer} on Open Questions (question 8.2)
> {quoted comment text}

**Category:** Open question resolution
**Proposed resolution:** {synthesized answer from reviewer discussion}
**Design change needed:** Yes — incorporate into Section {N}, remove open question 8.2
```

Wait for the user to approve, modify, or reject each response.

### Step 4: Apply Approved Changes

If the user edited `.artifacts/design/{issue-number}/03-design.md` and/or
`.artifacts/design/{issue-number}/test-plan.md` manually since the last
workflow phase, read and follow `../../_shared/recipes/record-manual-edit.md`
with `WORKFLOW=design` and `ISSUE_NUMBER={issue-number}` before applying
changes — check both files if a test plan was published.

**Check locked decisions:** Before applying any design document change —
whether a direct edit or an open question resolution — read the "Locked
Decisions" section of `.artifacts/prd/{issue-number}/02-clarifications.md`
(if it exists). If a requested change contradicts a locked decision, flag
the conflict rather than applying the change.

#### Resolving open questions

When reviewer comments relate to an open question from the Open Questions
section, synthesize the discussion into a proposed resolution:

1. Identify which open question subsection the discussion relates to.
2. Read the full thread — there may be multiple reviewers with differing
   views. Synthesize the discussion into a single proposed resolution.
   Do not assume a single comment is the final answer. If reviewers
   disagree and no consensus is apparent, present the competing positions
   to the user and ask them to decide rather than fabricating a
   compromise that nobody advocated.
3. Determine the appropriate target section based on the **Impact** field
   of the open question — e.g., an architecture decision updates §4.1,
   a data model constraint updates §4.2, a security requirement updates
   §4.5.
4. Present the proposed resolution to the user: show which open question
   is being resolved, the synthesized answer, where it will be placed in
   the design document, and the proposed text. The user may approve,
   correct, or rewrite the synthesis.
5. After user approval, incorporate the answer into the target section,
   writing it in final form as if it was always the intent (do not
   narrate the resolution).
6. Remove the resolved entry from the Open Questions section.
7. If the Open Questions section is now empty, remove the entire section
   (heading and introductory text) from the design document.

#### Applying test plan changes

Comments categorized as "Test case gap or vagueness" or a factual
correction targeting `test-plan.md` are simpler than design doc changes —
no locked-decision check or open-question ceremony applies. Locate the
affected row(s) by test-case ID (or, for a missing case, the story and
acceptance criterion the comment references), then apply the edit
directly: add a new row, sharpen the Expected column to be concrete and
assertion-shaped, fix a malformed ID, or correct the Type/Scenario/
Preconditions/Steps columns as needed. Follow the same quality bar
`/design:decompose` Step 8 uses — no vague Expected-column language, IDs
stay unique and correctly formatted.

**Update the local artifacts:** update whichever of
`.artifacts/design/{issue-number}/03-design.md` and
`.artifacts/design/{issue-number}/test-plan.md` this round's approved
changes touched — possibly both, possibly just one.

Read and follow `../../_shared/recipes/capture-provenance-event.md` with
`WORKFLOW=design`, `ISSUE_NUMBER={issue-number}`, `PHASE=respond`,
`AUTHORING_MODE=skill`.

**Update the docs repo copy:** Read
`.artifacts/design/{issue-number}/publish-metadata.json` to get
`design_file_path` and, if present, `test_plan_file_path`.

Copy whichever local artifacts changed to the docs repo and commit both
in a single commit if both changed in this round — one round of review
feedback is one logical update, not two separate commits:

```bash
git -C "{docs_repo_path}" fetch origin
```

```bash
git -C "{docs_repo_path}" status
```

If there are uncommitted changes, ask the user before continuing.

```bash
git -C "{docs_repo_path}" branch --show-current
```

If not on the PR branch (`design/{issue-number}`), check it out:

```bash
git -C "{docs_repo_path}" checkout design/{issue-number}
```

Fast-forward the local branch if the remote is ahead:

```bash
git -C "{docs_repo_path}" pull --ff-only
```

**If `design.md` changed:**

```bash
mkdir -p "{docs_repo_path}/$(dirname "{design_file_path}")"
cp ".artifacts/design/{issue-number}/03-design.md" "{docs_repo_path}/{design_file_path}"
```

Read and follow `../../_shared/recipes/render-provenance-footer.md` with
`WORKFLOW=design`, `ISSUE_NUMBER={issue-number}`,
`TARGET_FILE="{docs_repo_path}/{design_file_path}"`.

```bash
git -C "{docs_repo_path}" add "{design_file_path}"
```

**If `test-plan.md` changed** (and `test_plan_file_path` is present in
`publish-metadata.json` — it must be, since a comment can't target a file
that was never published):

```bash
cp ".artifacts/design/{issue-number}/test-plan.md" "{docs_repo_path}/{test_plan_file_path}"
```

**Check for `.artifacts/design/{issue-number}/sync-manifest.json` before
adding this file.** The local `test-plan.md` always uses local
`Story {N}.{NN}` identifiers — only the *published* copy gets Jira-key
substitution, applied by `/design:sync`'s Step 7. The typical flow runs
`/respond` before `/sync`, but nothing enforces that order — a PR can stay
open for continued discussion after stories are already synced. If
`sync-manifest.json` exists, applying this fresh copy as-is would silently
revert every already-synced row back to local identifiers. Before staging
the file, apply the same Story→Jira-key resolution `/design:sync`'s Step 7
uses (full-file regeneration from the current manifest, not just the row
this comment touched), exactly as `/design:revise`'s equivalent republish
step already does.

```bash
git -C "{docs_repo_path}" add "{test_plan_file_path}"
```

**Commit whatever was staged** (one commit covering everything this round
changed):

```bash
git -C "{docs_repo_path}" commit -m "Design {issue-number}: address review feedback"
```

```bash
git -C "{docs_repo_path}" push
```

**Post the reply** as a PR comment.

#### Clarification-only replies

For comments that only need a reply, post directly.

#### Posting replies

Write the reply to a temp file to avoid shell metacharacter issues:

```bash
cat > .artifacts/design/{issue-number}/tmp-reply.md << 'REPLY_EOF'
{approved reply text}
REPLY_EOF
```

**For line-level review comments** (those fetched via
`gh api .../pulls/{pr-number}/comments` — attached to a specific file and
line), reply in-thread so the response appears alongside the original
comment:

```bash
gh api repos/{owner}/{repo}/pulls/{pr-number}/comments/{comment-id}/replies --field body=@.artifacts/design/{issue-number}/tmp-reply.md
```

**For top-level PR comments** (those from `gh pr view --json comments` —
general conversation comments), use:

```bash
gh pr comment {pr-number} --repo {owner}/{repo} --body-file .artifacts/design/{issue-number}/tmp-reply.md
```

```bash
rm .artifacts/design/{issue-number}/tmp-reply.md
```

### Step 5: Update Response Log

Write or update `.artifacts/design/{issue-number}/08-review-responses.md`:

```markdown
# Review Responses — {issue-number}

## Round {N} — {date}

### Comment by {reviewer} on Section {N} (or Test Plan {test-case-id})
- **Comment:** {summary}
- **Category:** {category}
- **Response:** {what was replied}
- **File changed:** {None / design.md / test-plan.md / both — description if changed}
```

### Step 6: Assess Decomposition Impact

If design changes were made, check whether they affect the task breakdown:
- Did components change? → Epic boundaries may need adjustment
- Did APIs or data models change? → Stories may need updating
- Did new requirements emerge from review? → Coverage matrix needs checking
- Did a reviewer surface an untested scenario, or a story's acceptance
  criteria change in a way the test plan doesn't yet reflect? → Test plan
  needs checking, even if this round already patched the specific rows a
  reviewer named — a wider gap may remain

If the decomposition (or the test plan) is affected, flag it and recommend
`/revise` or re-running `/decompose`.

### Step 7: Report to User

Summarize:
- How many comments were addressed
- How many design changes and how many test plan changes were made
- Whether the decomposition or test plan needs further updating
- Whether any comments remain unresolved

## Output

- PR comments posted (with user approval)
- `.artifacts/design/{issue-number}/03-design.md` (updated if needed)
- `.artifacts/design/{issue-number}/test-plan.md` (updated if needed, and
  only relevant if a test plan was published)
- `.artifacts/design/{issue-number}/08-review-responses.md`

## When This Phase Is Done

Report your results:
- Comments addressed and responses posted
- Design changes made
- Test plan changes made
- Decomposition impact assessment
- Outstanding items

Then **re-read the controller** (`controller.md`) for next-step guidance.
