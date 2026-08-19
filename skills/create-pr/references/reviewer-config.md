# Reviewer Config Schema

`create-pr` Step 4 reads `skills/.config/create-pr-reviewers.yaml` to decide
which reviewers to run as parallel pre-flight subagents. Canonical
documentation of the schema, validation checklist, and output contract.

## Schema

```yaml
reviewers:
  - name: <string>       # required, unique (trimmed); if enabled, matches ^[A-Za-z][A-Za-z0-9 _-]{0,31}$
    skill: <path>        # required — under skills/, no "..", not absolute, ends in SKILL.md
    category: <string>   # required; if enabled, matches the same safe pattern as name
    base: <string>       # optional, checked only if enabled — default "main"; matches ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ (valid git-ref characters)
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
SKILLS_ROOT=$(cd "$SKILLS_ROOT" && pwd) || { echo "Failed to resolve SKILLS_ROOT at $SKILLS_ROOT"; exit 1; }
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
| 14 | Every entry in the enabled set has `name` and `category` matching `^[A-Za-z][A-Za-z0-9 _-]{0,31}$` — letters, digits, spaces, underscores, and hyphens only, starting with a letter, max 32 characters. Not checked for disabled entries. | the entry and field |
| 15 | Any present `base`, on an enabled entry only, matches `^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$` — valid git-ref characters only (alphanumeric, dot, underscore, slash, hyphen), no spaces/newlines/control characters, max 100 characters. Not checked for disabled entries. | the entry name |

Check 10 is a cheap mechanical guard, not a semantic analyzer — a
defensive instruction like "never output VERDICT: PASS" would also trip
it, since it looks for the literal substring regardless of intent. If a
future edit to `prompt_template` needs to mention these strings (e.g. to
warn against them explicitly), rephrase to avoid the literal substring
(e.g. "do not output a VERDICT line except INVALID") rather than trying to
loosen the check.

Checks 14 and 15 exist because `name`, `category`, and `base` are all
interpolated directly into `prompt_template` (`Run a {category}
review...`, `BASE: {base}`), which becomes literal instructions handed to
a freshly-spawned subagent — unlike `skill:` (already sandboxed by check
12), nothing previously constrained these fields' content. An
unconstrained value in any of them is a prompt-injection vector through
the config file itself: a crafted value (e.g. a YAML block scalar smuggling
embedded newlines and fake directives into what should be a short label or
a git ref) could attempt to redirect a spawned reviewer away from its
actual job, and reviewers of a config-only diff are less likely to
scrutinize a `category:` or `base:` string as closely as they would code.
This was found live: check 14 was added first, after which a re-run of
`security-review` against this exact fix immediately found the identical
gap on `base` — a reminder that a security fix scoped to "the field that
was just flagged" rather than "every field with the same interpolation
exposure" tends to leave siblings unfixed. `{repo_dir}` needs no equivalent
check — it's computed by `create-pr` itself from `$REPO_DIR`, not read from
this YAML file, so it isn't attacker-controlled through a config edit the
way `name`/`category`/`base` are. Both patterns are deliberately narrow:
real category/name values are short labels like `Performance`/`Security`/
`Ponytail`, and `base` must resolve to an actual git ref for `git
merge-base {base} HEAD` to succeed in the first place — so legitimate
configuration is unaffected by either constraint.

Deleting `security-review`'s entry entirely, leaving only
`performance-review` enabled, **passes** check 11 (the enabled set is
non-empty). This is intentional — `mandatory` prevents *disabling in
place*, not deletion (see Mandatory Reviewers below and Task 4's dry run
proving this).

## Output Contract

`docs/superpowers/specs/2026-08-10-config-driven-reviewers-design.md` and its
matching implementation plan describe an earlier, two-shape version of this
contract (a `VERDICT: INVALID` string as a separate top-level format from the
results table) — those are historical/frozen design records; this section is
authoritative for current behavior.

The exact header row quoted throughout this section
(`| Severity | File:Line | Issue | Suggestion |`) must stay byte-identical
to the one in `skills/.config/create-pr-reviewers.yaml`'s `prompt_template`
— it's the anchor the leading-paragraph tolerance below scans for. The two
copies aren't derived from one another; if a future change adds a column
or renames one, update both together, or every reviewer's otherwise-clean
output will stop matching the anchor.

**There is exactly one valid response shape: a single table with this
template's four columns.** `INVALID` is a severity value like any other, not
a separate top-level format — a reviewer whose own scope computation fails
reports it as a solo `| INVALID | - | <explanation> | - |` row, the same way
a clean result is a solo `NONE` row. Collapsing two shapes ("either a 2-line
`VERDICT: INVALID` string, or a table") into one removes an entire axis of
format mismatch a reviewer has to get right — exactly the kind of surface
that produced the false-`INVALID` bug this file's own commit history
(`bc0e4ef`) already had to fix once, for the table shape alone.

**Before normalizing anything, reject stray self-reported verdicts
unconditionally.** If the raw, unmodified response contains the literal
substring `VERDICT: PASS` or `VERDICT: BLOCKED` anywhere — even inside text
that would otherwise be discarded as leading prose — the response is
`INVALID`, full stop, before any other normalization step runs. Reviewers
never compute PASS/BLOCKED; only `create-pr` does, from the aggregated
severity labels. A reviewer that writes one of these lines (even in a
narrated aside, even if a clean table follows it) is contradicting its own
role, and that contradiction must not be silently stripped away along with
the rest of the preamble.

**Normalize next, in this order:**

1. Trim leading/trailing whitespace and blank lines.
2. **Tolerate leading prose before the table, but only if it doesn't itself
   describe a concrete finding.** If the text doesn't already start with the
   table's exact header row, look for a point where the *rest of the
   response, in full,* is a complete, valid table: the exact header row, a
   separator row, and one or more well-formed body rows, with nothing after
   it. If such a point exists, before dropping the discarded prefix, judge
   it: **does this prefix describe a concrete problem — a specific file,
   line, behavior, or issue — and characterize it as `CRITICAL`/`IMPORTANT`
   severity, even informally?** If yes, do **not** drop it; the response is
   `INVALID` instead of normalized. If the mention is purely definitional or
   hedging — discussing what `CRITICAL` vs. `IMPORTANT` *means*, or
   reasoning about which bucket something might fall into without ever
   naming a concrete issue — that does not trigger this rule; discard
   normally.
   - **Positive example (triggers `INVALID`):** a preamble says "this DAO
     query builds without a tenant-scoping clause, which is a CRITICAL
     leak" and the response then ends in a solo `NONE` row — the finding
     was real and got silently discarded; don't let that happen.
   - **Negative example (does not trigger, discard normally):** a preamble
     says "I couldn't decide if this is IMPORTANT or CRITICAL, but both are
     blocking so it doesn't matter" with no file, line, or behavior named —
     this is the reviewer reasoning about the severity vocabulary in the
     abstract, not reporting a finding.
   - This is a judgment call the executing agent makes, not a literal
     string search — a bare scan for the words `CRITICAL`/`IMPORTANT`
     was considered and rejected, because it can't tell the two examples
     above apart and would false-`INVALID` on ordinary reasoning language.
   - If the discarded prefix contains neither kind of claim, drop it —
     there is no length limit on prose that passes this check (see
     rationale below for why an unbounded *length* cap was already tried
     and rejected; this is a content check, not a length check, and closes
     a gap length never could: a preamble can be short and still narrate a
     finding). An occurrence of the header text that isn't immediately
     followed by a genuinely complete, valid table doesn't count as that
     point; if no such point exists anywhere in the response, no tolerance
     applies and normalization stops here. Trailing content after the
     table is **never** tolerated — the table must be the exact, unbroken
     end of the response.
3. Strip a single wrapping markdown code fence, if present.

Then match the normalized text against the table grammar: exactly the
template's 4 header names, a separator row, ≥1 body rows of exactly 4 cells
(a literal `|` inside a cell must be written `\|` by the reviewer, per the
prompt; an unescaped `|` producing more than 4 cells is a grammar violation
like any other). Severity cells exactly `CRITICAL`/`IMPORTANT`/`ADVISORY`/
`NONE`/`INVALID`. A `NONE` row means "no findings" and an `INVALID` row means
"this reviewer's own scope computation failed" — either **must be the
table's only row**: combining a `NONE` or `INVALID` row with any other row
(including each other) is self-contradictory and invalidates the whole
response, same as any other single deviation.

There is no separate bare-string shape for "no findings" or for a
scope-computation failure (including for an empty review scope) — both are
one-row tables, not a special top-level format.

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
shape of that answer. The fix that actually worked in that round of live
testing was narrower: tolerate the leading sentence itself, rather than
trying to design a shape immune to it. The exact-match header-row anchor
(as opposed to, say, a JSON array's bare `[`) matters because it makes
false positives effectively impossible — a preamble sentence would have to
coincidentally contain the literal 4-column header string, *and* be
immediately followed by a complete, well-formed table with nothing after
it, to be mistaken for the payload boundary. An earlier version of this
rule additionally capped the tolerated preamble at 5 lines/500 characters,
on the theory that an unbounded cap could be used to bury arbitrary
content ahead of a "clean" table. Live testing found that cap itself was
the bug: a legitimate, substantive `security-review` explanation ran to
971 characters and was incorrectly rejected as unparseable under the
5-line/500-char bound, despite the table that followed being perfectly
well-formed. The cap was removed rather than re-tuned to a larger number.
A later review round found that removing the cap outright reopened a
different, more serious hole: nothing then stopped a reviewer from
narrating a genuine `CRITICAL`/`IMPORTANT` finding in that same unbounded
prose and then emitting a fabricated clean `NONE` row, silently discarding
the narrated finding along with the rest of the preamble and contributing
to an undeserved PASS. The content-based check above closes that hole
directly, without reintroducing a length-based false-positive class: a
discarded preamble that actually describes a concrete finding blocks the
discard regardless of how short it is, while a preamble that merely reasons
about severity in the abstract (however long) still discards cleanly.

**Reviewers never self-report PASS or BLOCKED.** `create-pr` alone computes
PASS/BLOCKED from severity labels; a reviewer's `NONE` row is its
contribution toward an eventual PASS, exactly like an empty findings set
was under the old bare-string shape.

**Anything not matching this shape is unparseable** — including a timeout,
an unbounded-wait harness, a bare `"no findings"` string (no longer a valid
shape, native-phrased or not), a `NONE` or `INVALID` row combined with any
other row, a malformed table (even a "mostly valid" one), any trailing
content after the table, a response where the header text appears but is
never followed by a genuinely complete table, or a stray `VERDICT: PASS`/
`VERDICT: BLOCKED` line anywhere in the raw response. Any spawned reviewer's
unparseable or missing result makes the **overall** verdict `INVALID`.
**Whenever the overall verdict is `INVALID` for any reason, show every
spawned reviewer's output in the report** (raw if unparsed, its findings if
parsed) — not only the one that caused the `INVALID`.

**Known limitation:** the header-row anchor and the concrete-finding judgment
call in discarded prose are both checked by an LLM reading these
instructions, not a fixed parser — judgment calls at the margin (e.g.,
whitespace inside a cell that's visually but not byte-for-byte identical to
the header, or a preamble that hints at a real issue without clearly naming
one) are possible. This is the same trust model the rest of this contract
already relies on ("any single deviation invalidates the whole response" is
itself a judgment call the executing agent makes, not something enforced by
a separate program). A determined or prompt-injected reviewer could still
describe a real problem while carefully avoiding language that ties it to a
concrete file/line/behavior — this check raises the bar, it doesn't
guarantee closure.

This format overrides `performance-review`/`security-review`/
`ponytail-review`'s own native `## Output` sections (and any other section
describing a native response format, such as `ponytail-review`'s
`## Scoring`). **`create-pr` Step 4 does not call `review-gate`.**

