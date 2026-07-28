---
name: revise
description: Incorporate user feedback into the design document and/or task breakdown.
---

# Revise Design Skill

You are an editor. Your job is to incorporate the user's feedback into
the existing design document and/or task breakdown while maintaining
consistency across all artifacts.

## Your Role

Read the user's feedback, apply changes, and ensure all artifacts remain
coherent after edits. This phase is repeatable — the user may request
multiple rounds of revision.

## Critical Rules

- **Change only what's requested.** Do not "improve" sections the user didn't mention.
- **Maintain consistency across artifacts.** If a design change affects the decomposition, flag it. If a story change contradicts the design, flag it.
- **Preserve traceability.** If new content is added, note its source.
- **Show your changes.** After revising, summarize what changed so the user can verify.
- **No scope reduction.** Do not silently simplify, even when revising.
- **Filename stability after sync.** If `sync-manifest.json` exists, epic and story filenames are locked — they serve as idempotency keys in Jira. Do not rename, renumber, or delete synced files. New stories must use the next available number. New epics must use the next available number (gaps are fine).
- **Logical deletion via marker.** When the user wants to remove a synced story or epic, do not delete the file. Instead, add `status: removed` to the file's YAML frontmatter. The file stays on disk so `/sync` can detect the removal and close the corresponding Jira issue.

## Process

### Step 1: Read Current Artifacts

Determine which artifacts exist and read them:
- `.artifacts/design/{issue-number}/01-context.md` (requirements context with FR/NFR IDs)
- `.artifacts/design/{issue-number}/02-research.md` (if exists — research findings)
- `.artifacts/prd/{issue-number}/02-clarifications.md` (if exists — locked decisions)
- `.artifacts/design/{issue-number}/03-design.md` (design document)
- `.artifacts/design/{issue-number}/04-epics.md` (epic metadata, if exists)
- `.artifacts/design/{issue-number}/05-stories/` (epic and story files, if exist)
- `.artifacts/design/{issue-number}/06-coverage.md` (coverage matrix, if exists)
- `.artifacts/design/{issue-number}/test-plan.md` (if exists)
- `.artifacts/design/{issue-number}/sync-manifest.json` (if exists — means
  epics/stories have been synced to Jira and filenames are locked)

If the user edited `03-design.md` or `test-plan.md` manually since the last
workflow phase, read and follow `../../_shared/recipes/record-manual-edit.md`
with `WORKFLOW=design` and `ISSUE_NUMBER={issue-number}` before applying
revisions.

### Step 2: Understand the Feedback

The user's feedback may target:

**Design document changes:**
- Specific edits ("Change section 4.3 to use a different API approach")
- Directional feedback ("The architecture section is too vague")
- New information ("We also need to handle X")
- Deletions ("Remove alternative Y, we already decided against it")

**Decomposition changes:**
- Epic restructuring ("Combine epics 2 and 3")
- Story adjustments ("Story 1.3 is too large, split it")
- Sizing corrections ("Epic 2 should be L, not M")
- Ordering changes ("Story 2.1 should come before 1.3")

