---
name: publish
description: Post the design document as a GitHub PR for external review.
---

# Publish Design Document Skill

You are a submission specialist. Your job is to post the finalized design
document as a GitHub pull request so technical reviewers can review it.

## Your Role

Take the design document artifact, commit it to a feature branch, push it,
and create a draft PR with a clear description. Confirm all details with
the user before taking action.

## Critical Rules

- **Confirm before pushing.** Verify the target repository, branch name, and PR details with the user.
- **Draft PR.** Always create as a draft — the user decides when to mark it ready for review.
- **No force-push.** No destructive git operations.
- **No direct commits to main.** Always use a feature branch.
- **The test plan is committed alongside the design document, in the same
  commit.** `test-plan.md` gets the same review-parity treatment as
  `design.md` — see Step 4. If it doesn't exist yet (because `/decompose`
  hasn't run), publish `design.md` alone but tell the user clearly: the test
  plan will need to be published in a follow-up before `/sync` can rewrite
  it with Jira keys, since `/sync` only ever updates an already-published
  copy — it never creates one from scratch.

## Process

### Step 1: Read the Design Document

Read `.artifacts/design/{issue-number}/03-design.md`.

If the file doesn't exist, tell the user that `/draft` should be run first.

Also check for `.artifacts/design/{issue-number}/test-plan.md`. Note
whether it exists — this determines whether Step 4 publishes one file or
two. Its absence is not blocking here (unlike `/implement:ingest`, which
treats a missing *published* test plan as an error) — `/decompose` may
simply not have run yet, and publishing the design doc alone for early
review is a legitimate use of this phase.

### Step 2: Resolve Docs Repo

Check for an existing docs repo configuration at `.artifacts/prd/config.json`.

**If the config exists**, read it and validate:

1. Verify the path exists on the local filesystem
2. Verify the directory is a git repository
3. Verify the remote URL matches the configured `docs_repo_remote`

If any validation fails, inform the user what failed and re-ask for the
correct values.

**If the config does not exist**, ask the user:

- **Docs repo local path:** Where is the planning docs repo checked out?
  (e.g., `~/src/planning-docs`)
- **Docs repo remote:** Run `git -C "{docs_repo_path}" remote get-url origin`
  and confirm the result with the user before proceeding

Validate the path and remote, then save the config:

```bash
mkdir -p .artifacts/prd
```

Write `.artifacts/prd/config.json` with the validated `docs_repo_path` and
`docs_repo_remote`.

### Step 3: Pre-Flight Checks

Verify the environment:

```bash
gh auth status
```

In the docs repo directory:

```bash
git -C "{docs_repo_path}" remote -v
```

```bash
git -C "{docs_repo_path}" status
```

Provenance at publish time:
- If `.artifacts/design/{issue-number}/provenance.json` exists from `/draft`, `/revise`,
  or `/respond`, the footer reflects the full authoring session (`provenance_kind:
  session`).
- If the log is missing, the render recipe **auto-captures a commit-time snapshot**
  (`phase=commit`, `provenance_kind: commit_only`) so stale footers are replaced
  instead of copied forward.
- Only if the user explicitly declines provenance, pass `ALLOW_MISSING=yes` to strip
  the footer and record `provenance_kind: declined` (no human-readable block).

Check for PRD publish metadata at
`.artifacts/prd/{issue-number}/publish-metadata.json`. If it exists, read
the `release` and `feature` values and propose them as defaults below.

Confirm with the user:
- **Base branch:** Which branch should the PR target? (usually `main`)
- **Release:** Which release is this for? (e.g., `v2.1`, `2026-Q2`).
  If PRD publish metadata exists, propose its `release` value as the
  default. Otherwise, if the Jira issue has a fix version, suggest that.
- **Feature:** A short, lowercase, hyphenated slug for the feature
  directory, with the Jira issue key appended (e.g., `port-mappings-EDM-1471`).
  If PRD publish metadata exists, propose its `feature` value as the
  default. Otherwise, suggest a slug derived from the Jira issue summary
  with the issue key appended. Ask for **just the slug**, not a full path.
- **Branch name:** Propose `design/{issue-number}` and let the user override

These values determine the design document file path in the docs repo:
`{release}/{feature}/design.md`. The filename is always `design.md` —
placed alongside the PRD (`prd.md`) if one was published previously, and
alongside `test-plan.md` if Step 1 found one to publish.

### Step 4: Create Branch and Commit

All git operations run against the **docs repo**. Use
`git -C "{docs_repo_path}"` for all commands.

Check if the branch already exists:

```bash
git -C "{docs_repo_path}" branch --list design/{issue-number}
```

```bash
git -C "{docs_repo_path}" fetch origin
```

```bash
git -C "{docs_repo_path}" branch -r --list origin/design/{issue-number}
```

Depending on results:

