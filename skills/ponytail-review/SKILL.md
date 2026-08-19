---
name: ponytail-review
description: >
  Code review focused exclusively on over-engineering and duplication.
  Finds what to delete: reinvented standard library, unneeded dependencies,
  speculative abstractions, dead flexibility, and non-trivial duplicated
  logic. One line per finding: location, what to cut or de-duplicate, what
  replaces it. Use when the user says "review for over-engineering", "what
  can we delete", "is this over-engineered", "simplify review", or invokes
  /ponytail-review. Also runs as one of `create-pr`'s config-driven Step 4
  pre-flight reviewers (see `skills/create-pr/references/reviewer-config.md`)
  — complements correctness/security/performance review, this one only
  hunts complexity and duplication. Adapted from
  https://github.com/DietrichGebert/ponytail.
allowed-tools: Read, Grep, Bash, Glob
---

# Ponytail Review

Review diffs for unnecessary complexity and non-trivial duplicated logic.
One line per finding: location, what to cut or de-duplicate, what replaces
it. The diff's best outcome is getting shorter, or at least not growing
the number of places the same logic lives.

**Severity contract:** `duplicate:` findings are `IMPORTANT` — non-trivial
duplicated logic compounds into maintenance debt in a way the other
categories don't, and `IMPORTANT` gates a `create-pr` push exactly like
`CRITICAL` does (see `skills/review-gate/SKILL.md`'s Severity Vocabulary).
Every other category (`delete`/`stdlib`/`native`/`yagni`/`shrink`) is
`ADVISORY` — worth raising, not worth blocking, consistent with this
reviewer complementing rather than replacing correctness/security/
performance review.

## Scope

Review **everything this branch has changed since diverging from `{BASE}`**
(`{BASE}` is `main` by default — see below), plus any untracked files —
whether committed, staged, unstaged, or never staged at all — not the full
repo.

```bash
MERGE_BASE=$(git merge-base {BASE} HEAD)
git diff "$MERGE_BASE" --name-only
git diff "$MERGE_BASE"
git ls-files --others --exclude-standard
```

**If `git merge-base` fails** (`{BASE}` stale, unfetched, or doesn't
exist), stop and report the exact git error — don't treat a failed lookup
as nothing to review.

**Set `{BASE}` yourself if this branch is stacked on another** (not
directly on `main`) and you're running this standalone — otherwise the
merge-base lands on where the *parent* branch diverged from `main`,
pulling the parent's entire contents into scope.

`git diff` alone misses untracked files — a brand-new file that's never
been `git add`-ed produces no diff output. If `git ls-files --others
--exclude-standard` lists anything, read each file in full and review it
exactly as if it were an added file in the diff — a hand-rolled stdlib
reimplementation or a copy-pasted 40-line function sitting in a file
that's never been staged is exactly the kind of thing this review exists
to catch.

If both are empty, say so and stop — there's nothing to review yet.

**For `duplicate:` specifically, look past the diff itself.** The other
four categories only need the changed lines; duplication needs one more
step: for each new or substantially-rewritten non-trivial function/block
in the diff, `Grep` the rest of the repo for near-identical logic that
already existed before this branch. A PR that copies a 40-line function
into a second file is a `duplicate:` finding even if neither copy is new
to this diff in isolation — the diff is where the *second* copy was
introduced, which is exactly the moment to catch it.

## Format

`L<line>: <tag>: <what>. <replacement>.`, or `<file>:L<line>: ...` for
multi-file diffs.

Tags:

- `delete:` dead code, unused flexibility, speculative feature. Replacement: nothing.
- `stdlib:` hand-rolled thing the standard library ships. Name the function.
- `native:` dependency or code doing what the platform already does. Name the feature.
- `yagni:` abstraction with one implementation, config nobody sets, layer with one caller.
- `shrink:` same logic, fewer lines. Show the shorter form.
- `duplicate:` non-trivial logic that already exists elsewhere (in this diff or already in the repo). Name the other location(s); the replacement is always "extract to a shared helper" or "call the existing one," never "nothing" — duplication is a de-duplication problem, not a deletion.

**"Non-trivial" is the filter for `duplicate:`.** Two call sites doing
`if err != nil { return err }`, a three-line getter repeated across
structs, or an idiomatic pattern this codebase already uses everywhere are
not findings — only genuine business logic (parsing, validation rules,
retry/backoff logic, a multi-step computation) copy-pasted or
independently reinvented in a second place counts.

## Examples

❌ "This EmailValidator class might be more complex than necessary, have you
considered whether all these validation rules are needed at this stage?"

✅ `L12-38: stdlib: 27-line validator class. "@" in email, 1 line, real validation is the confirmation mail.`

✅ `L4: native: moment.js imported for one format call. Intl.DateTimeFormat, 0 deps.`

✅ `repo.py:L88: yagni: AbstractRepository with one implementation. Inline it until a second one exists.`

✅ `L52-71: delete: retry wrapper around an idempotent local call. Nothing replaces it.`

✅ `L30-44: shrink: manual loop builds dict. dict(zip(keys, values)), 1 line.`

✅ `internal/servers/foo_server.go:L120-155: duplicate: 35-line pagination-cursor decode, byte-identical to internal/servers/bar_server.go:L80-115. Extract to a shared internal/servers/pagination.go helper; both call sites already take the same cursor type.`

## Scoring

End with the only metric that matters: `net: -<N> lines possible.` (a
`duplicate:` finding whose fix is "extract to a shared helper" still
counts toward this — the net is post-extraction, not zero just because
nothing gets deleted outright).

If there is nothing to cut or de-duplicate, say `Lean already. Ship.` and
stop.

## Boundaries

Scope: over-engineering, complexity, and duplication only. Correctness
bugs, security holes, and performance are explicitly out of scope. Route
them to a normal review pass, not this one — when run through `create-pr`,
`performance-review` and `security-review` already cover that ground in
parallel. A single smoke test or `assert`-based self-check is the ponytail
minimum, not bloat, never flag it for deletion. An idiomatic pattern this
codebase already uses pervasively (see "Non-trivial" above) is not a
`duplicate:` finding. Does not apply the fixes, only lists them.
"stop ponytail-review" or "normal mode" (standalone use only): revert to
verbose review style.

## Output

The format above (tags, one-liner-per-finding, `net:` scoring) is this
skill's native standalone format — use it when invoked directly (e.g.
`/ponytail-review`). **When invoked through `create-pr`, its
`prompt_template` overrides this entirely, including the `## Scoring`
section above** — ignore both sections and respond with the table format
`create-pr` specifies instead (see
`skills/create-pr/references/reviewer-config.md`'s Output Contract): one
row per finding with `Severity` = `IMPORTANT` for `duplicate:` findings and
`ADVISORY` for every other tag, `File:Line`, `Issue` = the tag and what to
cut/de-duplicate, `Suggestion` = the replacement; a single `NONE` row for
"lean already, ship" with no findings at all; or a single `INVALID` row if
your own scope computation fails. Never append a `net: -<N> lines
possible.` line (or any other native-format trailer) after the table — that
is exactly the kind of trailing content the Output Contract forbids.
