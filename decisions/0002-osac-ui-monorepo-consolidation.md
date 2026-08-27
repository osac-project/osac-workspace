# 0002. Merge `osac-ui` into the `osac` Mono-Repo

- **Status:** Proposed
- **Date:** 2026-08-05

## Context

Prompted by asking "if we started from scratch, what's the ideal setup, and
can we get there?" The meta-repo pattern's own literature is explicit that
it's a second-best pattern chosen *because* restructuring is expensive, not
because it's theoretically ideal on a blank slate. It's worth naming what
"ideal" would actually look like, separately from deciding whether or when
to pursue it.

`osac-ui` is a Go-backend-adjacent, TypeScript/React (pnpm workspaces: `apps/`,
`libs/`, plus a Go `proxy/`) frontend, already living in a repo separate from
the `osac` backend mono-repo it talks to. `osac-installer` currently depends
on `osac-ui` "as a real external dependency (OCI chart + image,
version-tagged), bumped deliberately when a new release is needed" — this is
a deliberate current design choice (`AGENTS.md`, Deployment Coordination),
not an oversight, and any consolidation needs to either preserve or
deliberately change that relationship.

This record is scoped narrowly to `osac-ui`. It does not revisit whether
`osac-workspace` should remain a meta-repo, whether `enhancement-proposals`
should stay separate, or how AI skills should be distributed — those are
separate questions, tracked elsewhere.

## Proposed Direction

- **Merge `osac-ui` into `osac`** as a top-level directory (e.g. `osac/ui/`),
  alongside the existing backend components. Use Go workspaces for the
  backend (already in place) and pnpm workspaces for the frontend (already
  how `osac-ui` is structured internally — no frontend tooling rewrite
  needed). Add path-scoped CI (GitHub Actions `paths:` filters) so a
  UI-only PR doesn't trigger Go builds and vice versa, and path-based
  `CODEOWNERS` so review routing stays team-scoped without needing repo
  boundaries to enforce it.
- **Keep `osac-test-infra` separate.** Unlike `osac-ui`, this one is
  genuinely a closer call, but I'd lean toward not merging it even ideally:
  it tests the system as a black box across component boundaries, often
  needs to run against multiple *released* versions rather than just HEAD,
  and is realistically QE-owned rather than dev-owned — reasons that hold
  independent of how the product code is organized. (Kubernetes itself
  splits this both ways — some e2e in-tree, some in separate repos — so
  there's no single industry-standard answer here; this is a judgment call,
  not a precedent-backed conclusion like the other pieces of this proposal.)
- **`enhancement-proposals` and `docs`:** unaffected. The docs/website
  question (standalone repo vs. folder in `osac`) is low-stakes either way —
  `kubernetes/website` stays separate from `kubernetes/kubernetes` even in an
  otherwise-polyrepo ecosystem — and isn't part of this proposal.

## Precedent

Go-backend-plus-TypeScript/React-frontend-in-one-repo is well-established at
real scale, using workspace tooling rather than a heavyweight build system
like Bazel:

- **Grafana** (`grafana/grafana`) — Go backend (`pkg/`) + TypeScript/React
  frontend (`public/app/`), one repo, Go workspaces (`go.work`) for the
  backend and Yarn workspaces for the frontend. Their own `AGENTS.md`
  describes it plainly as "monorepo with Yarn workspaces (frontend) and Go
  workspaces (backend)."
- **HashiCorp Vault and Nomad** — Go backend, Ember.js `ui/` directory,
  single repo, since Vault ~0.9.0 (Dec 2017) — nearly 9 years at production
  scale, still actively maintained (Nomad shipped an Ember LTS modernization
  in April 2026).

## Why Not Now

Technically low-risk, but not something to execute unilaterally:

