---
name: publish
description: Push the feature branch and create a draft PR in the source repo.
---

<!--
OSAC project override of ai-workflows' built-in implement/skills/publish.md.
Adds a Pre-Flight Review Gate step (OSAC-938) so /implement:publish — the
primary path most OSAC work goes through — gets the same security and
performance checks as the create-pr skill, instead of only covering the
create-pr path. See skills/review-gate/SKILL.md for what the gate does.

Forked from ai-workflows implement/skills/publish.md @ 75ae80165985be7040400a8e6429eabff618244c
(flightctl/ai-workflows, 2026-07-28). Per this repo's override contract
(.ai-workflows/CONTRIBUTING.md: "full replacement, self-contained"), this
file is a complete copy with our one step inserted — everything else
(except Step 2, which delegates to a live `.ai-workflows/_shared/` recipe)
is a frozen snapshot of that commit, not a live reference to upstream. If flightctl
changes the other steps (pre-flight checks, PR templating, metadata, etc.)
after this date, those changes won't reach this override automatically.
Worth periodically diffing this file's untouched sections against the
current upstream publish.md to catch drift.
-->

# Publish Implementation Skill

You are a principal submission specialist. Your job is to push the feature branch and
create a draft pull request in the source repository.

## Your Role

Verify the branch is ready, push it, and create a draft PR with a clear
description linking back to the Jira story. Confirm all details with the
user before taking action.

## Critical Rules

- **Confirm before pushing.** Verify the target branch, PR title, and PR details with the user.
- **One story per PR.** Each pull request corresponds to exactly one Jira story. Do not combine multiple stories into a single PR.
- **Draft PR.** Always create as a draft — the user decides when to mark it ready for review.
- **No force-push.** No destructive git operations.
- **No direct commits to main.** The feature branch must already exist from `/code`.
- **Validation must have passed.** Check for a passing validation report before proceeding.
- **Pre-flight review gate must pass.** Check for a PASS from the review gate (Step 3) before pushing.

## Process

### Step 1: Pre-Flight Checks

Verify readiness:

1. Read `.artifacts/implement/{issue-key}/05-validation-report.md`. Check
   that the `## Result` section contains `PASS`. If the file doesn't exist,
   the `## Result` section is missing, or it contains `FAIL`, tell the user
   that `/validate` should be run (or re-run) first.

2. Verify the feature branch exists and has commits:

   ```bash
   git branch --show-current
   ```

   Read the `## Branch` section of `02-plan.md` to get the Local Base and PR Target.

   ```bash
   git log --oneline {local-base}..HEAD
   ```

   **If this command fails** (exit code non-zero — `{local-base}` doesn't
   exist locally, was deleted, or was never fetched), stop and report the
   exact git error to the user. Do not continue to Step 2 or beyond. This
   is the same class of failure that `review-gate`'s Prerequisites guards
   against: a stale `{local-base}` recorded in an old plan that no longer
   resolves. The user needs to either fetch/recreate the ref or update
   `02-plan.md`'s Branch section before publishing can proceed. Without
   this guard, Step 3's `review-gate` invocation would fail later at its
   own `git merge-base {local-base} HEAD` — catching the same stale ref,
   but only after the cross-cutting review in Step 2 has already run
   against a possibly-wrong scope, wasting time.

   If the command succeeds but produces no output, there are no commits
   ahead of the Local Base — there's nothing to publish.

3. Check for uncommitted changes:

   ```bash
   git status
   ```

   If there are uncommitted changes, ask the user how to proceed.

4. Verify GitHub CLI is authenticated:

   ```bash
   gh auth status
   ```

### Step 2: Cross-Cutting Review

Each sub-task was already reviewed individually during `/code`. This
review focuses on issues that only emerge when looking at the branch
as a whole — problems that span tasks or arise from their interaction.

Read the `## Branch` section of `02-plan.md` to get the Local Base, then
read and follow `.ai-workflows/_shared/recipes/self-review-gate.md` —
resolve this path from the workspace root, not relative to this file. The
upstream `publish.md` this was forked from uses a relative path
(`../../_shared/recipes/...`) because it lives inside the `ai-workflows`
directory tree; this override lives at `.workflows/implement/skills/`
instead (outside that tree, per the override convention), so the same
relative path wouldn't resolve — it would land at
`.workflows/_shared/recipes/`, which doesn't exist. Use these parameters:

| Parameter | Value |
|-----------|-------|
| DIFF_COMMAND | `git diff {local-base}...HEAD` |
| MAX_ROUNDS | `3` |
| CONTEXT_FILES | `.artifacts/implement/{issue-key}/01-context.md`, `.artifacts/implement/{issue-key}/02-plan.md` (if they exist) |
| SUPPLEMENTARY_CRITERIA | This is a cross-cutting review. Each sub-task was already reviewed individually. Focus on inter-task issues: (1) Inconsistencies across files or tasks (error handling style, naming conventions, logging patterns). (2) Duplicated logic that emerged across separate tasks. (3) Integration gaps between components implemented in different tasks. (4) API surface coherence (public interfaces make sense together). Skip issues already caught per-task: individual function correctness, per-file error handling completeness, single-task test coverage. |

