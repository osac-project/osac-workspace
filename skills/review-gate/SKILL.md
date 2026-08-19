---
name: review-gate
description: Local pre-flight review gate that runs performance and security reviews against everything this branch has changed since diverging from a base ref (main by default, via merge-base — not a raw diff against the base's current tip) before PR submission, covering committed, staged, and unstaged changes uniformly. Orchestrates the performance-review and security-review skills in sequence and aggregates their findings into one actionable report. Use standalone before opening a PR — create-pr's own Step 4 pre-flight gate invokes reviewers directly per its config-driven list (skills/.config/create-pr-reviewers.yaml) and does not call this skill. Blocks on critical/important findings from either reviewer.
allowed-tools: Read, Grep, Bash, Glob
---

# Pre-Flight Review Gate

Runs OSAC's local review swarm — `performance-review` then `security-review`
— against **the diff from where this branch last agreed with `{BASE}`**,
plus any untracked files: everything this branch has changed since it
diverged, committed or not, staged or not, and even files never `git add`-ed
at all. `{BASE}` is `main` by default — see Parameters. See Step 1 for why
"since it diverged" and not just "diff against `{BASE}`" matters.

This is a pre-flight checkpoint for a change before it leaves the machine:
run it standalone whenever you want a two-reviewer pass without going
through `create-pr`. `create-pr`'s own Step 4 pre-flight gate does **not**
invoke this skill — it spawns reviewers directly from
`skills/.config/create-pr-reviewers.yaml`'s config-driven list (currently
three reviewers, not the two this skill always pairs), using a different
output contract (a results table, not this skill's `[SEVERITY] file:line —
description — fix` line format). See
`skills/create-pr/references/reviewer-config.md` for that mechanism.

**Announce at start:** "Using the review-gate skill to run the pre-flight review."

**IMPORTANT — never skip a reviewer:** Run every reviewer in Step 2 to
completion before making any gate decision. A blocking finding from
`performance-review` is **not** a reason to stop before running
`security-review` — that's the "stop on first failure" pattern from
`create-pr`'s build/lint gate, and it does not apply here. The developer
needs findings from *all* reviewers in one pass, not one round trip per
reviewer. The only place a gate decision is allowed to happen is Step 4,
after Step 3 has aggregated every reviewer's output.

## Parameters

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| `BASE` | No | The ref this branch diverged from — scope is computed from `git merge-base {BASE} HEAD`, not a raw diff against `{BASE}`'s current tip (see Step 1) | `main` |

Callers that stack branches (a story built on top of another, not directly
on `main`) must pass their actual parent branch as `BASE` — see Step 1 for
why `main` would be wrong there. `create-pr` never stacks, so it uses the
default without saying anything.

## Prerequisites

Resolve the merge-base first — compute it exactly once, here, and reuse
this same value everywhere else in this skill (Step 1 included):

```bash
MERGE_BASE=$(git merge-base {BASE} HEAD)
```

**If this command fails** (`{BASE}` is stale, unfetched, or doesn't exist),
stop and report the exact git error to the user — do not treat a failed
lookup as "nothing to review." This is an **INVALID** outcome (see Step 4)
just like a malformed reviewer output is — the gate itself could not
complete, which is not the same as it completing and finding nothing.
Report it the same way Step 4 reports any other INVALID case. This matters
because of a specific failure mode: written unquoted and inline (`git diff
$(git merge-base {BASE} HEAD) --name-only`), a failing inner command
substitutes to an empty string, which the shell then word-splits away
entirely — collapsing the whole command to plain `git diff --name-only`
(working tree vs. index only), which exits `0` and typically prints
nothing on a clean tree. That looks exactly like "nothing to review" and
silently skips the entire gate right before a push. Assigning to
`$MERGE_BASE` and always quoting it (`"$MERGE_BASE"`) avoids this — the
same failing command instead fails loudly with an explicit `fatal:` error,
because `git diff ""` is a recognizable, invalid argument rather than
nothing at all.

- Something exists to review: `git diff "$MERGE_BASE" --name-only` is
  non-empty, or there are untracked files (`git ls-files --others
  --exclude-standard` is non-empty). If both are empty, report **PASS** —
  there's no difference since this branch diverged from `{BASE}`
  (committed, staged, or unstaged) and no untracked files, so there's
  nothing for the review gate to block on. Still produce the Step 3
  aggregated report (with "no findings" from both reviewers omitted and
  "scope was empty" stated explicitly) so callers can distinguish "PASS
  because nothing to review" from "PASS after reviewing."

## Severity Vocabulary — the contract both reviewers use

This is the single source of truth for severity. `performance-review` and
`security-review` both tag every finding with exactly one of these three
labels — no synonyms (not "blocking", not "high", not "moderate"):

| Label | Meaning | Blocks? |
|-------|---------|---------|
| `CRITICAL` | Confirmed, high-confidence problem: real secret, injection, auth/authz bypass, tenant-isolation violation, confirmed data leakage, O(n^2)+ on a hot path scaled by user/tenant input, confirmed goroutine/resource leak | Yes |
| `IMPORTANT` | High-confidence but lower-stakes, or needs more context to be certain it's exploitable: missing pagination at scale, a pattern that's suspicious but not proven | Yes |
| `ADVISORY` | Style, micro-optimization, or a suggestion — worth raising, not worth gating | No |

Step 4's PASS/BLOCKED decision is a direct function of this label, not of
free-text severity language — see Step 3.

## Step 1: Capture Scope

Not the full repo — and not a raw diff against `{BASE}`'s current tip
either. Reuse `$MERGE_BASE` from Prerequisites — do not recompute it here:

```bash
git diff "$MERGE_BASE" --name-only
git diff "$MERGE_BASE"
git ls-files --others --exclude-standard
```

**Diff from the merge-base, not from `{BASE}` directly — `{BASE}` can move
out from under you.** `git diff {BASE}` is a raw tree-to-tree comparison
against wherever `{BASE}` currently points. If `{BASE}` has gained commits
since this branch diverged from it (normal for anything but a
just-created branch — `main` moves constantly), that comparison pulls in
`{BASE}`'s own subsequent changes too, indistinguishable from changes this
branch actually made. Confirmed with a throwaway repro: `git diff main`
showed a file that only existed because `main` had advanced, one this
branch never touched, as a false deletion. `git diff
$(git merge-base {BASE} HEAD)` — diffing from the commit where this branch
and `{BASE}` last agreed — shows only what this branch actually changed,
regardless of anything that happened on `{BASE}` afterward. `$MERGE_BASE`
is a fixed commit, so this remains a plain single-ref diff against the
working tree — it still naturally includes staged and unstaged changes,
same as before.

**`git diff` alone misses untracked files.** A file that's never been
`git add`-ed produces no diff output at all — a brand-new file with a
planted secret or a bad pattern would otherwise pass through this gate
against an empty scope, prerequisite check and all. If `git ls-files
--others --exclude-standard` lists anything, read each file in full and
include it in scope exactly as if it were an added file in the diff.

Diffing from `$MERGE_BASE` is deliberately not `git diff --cached`. Two
calling contexts, one mechanism:

- **Standalone, mid-work** — picks up any prior commits on the branch *and*
  whatever's staged/unstaged on top, all the way back to where it diverged
  from `{BASE}`. Staged-only scope would silently skip already-committed
  work if a developer commits, then stages one more change before running
  this gate. This is also the case where the untracked-file check above
  actually matters — a new file sitting in the working tree, never staged,
  is exactly what `create-pr`'s own clean-tree gate would catch but nothing
  has caught yet mid-work.
- **From `create-pr`** — by the time that skill reaches this gate, its own
  Step 1 already required a clean, fully-committed tree (`git status
  --porcelain` empty, which includes untracked files) *and* it reaches this
  gate with nothing staged or unstaged. Diffing from `$MERGE_BASE` here
  covers exactly the commits about to be pushed, whether or not `main` has
  moved since the branch was created, and the untracked-file check will
  always come back empty — harmless to run, just redundant in this path
  specifically.

**Why `BASE` matters for stacked branches:** if this story is stacked on
another (its actual parent isn't `main`), computing a merge-base against
`main` would still land on the point where the *parent* branch diverged
from `main` — including the parent's entire contents in the diff. That's
code this branch didn't write and can't fix, since it's not part of this
story in any meaningful sense. Setting `BASE` to the actual parent branch
before computing the merge-base reviews only what this story itself adds.

Capture this scope now — the diff plus any untracked file contents. Pass it
explicitly to both reviewers in Step 2 — don't let them independently
re-derive their own scope, so reviewers and gate all agree on precisely
what's being reviewed.

## Step 2: Run Reviewers — in order, not parallel, never short-circuited

Run `performance-review` **first**, then `security-review` **last**.
Security is the more critical gate — it runs last, closest to push.

**How to invoke a reviewer:** read `../performance-review/SKILL.md` (or
`../security-review/SKILL.md`) with the `Read` tool and follow it exactly,
as if it were pasted inline here. Do this even if your harness also offers
a dedicated skill-invocation mechanism (e.g. Claude Code's `Skill` tool) —
`review-gate`'s own `allowed-tools` doesn't assume one exists, and reading
the file directly works identically across Claude Code, Cursor, and Gemini
CLI, which all mirror this same `skills/` directory. **Do this fresh every
time, even if you've run performance-review or security-review earlier in
this same session** — recalling a prior result instead of re-reading the
current file is exactly how a stale gate check produces a plausible-looking
but stale verdict.

1. Read and follow `../performance-review/SKILL.md`, applying it to the
   exact scope captured in Step 1 (the diff from `$MERGE_BASE`, plus any
   untracked files) — not whatever its own Scope section would derive on
   its own. Its own default is similar in spirit (diff since diverging from
   `main`) but was captured independently in a possibly-different moment or
   against a possibly-different `BASE`; hand it the scope you already
   captured rather than letting it re-derive one. Capture its structured
   findings — **regardless of what they are**, including blocking-severity
   ones.
2. Read and follow `../security-review/SKILL.md` the same way, with the
   same explicit scope override. Run this unconditionally, even if step 1
   already found blocking issues — do not treat step 1's findings as a
   reason to stop here.

Do not decide the verdict (PASS, BLOCKED, or INVALID) anywhere in this
step. That happens only in Step 4, after both reviewers above have run.

This list is deliberately ordered and extensible — if a third reviewer is
added later (for example, a local CodeRabbit pass), it slots in at an
explicit position in this sequence rather than requiring a redesign, and the
same rule applies: every reviewer runs, regardless of earlier reviewers'
findings.

## Step 3: Aggregate

**Validate before merging — fail closed, don't default to PASS.** Each
reviewer's output must be either:
- at least one line in the form `[CRITICAL|IMPORTANT|ADVISORY] file:line —
  description — suggested fix`, or
- the exact phrase `"performance review: no findings"` /
  `"security review: no findings"`, optionally preceded by leading prose —
  see the tolerance rule below.

**Both the stray-verdict rejection and the leading-prose tolerance below
use the exact judgment-call algorithm `create-pr`'s Output Contract
defines canonically** — see
`skills/create-pr/references/reviewer-config.md`'s Output Contract for the
full reasoning, worked positive/negative examples, and the `bc0e4ef`
history behind why an exact-match-only bare string is itself a
false-`INVALID` bug. Only the final output *shape* differs (a findings
line or the literal "no findings" phrase here, vs. a table row there); the
decision procedure is identical, so it isn't re-derived below. Applied to
review-gate's shape:

- **Stray verdict, unconditional:** if a reviewer's raw output contains
  `verdict: pass` or `verdict: blocked` anywhere, case-insensitively, the
  output is invalid — full stop, before the tolerance judgment below even
  runs. Neither reviewer computes PASS/BLOCKED; only this skill's Step 4
  does.
- **Leading-prose tolerance:** before discarding any leading text ahead of
  a findings line or the "no findings" phrase, judge whether it names a
  concrete `CRITICAL`/`IMPORTANT` problem that's genuinely absent from
  everything that follows — not just absent from a literal "no findings"
  match. A reviewer that narrates a real finding and then reports only an
  unrelated line about a different file has dropped it just as much as if
  it had said "no findings" outright. If the narrated problem is absent
  from every findings line that follows, don't discard the prose — the
  output is invalid. If the narrated problem *is* one of the findings
  lines, that's ordinary "narrate before reporting" behavior, not a leak;
  discard normally.

If either reviewer's output is missing, empty, or doesn't match one of
these two forms after applying the tolerance above — a reviewer step was
skipped, crashed, returned free text with no severity labels, narrated a
real finding and then claimed "no findings" anyway, or anything else that
doesn't parse — that is itself a gate failure, distinct from BLOCKED. Do
not treat an unparseable or absent reviewer section as "no findings" and do
not let it produce a PASS. Stop and report which reviewer's output was
invalid or missing. A gate that can't verify what a reviewer found has not
passed.

Once both outputs validate, merge them into one, in this shape:

```markdown
## Pre-Flight Review Gate

### Performance Review
[CRITICAL|IMPORTANT|ADVISORY] file:line — description — suggested fix
...
(or: "performance review: no findings")

### Security Review
[CRITICAL|IMPORTANT|ADVISORY] file:line — description — suggested fix
...
(or: "security review: no findings")

### Verdict: PASS / BLOCKED / INVALID
```

- Dedup findings that land on the same file:line from both reviewers —
  keep the higher-severity write-up (`CRITICAL` > `IMPORTANT` > `ADVISORY`),
  note the other reviewer flagged it too.
- Verdict is **BLOCKED** if either reviewer reported at least one `CRITICAL`
  or `IMPORTANT` finding. **PASS** only if every finding from both reviewers
  is `ADVISORY` (or there are no findings at all). This is a literal label
  check, not a judgment call — see the Severity Vocabulary above.

## Step 4: Gate Decision

This is where the verdict (PASS, BLOCKED, or INVALID) is formally decided
— after both reviewers in Step 2 have completed and Step 3 has aggregated
their output. The one exception is Prerequisites: if `git merge-base`
fails there, it short-circuits to INVALID before Step 1 ever runs.

- **PASS** — both reviewer outputs validated in Step 3, and every finding
  is `ADVISORY` or absent. Report the result and continue (if called from
  `create-pr`, proceed to the next step; if standalone, just show the
  report).
- **BLOCKED** — both reviewer outputs validated, and at least one
  `CRITICAL` or `IMPORTANT` finding exists. Stop. Show the full aggregated
  report. Do not proceed to push or PR creation. The only next action is
  fixing the flagged issues (in the working tree, staged, or via a new
  commit — never amend an existing one) and re-running this gate.
- **INVALID** — the gate itself could not complete, for either of two
  reasons: Prerequisites' `git merge-base` failed (Step 1 scope capture
  never happened), or Step 3's validation failed for either reviewer
  (missing, empty, or malformed output). Stop. This is not the same as
  PASS or BLOCKED — treat it exactly like BLOCKED for the purpose of not
  proceeding to push, but report it distinctly: name what failed (the
  merge-base lookup, or which reviewer's output) and why. The next action
  matches the failure: re-check `{BASE}` and retry Prerequisites, or
  re-read the failed reviewer's `SKILL.md` and re-run it against the same
  scope from Step 1 — not fixing code, since there may be no real findings
  yet to fix.

## Output

Always produce the aggregated report from Step 3, even on a clean pass or
an INVALID outcome — a silent pass is indistinguishable from the gate not
having run, and a silently-dropped reviewer is indistinguishable from one
that found nothing.
