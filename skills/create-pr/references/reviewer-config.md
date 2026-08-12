# Reviewer Config Schema

`create-pr` Step 4 reads `skills/.config/create-pr-reviewers.yaml` to decide
which reviewers to run as parallel pre-flight subagents. Canonical
documentation of the schema, validation checklist, and output contract.

## Schema

```yaml
reviewers:
  - name: <string>       # required, unique (trimmed)
    skill: <path>        # required — under skills/, no "..", not absolute, ends in SKILL.md
    category: <string>   # required
    base: <string>       # optional, non-empty if present, checked only if enabled — default "main"
    enabled: <bool>       # optional — default true; boolean-typed, literal false disables
    mandatory: <bool>     # optional — default false; true forbids enabled: false on this entry

prompt_template: <string>  # required, non-empty YAML string (not a list/map),
                            # must contain {skill}, {base}, {category}, {repo_dir},
                            # must not contain "VERDICT: PASS" or "VERDICT: BLOCKED"
```

Only `reviewers` and `prompt_template` are permitted top-level keys. Only
`name`, `skill`, `category`, `base`, `enabled`, `mandatory` are permitted
per-entry keys — anything else (a typo like `enable` or `manditory`) fails
validation rather than being silently ignored.

## Path Resolution

```bash
SKILLS_ROOT="$REPO_DIR"
[[ -f "$SKILLS_ROOT/skills/.config/create-pr-reviewers.yaml" ]] || SKILLS_ROOT="$REPO_DIR/.."
SKILLS_ROOT=$(cd "$SKILLS_ROOT" && pwd)
```

Checking for the config file itself, not merely a `skills/` directory,
matters if a component repo ever acquires its own `skills/` without the
config file in it — the file-specific check falls through to the parent
correctly in that case instead of stopping at the wrong root.

Independent of Step 1's `$WORKSPACE_ROOT`, which is wrong when `$REPO_DIR`
is `osac-workspace` itself (out of scope to fix here — see
`skills/create-pr/SKILL.md` Step 1 and this feature's design doc). The
config file and every `skill:` value are read from `$SKILLS_ROOT/<path>`.

**Reviewer git-command anchoring is separate from file-path resolution.**
`$SKILLS_ROOT` only governs where `create-pr` itself reads config/skill
*files* from. A spawned reviewer's own git commands (merge-base, diff) run
wherever the reviewer starts — anchor them explicitly by substituting
`{repo_dir}` (`$REPO_DIR`) into the prompt and instructing the reviewer to
run its git commands against that directory (see the shipped
`prompt_template`).

## Validation Checklist (canonical, ordered; any failure ⇒ overall verdict `INVALID`, no agent spawned, no push)

| # | Check | On failure, report |
|---|-------|---------------------|
| 1 | Config file exists at `$SKILLS_ROOT/skills/.config/create-pr-reviewers.yaml` | "config file not found" |
| 2 | File parses as valid YAML | the parse error |
| 3 | Only `reviewers` and `prompt_template` are present as top-level keys | the unexpected key |
| 4 | `reviewers` is present and is a non-empty YAML sequence of mappings | "reviewers must be a non-empty list of mappings" |
| 5 | Every entry contains only `name`/`skill`/`category`/`base`/`enabled`/`mandatory` — no other keys | the entry and the unexpected key |
| 6 | Every entry has non-empty (trimmed) `name`, `skill`, `category` | which entry/field |
| 7 | No two entries share the same `name` (trimmed) | the duplicate |
| 8 | Any present `enabled`/`mandatory` is boolean-typed (not a string, number, list, or mapping) | the entry and field |
| 9 | No entry has `mandatory: true` and `enabled: false` simultaneously | the entry name |
| 10 | `prompt_template` is a non-empty YAML string (not a list/map), contains `{skill}`, `{base}`, `{category}`, `{repo_dir}`, and does not contain the literal substring `VERDICT: PASS` or `VERDICT: BLOCKED` | which condition failed |
| 11 | After filtering to entries where `enabled` is not explicitly `false`, the remaining set is non-empty | "no enabled reviewers" |
| 12 | Every entry in the enabled set has a `skill` value that's sandboxed (under `skills/`, no `..`, not absolute, ends in `SKILL.md`) and exists under `$SKILLS_ROOT`. Not checked for disabled entries. | the entry and path |
| 13 | Any present `base`, on an enabled entry only, is a non-empty string. Not checked for disabled entries. | the entry name |

Check 10 is a cheap mechanical guard, not a semantic analyzer — a
defensive instruction like "never output VERDICT: PASS" would also trip
it, since it looks for the literal substring regardless of intent. If a
future edit to `prompt_template` needs to mention these strings (e.g. to
warn against them explicitly), rephrase to avoid the literal substring
(e.g. "do not output a VERDICT line except INVALID") rather than trying to
loosen the check.

Deleting `security-review`'s entry entirely, leaving only
`performance-review` enabled, **passes** check 11 (the enabled set is
non-empty). This is intentional — `mandatory` prevents *disabling in
place*, not deletion (see Mandatory Reviewers below and Task 4's dry run
proving this).

## Output Contract

**Normalize first, in this order:**

1. Trim leading/trailing whitespace and blank lines.
2. **Tolerate at most one short leading paragraph before the payload** —
   if the text doesn't already start with `VERDICT:` or the table's exact
   header row, scan for the first line that is *exactly*
   `| Severity | File:Line | Issue | Suggestion |` and, if that line
   appears within the first 5 lines and the discarded prefix is at most
   500 characters, drop everything before it. If no such header line
   exists in the first place, or it exists but only past that 5-line/
   500-char bound, don't drop anything (the too-long case is itself a
   normalization failure — see below). Trailing content after the table
   is **not** given this tolerance — only a leading paragraph is.