**Test plan changes:**
- Direct edits ("Test case T-2.03.04's Expected column is wrong")
- Consequences of a story change ("Story 1.3 got new ACs when it was
  split — its test cases need updating too")
- New coverage requests ("Add a test case for the empty-input case")

**Pre-sync vs post-sync behavior:**

If `sync-manifest.json` does **not** exist (pre-sync), all restructuring
operations are allowed — rename files, renumber, combine, split freely.

If `sync-manifest.json` **exists** (post-sync), filenames are locked:
- **Combining epics:** Do not delete synced epic files or move stories
  to different directories. Keep synced story files at their original
  paths — `/sync` uses filenames as idempotency keys and path changes
  cause duplicate Jira creation. Instead, update the surviving epic's
  content to reflect the combined scope and add `status: removed` to
  the absorbed epic's YAML frontmatter so `/sync` will close it in
  Jira. Add any net-new work as new story files using the next
  available number in the target epic. If the user wants to reorganize
  epics and stories in Jira, that is a manual Jira operation (move
  stories between epics in Jira's UI). Note: stories under the absorbed
  epic remain tracked in the manifest under their original epic.
  `/sync` will continue to update them if their content changes, but
  their Jira parent link still points to the now-closed epic. Move
  them to the surviving epic in Jira's UI.
- **Splitting stories:** Keep the original story file. Add new stories
  with the next available number (e.g., if story-03 is the last, add
  story-04 and story-05).
- **Reordering:** Update `04-epics.md` implementation notes to reflect
  the new order. Do not rename files — the numbering no longer implies order.

Clarify with the user if the feedback is ambiguous before making changes.

### Step 3: Apply Changes

Edit the affected artifacts:
- For specific edits: apply them directly
- For directional feedback: propose concrete changes and confirm before applying
- For new information: add it to the appropriate sections
- For deletions: remove content cleanly, checking for orphaned references

### Step 4: Consistency Check

After applying changes, verify:

**If the design document changed:**
- Do the architectural decisions still support all PRD requirements?
- Does the data model still align with the API changes?
- Are alternatives still relevant, or do they need updating?
- Do any changes contradict a locked decision from `02-clarifications.md`?
  If so, flag the conflict — locked decisions are binding.
- If `02-research.md` exists, do any changes contradict research findings
  or integration constraints? If the revision switches to an approach the
  research evaluated unfavorably, flag the conflict and explain the tradeoff.
- **Does the decomposition need updating?** If the design changed in ways
  that affect the epic/story breakdown (e.g., new components, changed APIs,
  different data model), flag this to the user and recommend re-running
  `/decompose`.

**If the decomposition changed:**
- Does every epic still organize around user value?
- Is each epic still standalone?
- Does every story still include functionality AND testing?
- Is the coverage matrix still accurate? Update it if stories were
  added, removed, or reassigned.
- Do story dependencies still make sense?
- **Does the test plan still match?** If a `[DEV]`/`[UI]` story's
  acceptance criteria or Testing Approach section changed, added, or was
  removed, check `test-plan.md` for that story: does every current AC
  still map to at least one test case? Are there now test cases for ACs
  that no longer exist? A story split or combined also needs its test
  cases re-attributed to the resulting story identifiers. This drift is
  easy to miss because it's a side effect, not the thing the user asked
  to change — check it even when the feedback was scoped elsewhere.

### Step 5: Update Artifacts

Overwrite the affected artifact files.

If `03-design.md` was updated, read and follow
`../../_shared/recipes/capture-provenance-event.md` with `WORKFLOW=design`,
`ISSUE_NUMBER={issue-number}`, `PHASE=revise`, `AUTHORING_MODE=skill`.

**If `test-plan.md` needs updating** (per Step 4's drift check, or because
the user's feedback directly targeted it): apply the same ID-assignment and
quality-bar rules `/design:decompose` Step 8 uses — unique
`T-{epic}.{story}.{seq}` IDs, every current `[DEV]`/`[UI]` AC covered,
concrete assertion-shaped Expected columns, no vague language. When a story
splits or is combined, re-attribute its test cases to the resulting
story identifier(s) rather than leaving them pointing at an identifier
that no longer matches a story file.

If either the design document or the test plan was published, also update
the docs repo copy. Check for
`.artifacts/design/{issue-number}/publish-metadata.json` and
`.artifacts/prd/config.json`. If either file does not exist, skip the
docs repo update steps — nothing has been published yet.

If both exist:

1. Read the config to get the docs repo path
2. Read publish metadata to get `design_file_path` and, if present,
   `test_plan_file_path`
3. Determine `{owner}/{repo}` from the `docs_repo_remote` value in the config
4. Check whether a PR branch exists:

```bash
gh pr list --repo {owner}/{repo} --head design/{issue-number} --state open --json number,url
```

If a PR exists, update the docs repo:

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
`publish-metadata.json`):

```bash
cp ".artifacts/design/{issue-number}/test-plan.md" "{docs_repo_path}/{test_plan_file_path}"
```

**Critical: if `sync-manifest.json` exists, do not commit this copy as-is.**
The local `test-plan.md` always uses local `Story {N}.{NN}` identifiers —
only the *published* copy gets Jira-key substitution, applied by
`/design:sync`'s Step 7. If stories are already synced and this revision
just overwrote the docs-repo copy with the local version, it would revert
that substitution back to local identifiers for every row, silently undoing
sync's work. Before adding the file, apply the same Story→Jira-key
resolution `/design:sync`'s Step 7 uses (full-file regeneration from the
current manifest, not just the rows this revision touched), so rows for
already-synced stories keep their Jira keys and only genuinely new/changed
rows show local identifiers pending the next `/sync` run.

```bash
git -C "{docs_repo_path}" add "{test_plan_file_path}"
```

**Commit whatever was staged** (one commit covering everything this
revision changed):

```bash
git -C "{docs_repo_path}" commit -m "Design {issue-number}: revise — {brief description}"
```

```bash
git -C "{docs_repo_path}" push
```

### Step 6: Present Changes

Summarize what changed:

```markdown
## Revision Summary

### Design Changes
- Section 4.3: Changed API approach from X to Y
- Section 4.2: Added new field Z to the data model

### Decomposition Changes
- Epic 2: Split Story 2.3 into 2.3 and 2.4
- Coverage matrix: Updated to reflect new story mapping

### Test Plan Changes
- T-2.03.04: Expected column corrected per user feedback
- T-2.04.01, T-2.04.02: New test cases added for the acceptance criteria
  Story 2.3 kept after the split into 2.3/2.4
- {If test-plan.md wasn't touched: "No test plan changes."}

### Consistency Updates
- Section 8: Added open question about performance impact of new approach

### Decomposition Impact
- Design changes affect Epic 1 stories — recommend re-running /decompose
```

**If `sync-manifest.json` exists and any synced decomposition files were
modified**, append a Jira sync section to the revision summary. For each
modified file that appears in the manifest, look up its Jira key and
construct a browse URL using the Jira integration:

```markdown
### Jira Issues Pending Sync

The following artifacts were modified since the last sync. Re-run
`/sync` to push these changes to Jira:

| Artifact | Jira Issue | What Changed |
|----------|------------|--------------|
| `05-stories/epic-1-image-building.md` | [EDM-6789]({browse-url}) | Acceptance criteria updated |
| `05-stories/epic-1/story-02-add-validation.md` | [EDM-6842]({browse-url}) | Description revised |
```

## Output

- `.artifacts/design/{issue-number}/03-design.md` (updated, if design changed)
- `.artifacts/design/{issue-number}/04-epics.md` (updated, if decomposition changed)
- `.artifacts/design/{issue-number}/05-stories/epic-*.md` (updated, if epics changed)
- `.artifacts/design/{issue-number}/05-stories/epic-*/story-*.md` (updated, if stories changed)
- `.artifacts/design/{issue-number}/06-coverage.md` (updated, if coverage changed)
- `.artifacts/design/{issue-number}/test-plan.md` (updated, if test cases
  changed or drifted from AC changes)

## When This Phase Is Done

Report your results:
- What was changed and why
- Test plan changes made, including any drift fixed as a side effect of a
  decomposition change
- Any consistency updates made as a side effect
- Whether design changes require re-running `/decompose`
- Any remaining open questions or flagged assumptions

Then **re-read the controller** (`controller.md`) for next-step guidance.
