# Internal Proposals

Workspace-native home for PRD/design documents that describe internal
engineering process or tooling — not an OSAC product feature. Lives in
`osac-workspace` alongside `evals/`, `skills/`, and `.design/context/` — not
the `enhancement-proposals` repo.

## Is this the right place?

Use **`enhancement-proposals/`** (the `enhancements/` dir) if the work:

- Adds or removes a significant tenant-facing capability
- Introduces or changes a CRD/API surface
- Affects one of OSAC's four canonical personas (Cloud Provider Admin, Cloud
  Infrastructure Admin, Tenant Admin, Tenant User)
- Needs consensus across multiple component repos/teams to implement

Use **`internal-proposals/`** (here) if the work:

- Has no tenant-facing surface and no CRD/proto/API footprint
- Is consumed by internal engineering roles (e.g. lead engineer, product
  owner, DevOps engineer), not OSAC's tenant-facing personas
- Happens to share a Jira project/component with OSAC feature work, but isn't
  itself something that ships *in* OSAC

If it's genuinely ambiguous, ask before drafting — this directory exists
because [OSAC-959](https://redhat.atlassian.net/browse/OSAC-959) (agentic-SDLC
measurement) hit exactly this ambiguity and the team decided it belonged
here, not in `enhancement-proposals`.

## Location decision

| Approach | This convention |
|----------|------------------|
| `enhancement-proposals` repo (`enhancements/` dir) | No — reserved for OSAC product/tenant-facing features (see that repo's README, "Is my proposed change an enhancement?") |
| Personal fork branch, never opened as a PR | No — not durable, not discoverable, not reviewed |
| Separate repo (e.g. `osac-internal-proposals`) | No — not enough volume to justify a bootstrapped component |
| Workspace-native `internal-proposals/` tree (this) | Yes |

## Naming convention

Mirrors `enhancement-proposals`' slug convention so tooling and muscle memory
transfer, but the top-level directory name keeps the two unambiguous:

```
internal-proposals/<jira-key>-<feature-slug>/prd.md
internal-proposals/<jira-key>-<feature-slug>/design.md
```

`<jira-key>` is the Jira **Feature**-level key exactly as it appears (no
zero-padding) — the same rule `AGENTS.md` documents for `enhancement-proposals`.

## Review process

- Normal `osac-workspace` PR review: push to `fork`, open a PR against
  `origin/main` (this repo's own fork-based workflow — see root `AGENTS.md`),
  get sign-off from the relevant reviewers.
- **Not** `enhancement-proposals`' "select at least three reviewers" consensus
  process — that bar is calibrated for changes with tenant/cross-team blast
  radius. Proposals here don't carry that radius by definition.
- No EP Review Bot runs against this directory. If you want an automated
  read, self-run the `prd-review` / `design-review` skills locally — but read
  the caveat below first.

## Rubric caveat

`skills/prd-review/SKILL.md` and `skills/design-review/SKILL.md` are
calibrated against OSAC's four tenant-facing personas and CRD/API-heavy
designs. A document here will legitimately have:

- No affected OSAC personas — internal engineering roles instead
- No CRD/proto/tenant-isolation surface — most of the Architecture criterion
  is N/A by design, not a gap
- No comparable exemplar in the `enhancement-proposals` reference library —
  every merged design there is CRD-heavy and tenant-facing

For `design-review`, this is confirmed advisory-only in practice: a self-run
against `OSAC-959-agentic-sdlc-measurement/design.md` scored 8/8, with
Architecture at full marks precisely *because* it documented its N/As
instead of leaving them silent. Treat a low `design-review` score driven by
structurally-N/A criteria as evidence the rubric wasn't built for this
category, not evidence the proposal is weak.

**`prd-review` is a different story: expect a real FAIL, but not via the
mechanism you'd guess.** A self-run against this directory's own PRD scored
6/10 (FAIL — threshold is 7/10) — not because WHAT hit its "score 0 if there
is no new product capability" clause. That clause is about content-only
deliverables ("documentation, example files, configuration samples" with no
engineering build behind them); it doesn't fire just because the work is
internal rather than tenant-facing, and it didn't fire here. Only **one** of
the four sub-2 scores was a genuine structural mismatch:

- **WHAT** (1/2) — dinged for not naming OSAC's canonical personas/services,
  which a document in this category legitimately doesn't have. Structural,
  unavoidable, advisory only.

The other three were **real, fixable PRD-quality gaps**, not category
mismatches — an OSAC feature PRD with the same issues would score the same
way:

- **User-Facing Focus** — dinged for naming internal codenames/personal-fork
  paths instead of describing outcomes
- **Right-Sized** — dinged for bundling a capability the PRD itself called
  "a distinct observability signal" into scope instead of splitting it out
- **Testability** — dinged for scope bullets that described a delivery
  process rather than a checkable, reviewer-verifiable outcome

Read a `prd-review` score here as **two signals layered together**: discount
the WHAT ding as structural, but treat dings on the other criteria as real
writing feedback worth fixing regardless of where the document lives.

## Current proposals

| Slug | Jira | Status |
|------|------|--------|
| [`OSAC-959-agentic-sdlc-measurement`](OSAC-959-agentic-sdlc-measurement/) | [OSAC-959](https://redhat.atlassian.net/browse/OSAC-959) | In Progress — migrated from a personal `enhancement-proposals` fork branch (`design/OSAC-959`), which was never opened as a PR there |