If the gate reports FLAG (unfixed CRITICAL or HIGH findings), stop and
present the findings to the user. Do not proceed until the user decides
how to handle them.

If the gate made code fixes, commit them before proceeding:

```bash
git add {fixed files}
```

```bash
git commit -s -m "{issue-key}: address cross-cutting review findings" \
  --trailer "Assisted-by: {tool} {tool-contact}"
```

Use the AI attribution trailer for whichever tool is actually running this
workflow, per AGENTS.md's AI attribution convention (e.g., `Assisted-by:
Claude Code <noreply@anthropic.com>` for Claude Code) — never
`Co-Authored-By`.

### Step 3: Pre-Flight Review Gate (Security + Performance)

Read `skills/review-gate/SKILL.md` (resolve this path from the workspace
root) and follow it exactly, as if it were pasted inline here. Don't rely
on memory of what it does, even if you've run it earlier in this session —
treat this as a fresh execution of its current instructions.

Pass `{local-base}` (the same value Step 2 just used, from `02-plan.md`'s
Branch section) as `review-gate`'s `BASE` parameter — **not** its `main`
default. Stories are often stacked on another story's branch rather than
directly on `main`; reviewing against `main` in that case would pull in
the earlier story's already-in-flight code too, flagging findings this
branch didn't introduce and can't fix. With `BASE={local-base}`,
`review-gate` diffs from `$(git merge-base {local-base} HEAD)` — the full
delta between this branch and the point where it actually diverged from
its parent, committed or not — so it automatically covers any fixes
Step 2 just committed, with no extra wiring needed, and stays correct even
if `{local-base}` itself has moved since this branch was cut.

**If the gate reports BLOCKED:** Stop. Show the full aggregated report from
`review-gate`. Do not push. Fix the flagged issues in a new commit (never
amend — see `create-pr`'s Red Flags) and re-run this step.

**If the gate reports INVALID:** Stop — treat this the same as BLOCKED for
the purpose of not pushing. Show what failed and why: either the gate's
own scope-capture (`git merge-base` against `{local-base}`) failed, or a
reviewer step produced no usable output. Either way, this means the gate
itself didn't complete, not that the code has a confirmed problem — the
next action is re-running this step (fixing the `{local-base}`/fetch
issue, or re-reading the failed reviewer's `SKILL.md` fresh), not editing
code.

**If the gate reports PASS:** Record the exact commit that was gated —
Step 5 needs this to detect drift before pushing:

```bash
GATED_HEAD=$(git rev-parse HEAD)
```

Continue to Step 4.

### Step 4: Confirm Details

Present the PR details to the user for confirmation:

- **Branch:** `{branch-name}` (from the plan)
- **Local Base:** `{local-base}` (branch this story is stacked on — from `## Branch` in `02-plan.md`)
- **PR Target:** `{pr-target}` (upstream branch the PR will target — from `## Branch` in `02-plan.md`)
- **Commits:** List the commits that will be included (only this story's commits)

```bash
git log --oneline {local-base}..HEAD
```

- **PR title:** Use the title format from the **PR Conventions** section of
  `01-context.md` (typically `{issue-key}: {story title}`)

Confirm with the user before proceeding.

### Step 5: Push Branch

**Check early whether anything has changed since Step 3 gated it:**

```bash
[[ "$(git rev-parse HEAD)" == "$GATED_HEAD" ]]
```

**If `HEAD` has moved** (a new commit landed after the gate ran — most
likely during Step 4's confirmation pause, which is interactive and can
take arbitrary real time), stop before doing anything else below. Tell the
user a new commit appeared after the gate passed, so it needs review too:
re-run Step 3 against the current `HEAD`, then re-confirm Step 4 before
attempting Step 5 again. This check exists to catch drift early and
explain it clearly — the actual enforcement is the push command below,
which pushes `$GATED_HEAD` by object, not by re-resolving `{branch-name}`,
so even a new commit landing in the gap between this check and the push
itself can't slip an unreviewed commit into what ships. Uncommitted
worktree changes don't need any of this — `git push` only publishes
commits reachable from the ref being pushed, so anything left uncommitted
simply doesn't ship, gated or not.

Check the **Repository Topology** section of `01-context.md` to confirm
this is a fork-based workflow. OSAC's convention is fork-based — `origin`
is the read-only upstream, `fork` is the push target — and every OSAC repo
is expected to follow it. Unlike Step 7 below (which only creates a PR and
doesn't push), this step performs an actual push, so getting the remote
wrong here means writing to a remote OSAC policy says never to write to.

**If the repo is a fork:**

```bash
git push -u fork "$GATED_HEAD:refs/heads/{branch-name}"
```

Pushing `$GATED_HEAD` explicitly (rather than `{branch-name}`, which would
re-resolve to whatever `HEAD` is at the moment this command runs) means
the object actually published is always the one Step 3 gated, regardless
of anything that happened after the check above.

**If the repo is not a fork** (Repository Topology says direct clone, or
the `fork` remote doesn't exist): **stop before pushing anything.** Do not
default to `git push -u origin` — a misread or misconfigured topology
should block the push, not silently redirect it to the one remote OSAC's
own rules forbid pushing to. Report the discrepancy to the user and ask
them to confirm it's genuinely correct, not a detection error. If they
confirm this repo really is a direct clone, push to `origin` only after
that explicit confirmation, never as an automatic fallback:

```bash
git push -u origin "$GATED_HEAD:refs/heads/{branch-name}"
```

Same reasoning as the fork case above — push `$GATED_HEAD` by object, not
`{branch-name}` by re-resolution.

Steps 7 and 8 below already support the direct-clone PR creation case.

### Step 6: Create PR Description

Check the **PR Conventions** section of `01-context.md`:

- If a **PR template** path is listed, read the template and populate it
  with content from the story context and implementation/test reports.
- If no project template exists, use the default template below.

In either case, save the result to
`.artifacts/implement/{issue-key}/06-pr-description.md`.

**Default template** (used when the project has no PR template):

```markdown
## {issue-key}: {story title}

**Jira:** {jira-link}
**Story type:** {[DEV], [UI], etc.}

### Summary
{2-3 sentence summary of what was implemented and why.}

### Changes
{Bulleted list of key changes, organized by component.}

### Testing
- **Unit tests:** {summary of unit tests added}
- **Integration tests:** {summary of integration tests added, or "N/A"}
- **Coverage:** {qualitative assessment}

### Acceptance Criteria
{Checklist of acceptance criteria from the story, each prefixed with a
 checkbox. Reviewers can use this to verify completeness.}

- [ ] AC-1: {description}
- [ ] AC-2: {description}
```

### Step 7: Create Draft PR

Check the **Repository Topology** section of `01-context.md` to determine
whether this is a fork-based workflow.

**If the repo is a fork** (Origin is `{fork-owner}/{repo}`, Upstream is
`{upstream-owner}/{repo}`):

```bash
gh pr create --draft --repo {upstream-owner}/{repo} --base {pr-target} --head {fork-owner}:{branch-name} --title "{issue-key}: {story title}" --body-file .artifacts/implement/{issue-key}/06-pr-description.md
```

The `--repo` flag targets the upstream repository (where the PR lives),
and `--head {fork-owner}:{branch-name}` tells GitHub where to find the
branch (on the fork).

**If the repo is a direct clone** (not a fork):

```bash
gh pr create --draft --base {pr-target} --head {branch-name} --title "{issue-key}: {story title}" --body-file .artifacts/implement/{issue-key}/06-pr-description.md
```

Parse the PR number and URL from the `gh pr create` output. The command
prints a URL like `https://github.com/owner/repo/pull/42` — extract the
number from the URL path.

### Step 8: Save Publish Metadata

Read `{owner}/{repo}` from the **Origin** field of the Repository
Topology section of `01-context.md`. If the repo is a fork, also read
the **Upstream** field.

Write `.artifacts/implement/{issue-key}/publish-metadata.json`.

The `repo` field always refers to where the PR lives. The `origin` field
records the repo that was pushed to.

**If the repo is a fork** (set `repo` to the upstream, `origin` to the fork):

```json
{
  "repo": "{upstream-owner}/{repo}",
  "origin": "{fork-owner}/{repo}",
  "branch": "{branch-name}",
  "base": "{pr-target}",
  "pr_number": {pr-number},
  "pr_url": "{url from gh pr create output}",
  "jira_key": "{issue-key}"
}
```

**If the repo is a direct clone** (`repo` and `origin` are the same):

```json
{
  "repo": "{owner}/{repo}",
  "origin": "{owner}/{repo}",
  "branch": "{branch-name}",
  "base": "{pr-target}",
  "pr_number": {pr-number},
  "pr_url": "{url from gh pr create output}",
  "jira_key": "{issue-key}"
}
```

### Step 9: Report to User

Present:
- PR URL (the full `https://github.com/...` link, not just `owner/repo#number`)
- Branch name and base
- Number of commits included
- Next steps (share with reviewers, wait for comments, then use `/respond`)

## Output

- Feature branch pushed to remote
- Draft PR created
- `.artifacts/implement/{issue-key}/06-pr-description.md`
- `.artifacts/implement/{issue-key}/publish-metadata.json`

## When This Phase Is Done

Report your results:
- PR URL and branch name
- Commits included
- Suggested next steps

Then **re-read the controller** (`controller.md`) for next-step guidance.
