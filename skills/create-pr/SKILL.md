---
name: create-pr
description: Create a PR on an OSAC component repo (including the osac mono-repo, which may need per-component validation for multiple touched components in one pass) using the fork-based workflow. Runs repo-specific validation (build, test, lint), pushes to the developer's push remote, and opens a PR against the upstream repo with proper title format. Use when the user says 'create PR', 'open PR', 'submit for review', 'push and create PR', or when finishing a feature branch.
metadata:
  version: "0.1.0"
---

# Create Pull Request

Create a PR on an OSAC component repo using the fork-based workflow.

**Announce at start:** "Using the create-pr skill to validate and submit a PR."

## Prerequisites

- `gh` CLI authenticated (`gh auth status`)
- A push remote configured (developer's personal repo — the push target)
- Commits on a feature branch, not `main`
- `tools/resolve-remotes.sh` available (run from `osac-workspace`)

## Step 1: Detect Context

Determine which component repo you're in and gather branch state.

```bash
REPO_DIR=$(git rev-parse --show-toplevel)
BRANCH=$(git branch --show-current)
```

**Resolve remote names** before deriving the repo name or running gate checks:

```bash
WORKSPACE_ROOT="$REPO_DIR"
[[ -f "$WORKSPACE_ROOT/tools/resolve-remotes.sh" ]] || WORKSPACE_ROOT="$REPO_DIR/.."
WORKSPACE_ROOT=$(cd "$WORKSPACE_ROOT" && git rev-parse --show-toplevel 2>/dev/null || echo "$WORKSPACE_ROOT")
_resolve_out=$("${WORKSPACE_ROOT}/tools/resolve-remotes.sh" "$REPO_DIR") || {
  echo "Failed to resolve remotes. Run tools/resolve-remotes.sh --print to diagnose."
  exit 1
}
eval "$_resolve_out"
```

`$REPO_DIR` may itself already be the workspace root (e.g. running `create-pr`
from `osac-workspace` directly, not a component subdirectory) — check for
`tools/resolve-remotes.sh` there first before falling back to the parent,
the same self-check-then-fallback idiom Step 4.1 uses for `$SKILLS_ROOT`.

This sets `$UPSTREAM_REMOTE` (the osac-project remote) and `$PUSH_REMOTE` (developer's push target). Run `tools/resolve-remotes.sh --print` to see current detection.

```bash
# Derive from the resolved upstream remote, not $(basename "$REPO_DIR") -- a
# worktree's directory name (e.g. ../osac-feature-branch, per
# cross-repo-workflow.md) doesn't match the repo name, which would silently
# skip mono-repo component detection below. Also not remote.origin.url
# directly -- resolve-remotes.sh already found the real upstream remote by
# URL/org, not by assuming it's named "origin".
REPO_NAME=$(git -C "$REPO_DIR" remote get-url "$UPSTREAM_REMOTE")
REPO_NAME="${REPO_NAME##*/}"
REPO_NAME="${REPO_NAME%.git}"
```

**Gate checks — stop if any fail:**

| Check | Command | Fail action |
|-------|---------|-------------|
| Not on main | `[[ "$BRANCH" != "main" ]]` | Stop: "You're on main. Create a feature branch first." |
| Push remote exists | `git remote get-url "$PUSH_REMOTE"` | Stop: "No push remote detected. Run `tools/resolve-remotes.sh --print` to diagnose. You may need to add one: `git remote add fork git@github.com:<user>/\<repo>.git`" |
| Has commits ahead of main | `git log main..HEAD --oneline` | Stop: "No commits ahead of main. Nothing to submit." |
| Clean working tree | `git status --porcelain` | Stop: "Uncommitted changes detected. Commit or stash before proceeding." |

### Mono-repo component detection

`osac` is a mono-repo containing `fulfillment-service`, `osac-operator`,
`osac-aap`, `osac-installer`, `bare-metal-fulfillment-operator`, and
`osac-csi-driver` as subdirectories — a single PR can touch more than one of
them. When `$REPO_NAME` is `osac`, detect which subdirectories this branch
actually touches instead of assuming a single component:

```bash
# Keep the (fulfillment-service|osac-operator|osac-aap|osac-installer|
# bare-metal-fulfillment-operator|osac-csi-driver) list in sync with
# bootstrap.sh's MERGED_COMPONENTS array, references/file-classification.md
# (Step 3), and references/validation-commands.md's per-component
# "### <name>" sections (Step 2) if a future component merges into osac or
# one of these splits out.
if [[ "$REPO_NAME" == "osac" ]]; then
  # Diff from the merge-base, not a raw two-ref diff against main's current
  # tip — the same reasoning review-gate's Step 1 documents in full: if
  # main has gained unrelated commits since this branch diverged, a raw
  # `git diff main..HEAD` pulls those in too, misclassifying which
  # components this branch actually touched.
  #
  # Split the merge-base, diff, and filter into separate steps: a `git
  # merge-base`/`git diff` failure must still propagate under
  # `set -e`/`pipefail`, but "no merged-component subdirectory touched" is
  # a valid, empty-string-producing outcome — awk exits 0 on zero matching
  # lines, so no trailing `|| true` is needed (which would otherwise mask a
  # genuine `git diff` failure too).
  MERGE_BASE_FOR_COMPONENTS=$(git merge-base main HEAD)
  CHANGED_PATHS=$(git diff "$MERGE_BASE_FOR_COMPONENTS" --name-only)
  TOUCHED_COMPONENTS=$(printf '%s\n' "$CHANGED_PATHS" \
    | awk -F/ '$1 ~ /^(fulfillment-service|osac-operator|osac-aap|osac-installer|bare-metal-fulfillment-operator|osac-csi-driver)$/ { print $1 }' \
    | sort -u)
else
  TOUCHED_COMPONENTS="$REPO_NAME"
fi
```

`$TOUCHED_COMPONENTS` may list zero, one, or multiple names. Use it in Steps 2
and 3 to select which per-component block(s) apply — run every matching block,
not just the first. If it's empty because the change is purely doc/config
outside all six subdirectories (e.g. `osac/README.md`), skip the
component-specific parts of Steps 2 and 3. If it's empty but the change
touches root-level files that affect multiple components' builds (e.g.
`osac/go.work`, a root `Makefile`, `.github/workflows/`), don't skip
validation entirely — read `osac`'s own `AGENTS.md`/`CLAUDE.md` for the
correct root-level check (a broken `go.work` can break both
`fulfillment-service` and `osac-operator` builds without either
component's own validation block catching it).

## Step 2: Run Validation

Run the checks for every component in `$TOUCHED_COMPONENTS` **before**
pushing. See [validation-commands.md](references/validation-commands.md)
(**read before running this step**) for the exact per-component
build/lint/test commands — if `$TOUCHED_COMPONENTS` lists more than one,
run **every** matching block in the same pass; that's the point of one PR
covering multiple mono-repo components.

**If any check fails:** Stop. Show the failure output. Do not proceed to push.

**If all checks pass:** Continue to Step 3.

## Step 3: Check Test Coverage

Analyze the diff to detect production code changes that lack corresponding test changes. This is **advisory only** — it warns but does not block PR creation.

Compute the merge-base first — same fail-closed pattern as `review-gate`'s
Prerequisites:

```bash
MERGE_BASE=$(git merge-base main HEAD)
```

If this command fails, stop and report the error — do not continue with an
empty or missing merge-base. Step 1 already validated that `main` exists,
so a failure here indicates a deeper problem (e.g., unrelated histories).

Then list the changed files:

```bash
git diff "$MERGE_BASE" --name-only --diff-filter=AMR
```

Classify each changed file using the component-specific rules in
[file-classification.md](references/file-classification.md) (**read
before running this step**) — for `osac`, only apply the row(s) matching
`$TOUCHED_COMPONENTS`.

**If gaps exist**, print a warning and continue:

```
⚠️  Test coverage gaps detected:

| Production file changed | Expected test file |
|------------------------|--------------------|
| fulfillment-service/internal/servers/foo_server.go | fulfillment-service/internal/servers/foo_server_test.go |

These files were added or modified without corresponding test changes.
This is a warning — proceeding with PR creation.
```

**If no gaps**, print: "✅ Test coverage looks good — all changed production files have corresponding test changes."

**Always continue to Step 4** regardless of the result.

## Step 4: Pre-Flight Review Gate

Run the configured reviewers (`skills/.config/create-pr-reviewers.yaml`) in
parallel before pushing. This is the last local check before anything
leaves the machine — it runs after validation (Step 2) and the coverage
advisory (Step 3), since either of those can still prompt more edits, and
right before push (Step 5).

By this point the working tree is already clean and everything is committed
(Step 1's gate check requires that). Each reviewer diffs from
`$(git merge-base {base} HEAD)`, run against `$REPO_DIR` (see Step 4.1's
`{repo_dir}`), using its own config `base` (default `main`) — so it reviews
exactly the commits about to be pushed even if `{base}` has advanced since
this branch was created.

Reviewers are defined in `skills/.config/create-pr-reviewers.yaml`, not
hardcoded here — see
[reviewer-config.md](references/reviewer-config.md) (**read before running
Step 4.1**) for the schema, path resolution, validation checklist, and
output contract.

### 4.1: Validate Config and Launch Reviewers in Parallel

Resolve this feature's own workspace root by following
[reviewer-config.md](references/reviewer-config.md)'s **Path Resolution**
section exactly — independent of Step 1's `$WORKSPACE_ROOT`, which is a
separate variable for a separate purpose (remote resolution, not
skill/config file reading). The canonical `$SKILLS_ROOT` resolution
snippet lives only there; don't duplicate it here.

Read `$SKILLS_ROOT/skills/.config/create-pr-reviewers.yaml` with `Read`.
Run every check in
[reviewer-config.md](references/reviewer-config.md)'s Validation
Checklist, in order. **Any failure stops here with overall verdict
`INVALID`** — no agent spawned, no push, naming exactly which check and
entry failed.

Once validation passes, for each enabled reviewer substitute `{skill}`
(the same `$SKILLS_ROOT`-resolved path used for its existence check),
`{base}` (default `main`), `{category}`, and `{repo_dir}` (`$REPO_DIR`)
into `prompt_template`. `{repo_dir}` anchors the reviewer's own git
commands to the repo being submitted — file-path resolution
(`$SKILLS_ROOT`) and git-scope anchoring (`$REPO_DIR`) are separate
concerns; both must be substituted.

Spawn **one separate background Agent subagent per enabled reviewer, all
in the same message** — one agent per reviewer, substituted prompt as its
`prompt`, never shared. If this harness cannot fan out multiple concurrent
background agents from one call, stop with overall verdict `INVALID`,
naming that limitation — never a silent sequential fallback.

```text
Agent tool calls (all enabled reviewers, same message):
  For each enabled reviewer:
    subagent_type: not specified (use <reviewer.skill>, resolved via $SKILLS_ROOT)
    prompt: <prompt_template with {skill}, {base}, {category}, {repo_dir}
             substituted for this reviewer>
```

The number of calls this produces always matches the config's enabled
entries — adding, removing, or disabling a reviewer changes it without any
edit to this file. `security-review` cannot be disabled via `enabled: false` while its entry
keeps `mandatory: true` (check 9) — but deleting the entry outright is not
itself blocked; that's an accepted limitation, not a bug.

Wait for all agents to complete. **A reviewer that hasn't returned within
10 minutes — or if this harness provides no way to detect/bound a hung
subagent's runtime at all — is `INVALID`** (see Step 4.2); there is no
option to note the limitation and keep waiting. Where the harness offers
an actual wall-clock timeout parameter on the agent-spawning tool itself,
set it to 10 minutes so a hung call is force-terminated rather than
waited on indefinitely. Where it doesn't, be honest about what a
`duration_ms`-style field (present on completion notifications in this
session) can and can't do here: it only ever arrives *after* a call
finishes, so it can flag a reviewer that eventually returned but took too
long, but it gives no signal at all for a reviewer that never returns —
there is no live/polling mechanism to check an in-flight call's elapsed
time from inside a single blocking spawn. For that genuinely-hung case,
the "no way to detect/bound a hung subagent's runtime at all" branch above
is the honest description of the situation, not a fallback this
`duration_ms` check quietly resolves.

### 4.2: Validate Outputs and Aggregate Results

For each spawned reviewer, normalize and validate its output per
[reviewer-config.md](references/reviewer-config.md)'s Output Contract —
read that section for the exact rules (the unconditional stray-`VERDICT:`
check, the leading-prose tolerance and its concrete-finding judgment call,
the single-table-shape grammar including the `NONE`/`INVALID` solo-row
rule). **Reviewers never self-report PASS or BLOCKED — only a solo
`INVALID` row.** A timeout, empty/missing output, or anything else not
matching the contract is that reviewer's result: `INVALID`.

**If any spawned reviewer's result is `INVALID`, the overall gate verdict
is `INVALID`** — name the reviewer(s) and stop. **Show every spawned
reviewer's output in the report** (raw if it didn't parse, its findings if
it did) — not only the one that failed; do not aggregate the clean
reviewers into a PASS alongside a failed one.

Only once every spawned reviewer's result validates — meaning no reviewer
reported an `INVALID` row — combine all real-finding rows
(`CRITICAL`/`IMPORTANT`/`ADVISORY`, excluding any `NONE` rows — they aren't
findings) into a single aggregated table:

```markdown
| Severity | File:Line | Category | Issue | Suggestion |
|----------|-----------|----------|-------|------------|
| ... | ... | Performance | ... | ... |
| ... | ... | Security | ... | ... |
| ... | ... | Ponytail | ... | ... |
```

"Category" uses each reviewer's config `category` — the example above shows
three rows because three reviewers are currently enabled; it grows or
shrinks with the config, not with this example.

### 4.3: Determine Overall Verdict

| Condition | Overall Verdict | Action |
|-----------|----------------|--------|
| Step 4.1 config validation failed | INVALID | Stop, report which check/entry failed |
| Any spawned reviewer's result is INVALID (Step 4.2) | INVALID | Stop, name the reviewer(s), show every reviewer's output |
| Any finding is CRITICAL or IMPORTANT | BLOCKED | Stop, show aggregated report |
| All findings are ADVISORY only, or there are no findings at all | PASS | Continue to Step 5 |

### 4.4: Gate and Report

**If INVALID:** Stop. Do not push. Every spawned reviewer's output is
shown in the report (Step 4.2), regardless of which one caused the
`INVALID`. Do not resolve an `INVALID` verdict by editing the reviewed
source, history, or git state to make a reviewer's scope computation
succeed — fix the tooling/config problem, or escalate to the user; the
reviewed change itself is not the thing to change here. Identify which
cause applies:
- **Step 4.1 config validation failed** — fix `skills/.config/create-pr-reviewers.yaml` per the reported check, then re-run Step 4.
- **A reviewer reported an `INVALID` row** — investigate the git state its explanation cell points to, then re-run Step 4.
- **A reviewer's output was unparseable, or it timed out/crashed** — check its raw output manually for any real finding (the gate could not auto-classify it), then re-run Step 4.

An empty review scope is **not** INVALID — a reviewer with nothing to
review reports a lone `NONE` row, contributing to PASS.

**If BLOCKED:** Stop. Show the full aggregated findings table with all
CRITICAL/IMPORTANT issues. Do not push. Fix the flagged issues in a new
commit (never amend — see Red Flags), then restart at Step 2.
Re-run validation, coverage analysis, and this review gate before pushing.

**If PASS (with ADVISORY findings):** Show the aggregated report with the
ADVISORY findings and note that they do not block. Continue to Step 5.

**If PASS (clean):** Report "Pre-flight review gate: PASS (no findings)."
Continue to Step 5.

## Step 5: Push to Push Remote

Always push to `$PUSH_REMOTE`, never to `$UPSTREAM_REMOTE`.

```bash
git push -u "$PUSH_REMOTE" "$BRANCH"
```

If push fails due to diverged history, do not force-push automatically. Show the push error to the user and ask them for explicit instructions on how to proceed.

## Step 6: Determine PR Title

The PR title must include the Jira ticket key if one exists.

**Format:** `<TICKET-KEY>: <short description>`

Examples:
- `OSAC-853: add AAP presubmit e2e-vmaas job`
- `MGMT-24256: add E2E test skill stubs`

Extract the ticket key from the branch name if it follows the convention (`feat/OSAC-123`, `fix/MGMT-456`):

```bash
TICKET=$(echo "$BRANCH" | grep -oE '(OSAC|MGMT)-[0-9]+' || true)
```

If no ticket key is found, ask: "Is there a Jira ticket for this work? (e.g., OSAC-123)"

If none, omit the prefix — just use a descriptive title.

## Step 7: Create PR

`fulfillment-service`, `osac-operator`, `osac-aap`, `osac-installer`,
`bare-metal-fulfillment-operator`, and `osac-csi-driver` share one remote pair
— the `osac` mono-repo — so this step creates a single PR covering every
component touched in `$TOUCHED_COMPONENTS`, not one PR per component.

Determine the upstream repo and push remote owner from the resolved remotes:

```bash
UPSTREAM=$(gh repo view $(git remote get-url "$UPSTREAM_REMOTE") --json nameWithOwner -q .nameWithOwner)
FORK_OWNER=$(gh repo view $(git remote get-url "$PUSH_REMOTE") --json owner -q .owner.login)
```

Construct the title from the ticket key and a short description (ask the user if unclear):

```bash
PR_TITLE="${TICKET:+$TICKET: }<short description>"
```

Create the PR from `$PUSH_REMOTE` to upstream. Replace `<SKILL_VERSION>` in the trailer with this skill's `metadata.version` value:

```bash
gh pr create \
  --repo "$UPSTREAM" \
  --head "$FORK_OWNER:$BRANCH" \
  --base main \
  --title "$PR_TITLE" \
  --body "$(cat <<'EOF'
## Summary
<1-3 bullet points describing what changed and why>

## Jira
<link to Jira ticket, or "N/A">

## Test plan
- [ ] <verification steps taken>
- [ ] Unit tests pass
- [ ] Lint/format checks pass

---

_This PR description was drafted with AI assistance ([create-pr](https://github.com/osac-project/osac-workspace/tree/main/skills/create-pr) v<SKILL_VERSION>). Review for accuracy_
EOF
)"
```

## Step 8: Report Result

Display the PR URL as a clickable markdown link:

```text
PR created: [#<number>](<url>)
```

If PRs in genuinely separate repos exist (e.g. `osac` + `osac-test-infra` — not
just multiple components within `osac`, which is one PR), remind: "Link
related PRs in the description (e.g., 'Depends on osac-project/osac#123')."

## Quick Reference

| Step | What | Gate |
|------|------|------|
| 1 | Detect context, resolve remotes | Not on main, push remote exists, commits ahead |
| 2 | Run validation | All checks pass |
| 3 | Check test coverage | Advisory warning (does not block) |
| 4 | Pre-flight review gate | Configured reviewers in parallel (see `skills/.config/create-pr-reviewers.yaml`), PASS required (blocks on BLOCKED or INVALID) |
| 5 | Push branch | Push to `$PUSH_REMOTE` succeeds |
| 6 | Determine title | Jira key included if available |
| 7 | Create PR | PR created against upstream repo |
| 8 | Report | Show PR URL |

## Common Issues

### No push remote detected

Run `tools/resolve-remotes.sh --print` to see which remotes were detected. If no push remote was found, add one:

```bash
git remote add <name> git@github.com:<your-username>/<repo>.git
```

The name can be anything (`fork`, `myfork`, your username) — `resolve-remotes.sh` detects it by URL, not by name.

### `gh pr create` fails with "not authenticated"

```bash
gh auth status
gh auth login
```

### Push rejected (branch already exists on remote)

Do not force-push automatically. Show the push error to the user and ask them for explicit instructions on how to proceed.

### PR already exists

```bash
gh pr list --repo <upstream> --head <push-remote-owner>:<branch>
```

If a PR already exists, show its URL instead of creating a duplicate.

## Red Flags

**Never:**
- Push to `$UPSTREAM_REMOTE` — always use `$PUSH_REMOTE`
- Create a PR from `main`
- Skip validation checks
- Skip the pre-flight review gate (Step 4), or push after its overall verdict is BLOCKED or INVALID
- Force-push without user confirmation
- Create a PR with failing tests
- Amend an existing commit — always create a new one

**Always:**
- Resolve remotes with `tools/resolve-remotes.sh` before pushing
- Run repo-specific validation first
- Run the pre-flight review gate before pushing
- Push to `$PUSH_REMOTE`
- Include Jira ticket key in title when available
- Check for existing PRs before creating duplicates