3. Strip a single wrapping markdown code fence, if present.

Then match the normalized text against exactly one of:

1. Exactly two lines: `VERDICT: INVALID`, then one non-empty explanation
   line — nothing else.
2. A results table: exactly the template's 4 header names, a separator
   row, ≥1 body rows of exactly 4 cells. Severity cells exactly `CRITICAL`/
   `IMPORTANT`/`ADVISORY`/`NONE`. A `NONE` row means "no findings" and
   **must be the table's only row** — combining a `NONE` row with a real
   (`CRITICAL`/`IMPORTANT`/`ADVISORY`) row in the same response is
   self-contradictory and invalidates the whole response, same as any
   other single deviation.

There is no separate bare-string shape for "no findings" (including for an
empty review scope) — a clean result is a one-row table with severity
`NONE`, not a literal string like the old `"no findings"`.

**Why the leading-paragraph tolerance exists:** Task 4's live dry run
against the round-6 bare-string contract found that most genuinely-clean
reviews came back as an explanatory sentence followed by `"no findings"`,
even under an explicit no-preamble instruction — correctly rejected as
unparseable under the strict rule, but a real, frequent false `INVALID`.
Two follow-up hypotheses were tried and *disproven* by further live
spawns before landing on this one: neither switching the clean case to a
`NONE`-severity table row, nor switching the whole payload to a JSON
array, stopped the model from prepending the same kind of sentence — the
behavior is about wanting to narrate before a final answer, not about the
shape of that answer. The fix that actually worked in live testing is
narrower: tolerate the leading sentence itself, rather than trying to
design a shape immune to it. The exact-match header-row anchor (as
opposed to, say, a JSON array's bare `[`) matters because it makes false
positives effectively impossible — a preamble sentence would have to
coincidentally contain the literal 4-column header string to be
mistaken for the payload boundary. The length/line cap exists so this
tolerance can't be used to bury an arbitrary amount of content ahead of a
"clean" table; anything past that bound is treated as a normalization
failure (unparseable), not silently accepted.

**Reviewers never self-report PASS or BLOCKED.** `create-pr` alone computes
PASS/BLOCKED from severity labels; a reviewer's `NONE` row is its
contribution toward an eventual PASS, exactly like an empty findings set
was under the old bare-string shape.

**Anything not matching one of the two shapes is unparseable** — including
a timeout, an unbounded-wait harness, a bare `"no findings"` string (no
longer a valid shape, native-phrased or not), a `NONE` row combined with
real-finding rows, a malformed table (even a "mostly valid" one), a
leading paragraph longer than the 5-line/500-char tolerance, or a stray
`VERDICT: PASS`/`VERDICT: BLOCKED` line. Any spawned reviewer's
unparseable or missing result makes the **overall** verdict `INVALID`.
**Whenever the overall verdict is `INVALID` for any reason, show every
spawned reviewer's output in the report** (raw if unparsed, its findings if
parsed) — not only the one that caused the `INVALID`.

**Known limitation:** the header-row anchor is checked as an exact string
match, which this document can specify precisely, but the check is
executed by an LLM reading these instructions, not a fixed parser —
judgment calls at the margin (e.g., whitespace inside a cell that's
visually but not byte-for-byte identical to the header) are possible.
This is the same trust model the rest of this contract already relies on
("any single deviation invalidates the whole response" is itself a
judgment call the executing agent makes, not something enforced by a
separate program).

This format overrides `performance-review`/`security-review`'s own native
`## Output` sections. **`create-pr` Step 4 does not call `review-gate`.**

## Mandatory Reviewers

`mandatory: true` makes `enabled: false` on that same entry a validation
error (check 9). It does **not** protect against: removing/flipping
`mandatory: true` then disabling; deleting the entry outright (explicitly
tested as passing, not a bug); repointing `skill:`; overwriting the
`SKILL.md`. Mistake-prevention against an accidental single-field disable —
CI is the control against deliberate bypass.

## Adding a reviewer

1. Write the reviewer's own `SKILL.md`, following `skills/review-gate/
   SKILL.md`'s Severity Vocabulary.
2. Add a `reviewers[]` entry.
3. No `SKILL.md` changes needed.

## Explicitly not supported (yet)

Conditional (`file_pattern`-based) execution.