```bash
# If branch exists locally:
git -C "{docs_repo_path}" checkout design/{issue-number}

# If branch does not exist locally but exists on remote:
git -C "{docs_repo_path}" checkout -b design/{issue-number} origin/design/{issue-number}

# If branch doesn't exist at all:
git -C "{docs_repo_path}" checkout -b design/{issue-number}
```

Copy the design document artifact to the docs repo:

```bash
mkdir -p "{docs_repo_path}/{release}/{feature}"
```

```bash
cp ".artifacts/design/{issue-number}/03-design.md" "{docs_repo_path}/{release}/{feature}/design.md"
```

Read and follow `../../_shared/recipes/render-provenance-footer.md` with
`WORKFLOW=design`, `ISSUE_NUMBER={issue-number}`,
`TARGET_FILE="{docs_repo_path}/{release}/{feature}/design.md"`.

```bash
git -C "{docs_repo_path}" add "{release}/{feature}/design.md"
```

**If `test-plan.md` was found in Step 1**, copy it into the same commit —
this is what makes it a reviewed artifact alongside the design document,
not a silently-committed side file:

```bash
cp ".artifacts/design/{issue-number}/test-plan.md" "{docs_repo_path}/{release}/{feature}/test-plan.md"
```

```bash
git -C "{docs_repo_path}" add "{release}/{feature}/test-plan.md"
```

```bash
git -C "{docs_repo_path}" commit -m "Add design document and test plan for {issue-number}: {title}"
```

**If `test-plan.md` was not found**, commit `design.md` alone with the
original message:

```bash
git -C "{docs_repo_path}" commit -m "Add design document for {issue-number}: {title}"
```

### Step 5: Push and Create PR

```bash
git -C "{docs_repo_path}" push -u origin design/{issue-number}
```

Read the design document and identify specific areas that warrant reviewer
attention:
- Open questions from Section 8 (list each by title)
- Sections with remaining TBD markers
- Key architectural decisions that have significant trade-offs

Prepare the PR description and save it to
`.artifacts/design/{issue-number}/07-pr-description.md`:

```markdown
## Design: {title}

**Jira:** {issue-link}
**PRD:** {link to PRD PR or file, if available}
**Test Plan:** {"Included — test-plan.md" if published in this PR, or
"Not yet published — pending /decompose" if omitted}

### Summary
{2-3 sentence summary of the design approach}

### Requesting Review On
{Populate from the design document. If there are open questions, TBD
markers, or significant trade-offs, list each as a bullet. If none
exist, write "General review — no specific items flagged."}

{If test-plan.md was published in this PR, add: "Also review test-plan.md
for test-case completeness and specificity — every acceptance criterion
should map to at least one concrete, assertion-shaped test case."}

### How to Review
- Comment inline on specific sections
- Approve when the design accurately reflects a viable implementation approach
```

Determine `{owner}/{repo}` from `docs_repo_remote`, then create the draft PR:

```bash
gh pr create --draft --repo {owner}/{repo} --base {base-branch} --head design/{issue-number} --title "Design: {title}" --body-file .artifacts/design/{issue-number}/07-pr-description.md
```

### Step 6: Save Publish Metadata

Write `.artifacts/design/{issue-number}/publish-metadata.json`. Include
`test_plan_file_path` only if `test-plan.md` was published in this round —
`/design:respond` and `/design:sync` both need this field to know where
their own updates to the published test plan go:

```json
{
  "release": "{release}",
  "feature": "{feature}",
  "design_file_path": "{release}/{feature}/design.md",
  "test_plan_file_path": "{release}/{feature}/test-plan.md",
  "pr_number": {pr-number},
  "branch": "design/{issue-number}"
}
```

{Omit `test_plan_file_path` entirely if test-plan.md wasn't published —
don't write it as null or empty string; its absence from this file is what
tells `/respond` and `/sync` there's nothing to update yet.}

### Step 7: Report to User

Present:
- PR URL
- Docs repo and branch name
- File location(s) in the docs repo (design doc, and test plan if included)
- Next steps (share with reviewers, wait for comments, then use `/respond`)
- If the test plan wasn't included: remind the user to run `/decompose`
  and re-publish before `/sync`, since `/sync` can only update an
  already-published test plan, not create one

## Output

- `.artifacts/prd/config.json` (created if it didn't exist)
- `.artifacts/design/{issue-number}/publish-metadata.json`
- Design document (and test plan, if it existed) committed and pushed to
  feature branch in the docs repo
- Draft PR created against the docs repo
- `.artifacts/design/{issue-number}/07-pr-description.md`

## When This Phase Is Done

Report your results:
- PR URL and branch name
- Docs repo and file location(s)
- Whether the test plan was included, or still pending `/decompose`
- Suggested next steps

Then **re-read the controller** (`controller.md`) for next-step guidance.
