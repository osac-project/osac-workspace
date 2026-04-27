---
name: generate-ep
description: |
  Generate OSAC enhancement proposals from high-level requirements, meeting notes, or Jira tickets.
  Trigger when: "create an EP", "draft an enhancement proposal", "write up a proposal",
  "turn these notes into an EP", "formalize this as an enhancement", or user provides
  requirements/notes and asks to create a formal proposal.
---

# OSAC Enhancement Proposal Generator

Transform rough requirements into a formal Enhancement Proposal following the
osac-project/enhancement-proposals template — then submit it as a PR.

## Modes

- `/generate-ep` — interactive: describe what you want to propose
- `/generate-ep <path-to-notes.md>` — from a file (meeting notes, requirements doc)
- `/generate-ep MGMT-XXXXX` — from a Jira ticket
- `/generate-ep review-feedback <PR#>` — address reviewer comments on an existing EP PR

## Workflow

### 1. Detect Input

Verify the `enhancement-proposals/` directory exists. If not, tell the user to run `./bootstrap.sh` and stop.

Determine input mode from `$ARGUMENTS`:
- **Jira ticket** (`MGMT-\d+`): check `command -v jira` first. If jira CLI is not installed, tell the user to install it (`https://github.com/ankitpokhrel/jira-cli`) or provide the requirements as text instead. If available, fetch via `jira issue view MGMT-XXXXX --plain`
- **File path**: read via Read tool
- **No args / free text**: use conversation context — ask user to describe the feature

### 2. Explore Codebase

Targeted exploration for the specific feature being proposed. Read `references/osac_conventions.md`
for repo layout, then search for related patterns:

```bash
rg --type proto "<resource>" --files-with-matches   # related proto schemas
rg "reconcile.*<Resource>" --type go -l              # related controllers
ls enhancement-proposals/enhancements/               # existing EPs for reference
```

Keep exploration narrow — use `--files-with-matches` first, then selectively read.

### 3. Clarify Unknowns (MANDATORY)

**STOP.** Present what you found and what you need to know. Do not draft until the user answers.

1. **What I found:** patterns, existing implementations, architectural constraints
2. **What I need to know:** list all open questions, then iterate through them one by one with the user. Present each question separately and wait for the answer before moving to the next. Example: "I have 8 open questions. Let's go through them one at a time."
3. **Wait for answers** — if user says "just draft it", push back on the most critical unknowns

### 4. Draft EP

Read the upstream template directly from the cloned repo — it is the single source of truth:

```bash
cat enhancement-proposals/guidelines/enhancement_template.md
```

Then read `references/ep_template.md` for section completion guidance (how to fill each section well).
Read `references/review_patterns.md` to anticipate reviewer expectations.

- Create `enhancement-proposals/enhancements/<feature-slug>/README.md`
- Fill ALL sections — use substantive placeholders where details depend on implementation
- Follow the YAML frontmatter format (title, authors, creation-date, tracking-link)

### 5. Submit PR

Semi-automatic — prepare locally in a git worktree, confirm with user before pushing.

```bash
cd enhancement-proposals
git worktree add ../enhancement-proposals-<feature-slug> -b enhancement/<feature-slug>
cd ../enhancement-proposals-<feature-slug>
mkdir -p enhancements/<feature-slug>
# Write enhancements/<feature-slug>/README.md
git add enhancements/<feature-slug>/README.md
git commit -m "MGMT-XXXXX: Add <feature-name> enhancement proposal"
```

Show the user: title, body, branch, files. Ask "Push and create PR?" before:

```bash
git push -u origin enhancement/<feature-slug>
gh pr create --repo osac-project/enhancement-proposals \
  --title "MGMT-XXXXX: Add <feature-name> enhancement proposal" \
  --body "<summary + motivation + tracking link>"
```

After the PR is created, clean up the worktree:

```bash
cd ../enhancement-proposals
git worktree remove ../enhancement-proposals-<feature-slug>
```

### 6. Review Feedback (mode: `review-feedback <PR#>`)

```bash
gh pr view <PR#> --repo osac-project/enhancement-proposals --json reviews,comments
```

Parse feedback, propose changes, update the EP, commit and push.

## Prerequisites

| Tool | Check | Fix |
|------|-------|-----|
| gh | `gh auth status` | `gh auth login` |
| jira (optional) | `jira me` | `jira init` (only needed for Jira ticket mode) |
| rg | `rg --version` | Install [ripgrep](https://github.com/BurntSushi/ripgrep#installation) |
| Repos | `ls enhancement-proposals/` | `./bootstrap.sh` |

## Reference Files

- `references/ep_template.md` — section completion guide (template itself is read from `enhancement-proposals/guidelines/enhancement_template.md`)
- `references/review_patterns.md` — common reviewer expectations from past EP PRs
- `references/osac_conventions.md` — OSAC repo layout, EP/PR/Jira conventions
