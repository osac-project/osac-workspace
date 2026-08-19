---
name: performance-review
description: Performance self-review of a branch's changes before PR submission. Scans everything changed since diverging from a base ref (main by default, committed, staged, and unstaged, via merge-base) for O(n)/O(n^2) hot-path issues, memory/goroutine leaks, and inefficient patterns across OSAC's Go services and Ansible/Python tooling. Use standalone before opening a PR, via review-gate (which pairs it with security-review), or via create-pr's config-driven pre-flight gate, which invokes it directly.
allowed-tools: Read, Grep, Bash, Glob
---

# Performance Review

Performance self-review of a branch's changes — catches inefficiencies while
they're still cheap to fix, before the change is pushed or exposed to
reviewers/CI.

This is one of the reviewers in OSAC's local pre-flight review gate. When run
via `review-gate` (standalone use), it's paired with `security-review` and
always runs **first**. When run via `create-pr`'s Step 4, it's one of
however many reviewers `skills/.config/create-pr-reviewers.yaml` currently
enables — `create-pr` invokes each reviewer directly and in parallel, not
through `review-gate`'s sequencing, and the enabled set may include
reviewers beyond these two (it currently also runs `ponytail-review`). It's
also independently invocable — run it any time you want a performance pass
without going through either gate.

**Severity contract:** tag every finding `CRITICAL`, `IMPORTANT`, or
`ADVISORY` — full definitions are in the Severity section below.
`CRITICAL`/`IMPORTANT` block; `ADVISORY` doesn't. This is a shared
vocabulary with `security-review` and `review-gate`'s PASS/BLOCKED logic,
not a local convention — see the Severity Vocabulary in `review-gate`.

## When to run

After the implementation feels done, before `git commit` or `gh pr create` —
or whenever invoked directly.

## Mindset

Assume this code runs at scale and in a hot path, even if it doesn't today.
Don't just check "does this work" — check "what happens at 10x, 100x the
data, or under concurrent load." A checklist alone misses this; the checklist
below is a starting point for that pass, not a substitute for it.

## Scope

Review **everything this branch has changed since diverging from `{BASE}`**
(`{BASE}` is `main` by default — see below), plus any untracked files —
whether committed, staged, unstaged, or never staged at all — not the full
repo. Pull in enough surrounding context to judge real cost: is the changed
function on a request path, a reconcile loop, or a one-time init? A O(n^2)
loop in a CLI's one-shot startup code is not the same severity as one in a
hot gRPC handler or a controller's `Reconcile()`.

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
pulling the parent's entire contents into scope. Default to `main` in
every other case.

Diff from the merge-base, not from `{BASE}` directly — `{BASE}` moves
constantly (especially `main`), and a raw `git diff {BASE}` would pull in
whatever `{BASE}` gained after this branch diverged, indistinguishable
from changes this branch actually made. `git diff "$MERGE_BASE"` isolates
exactly what this branch changed, regardless of `{BASE}`'s later history.

`git diff` alone misses untracked files — a brand-new file that's never
been `git add`-ed produces no diff output. If `git ls-files --others
--exclude-standard` lists anything, read each file in full and review it
exactly as if it were an added file in the diff.

If both are empty, say so and stop — there's nothing to review yet.

**If invoked via the `review-gate` skill**, review whatever scope it hands
you instead of deriving your own — `review-gate` captures scope once and
passes it to both reviewers so they agree on exactly what's in scope.

## What to check

### General

- **Nested iteration over the same collection** — O(n^2)/O(n^3) patterns:
  looping over a slice/map inside another loop over the same or related data,
  where a map lookup or pre-sorted index would do.
- **Unbounded growth** — slices/maps/buffers appended to in a loop with no
  cap, especially if sized by user or tenant input.
- **Repeated work that could be hoisted** — recomputing the same value inside
  a loop body instead of before it; redundant parsing/marshaling per
  iteration.
- **String/byte concatenation in loops** — building strings with `+=` in a
  loop instead of `strings.Builder` (Go) or `str.join` (Python).
- **N+1 query patterns** — a query per item in a loop where a single
  batched/joined query would work.

### Go (fulfillment-service, osac-operator)

- **DAO / query layer** (`internal/database/dao/`,
  `internal/database/filter_translator.go`) — queries without pagination on
  potentially large result sets; CEL-filter translation that can't use an
  index; loading full objects when only a projection is needed.
- **`internal/servers/generic_server.go`-style reflection** — new
  reflection-based code (`findPayloadField` and similar) added inside a
  per-request hot path instead of precomputed/cached once.
- **Goroutine leaks / unbounded spawning** — a goroutine launched per item
  with no `sync.WaitGroup`/limit/context cancellation; missing `defer close()`
  on channels; goroutines that can outlive the request they were spawned for.
- **Controller reconcile loops** (`internal/controller/*_controller.go`) — a
  `Reconcile()` that does unnecessary API-server round-trips (e.g., re-fetches
  an object it already has), or lacks requeue backoff, or does a network/AAP
  call inline that should be checked for idempotency and rate-limited.
- **Lock contention** — a mutex held across an I/O call (DB query, gRPC call,
  AAP REST call) instead of only around the in-memory critical section.

### Python / Ansible (osac-aap, e2e tests)

- **Per-item playbook tasks** without `loop`/`async`/batching where the
  target module supports batch operations.
- **Polling loops** (`wait_for`, AAP job status polling) with a tight interval
  or no backoff, generating excessive API load.
- **Test fixtures re-doing expensive setup** per test instead of sharing via a
  session/module-scoped pytest fixture, when the setup is read-only and
  tenant-safe to share.

## Severity

Tag every finding with exactly one of these three labels — this is a shared
contract with `security-review` and `review-gate`'s PASS/BLOCKED logic, not
a local convention. No synonyms (not "blocking", not "high", not "moderate").

- **`CRITICAL`** — O(n^2)+ on a hot path scaled by tenant/user input,
  confirmed goroutine/resource leaks, unbounded growth on attacker- or
  tenant-controlled input, lock held across an I/O call. Blocks.
- **`IMPORTANT`** — likely a real problem but lower-stakes or needs more
  context to be certain (e.g., a query missing pagination that's fine today
  but won't scale). Blocks.
- **`ADVISORY`** — a micro-optimization, or a loop that's technically
  O(n^2) but bounded to a handful of items. Raise it, don't gate on it.

## Output

Produce a short structured list:

```text
[CRITICAL|IMPORTANT|ADVISORY] file:line — one-line description — suggested fix
```

If you find nothing, say so explicitly ("performance review: no findings") —
a silent skip is indistinguishable from forgetting to run the review at all.

**When invoked through `create-pr`'s config-driven pre-flight gate, its
`prompt_template` overrides this section entirely** — respond with the
table format specified there instead (see
`skills/create-pr/references/reviewer-config.md`'s Output Contract), never
this native list format or the bare "no findings" string above.