- **OSAC already has direct, recent proof this mechanic works — verified,
  not assumed.** The OSAC-1739 consolidation left `osac` with 12 workflows
  under native GitHub `on.pull_request.paths` filters today (e.g.
  `publish-image.yaml` scoped to `fulfillment-service/**`,
  `build-bmf-image.yaml` to `bare-metal-fulfillment-operator/**`,
  `execution-environment.yml` to `osac-aap/**`), each excluding its own
  `OWNERS`/`LICENSE` files — this part of "the same playbook" is real and
  already running, not aspirational. Ownership routing, however, uses 7
  Prow-style per-directory `OWNERS` files rather than a GitHub-native
  `CODEOWNERS` file — a materially different mechanism (Prow bot-mediated
  approval vs. GitHub's built-in reviewer assignment) that already gives
  path-based review routing today, just not under the name this proposal
  uses. Adding `osac/ui/` would mean extending the existing `paths:`/`OWNERS`
  convention with one more component, not inventing path-scoping from
  scratch.
- **Change fatigue is real.** That consolidation only just landed. Stacking a
  second one immediately after has a cost independent of its technical
  merits.
- **It needs buy-in this record can't grant alone.** This changes the UI
  team's release cadence and CI ownership, and requires an explicit decision
  about whether `osac-installer`'s versioned-OCI-image dependency on
  `osac-ui` continues unchanged (mono-repo components already publish
  versioned images this way today, so the mechanism should transfer, but
  someone who owns that pipeline should confirm it) or changes shape.
- **The gain is incremental, not urgent.** The current meta-repo pattern
  already gives AI agents (and humans) cross-repo context today, just via
  documentation rather than by default. This would upgrade that to atomic
  cross-repo commits and a single CI/versioning source of truth — a real
  improvement, but not fixing something currently broken.

## Migration Path (if this moves forward)

1. Socialize this record with `osac-ui` and `osac-test-infra` maintainers —
   this should not be decided by `osac-workspace` tooling changes alone.
2. If there's appetite, likely warrants its own Jira Feature/EP through the
   normal `/prd` → `/design` flow, given it affects release cadence and CI
   ownership beyond `osac-workspace`.
3. History-preserving merge of `osac-ui` into `osac/ui/` — `git filter-repo`
   or `git subtree`, matching whichever approach OSAC-1739 used, but evaluate
   [Josh](https://github.com/josh-project/josh) first if that was subtree:
   the Rust project's June 2026 write-up describes subtree becoming "entirely
   unusable" (hours-long syncs that never finished) on repos with non-trivial
   history, which is why they built Josh as a faster replacement.
4. Add path-scoped `paths:` CI filters and `CODEOWNERS` (or extend the
   existing per-directory `OWNERS` convention — `osac` already has 12
   workflows scoped this way, and 7 `OWNERS` files; see Why Not Now) so UI
   and backend changes route to the right reviewers and don't cross-trigger
   unrelated builds.
5. Confirm or redesign the `osac-installer` → `osac-ui` OCI-image versioning
   relationship now that they share a repo.
6. Update the current sibling-repo clone list to drop `osac-ui`. As of this
   writing that's `osac-workspace`'s `bootstrap.sh` and `AGENTS.md`; if
   [0001](0001-dedicated-ai-skills-repo.md)'s transition has landed by the
   time this executes, the equivalent list lives in `osac/`'s own bootstrap
   instead.

## Non-Goals

- This record does not decide anything by itself — it exists so the option
  is written down durably instead of only living in chat history.
- Does not propose merging `osac-test-infra` or `enhancement-proposals`.
- Does not set a timeline. No urgency is implied by writing this down.

## References

- `grafana/grafana` — [`AGENTS.md`](https://github.com/grafana/grafana/blob/main/AGENTS.md), architecture docs
- HashiCorp Vault (`hashicorp/vault`) and Nomad (`hashicorp/nomad`) — in-tree `ui/`
- OSAC-1739 — recent backend mono-repo consolidation, proof of migration mechanics
- `AGENTS.md`'s Deployment Coordination section — current `osac-ui` OCI-image versioning relationship
- [Josh](https://github.com/josh-project/josh) — Rust project's git-subtree replacement, relevant to Migration Path step 3
- Direct check (`grep`/`find` against live `osac/.github/workflows/` and
  top-level `OWNERS` files) confirming path-scoped CI already exists (12
  workflows) though `CODEOWNERS` specifically does not (7 `OWNERS` files
  instead)