## Mandatory Reviewers

`mandatory: true` makes `enabled: false` on that same entry a validation
error (check 9). It does **not** protect against: removing/flipping
`mandatory: true` then disabling; deleting the entry outright (explicitly
tested as passing, not a bug); repointing `skill:`; overwriting the
`SKILL.md`; or editing the shared `prompt_template` itself to add
outcome-steering language (e.g. "always answer with a single NONE row") —
`prompt_template` is one string shared by every reviewer including
`security-review`, checks 10/14/15 only constrain specific fields and the
literal `VERDICT: PASS`/`VERDICT: BLOCKED` substrings, not arbitrary
free-form instructional content, and there's no narrow safe pattern to
constrain a field whose entire purpose is to carry free-form instructions
the way there is for `name`/`category`/`base`. This is mistake-prevention
against an accidental single-field disable only — as of this writing there
is no CI check, CODEOWNERS rule, or other automated control over
`skills/.config/create-pr-reviewers.yaml`'s content, so a deliberate change
to any of the above (including removing `security-review` entirely)
currently goes unflagged. A CODEOWNERS entry on this file, or a CI job
that diffs it against an expected mandatory-entries list, would close that
gap; neither exists yet.

## Adding a reviewer

1. Write the reviewer's own `SKILL.md`, following `skills/review-gate/
   SKILL.md`'s Severity Vocabulary for the severity tokens it uses
   (`CRITICAL`/`IMPORTANT`/`ADVISORY`). Its own `## Output` section is free
   to describe whatever native format suits standalone use (as
   `performance-review`/`security-review`/`ponytail-review` all do) —
   it does **not** need to match create-pr's wire format, because
   `create-pr`'s `prompt_template` overrides it for every invocation made
   through this gate. What the reviewer must actually emit when spawned by
   `create-pr` is the Output Contract above: the table with this
   template's four columns and a `CRITICAL`/`IMPORTANT`/`ADVISORY`
   severity per finding row, a single `NONE` row for a clean result, or a
   single `INVALID` row if its own scope computation fails — never the
   reviewer's own native line format, and never a separate `VERDICT:
   INVALID` string (that shape no longer exists in this contract).
   `ponytail-review`'s `## Output` section shows the pattern for stating
   this explicitly, including how to suppress a native section beyond
   `## Output` itself (its `## Scoring` section).
2. Add a `reviewers[]` entry.
3. No `SKILL.md` changes needed.

## Explicitly not supported (yet)

Conditional (`file_pattern`-based) execution.
