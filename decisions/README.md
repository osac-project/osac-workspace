# Architecture Decision Records

This directory records significant, durable decisions about `osac-workspace`'s own
architecture — its topology (meta-workspace vs. mono-repo vs. plugin marketplace),
how AI skills are distributed, and how the workspace relates to sibling repos
(`osac`, `osac-ui`, `enhancement-proposals`, etc.).

These are decisions *about the workspace itself*, not about OSAC the product —
product architecture decisions belong in `enhancement-proposals` (see
[`AGENTS.md`](../AGENTS.md)'s Enhancement Proposals section) or in the affected
component's own docs.

## Why this exists

`.planning/` is gitignored and local-only — useful for personal scratch work, but
not for a decision the whole team should be able to find later. Decisions here are
committed and durable for that reason.

## Format

Each record is a numbered markdown file (`NNNN-short-title.md`), loosely following
the standard [Michael Nygard ADR template](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions):

- **Status** — Proposed, Accepted, Superseded (by `NNNN`), or Rejected
- **Context** — what prompted the decision, what constraints applied
- **Decision** — what was decided
- **Options Considered** — alternatives evaluated and why they weren't chosen
- **Consequences** — what this makes easier or harder, and any follow-up work
- **References** — sources, commits, and prior art the decision relied on

Add a new file rather than editing an old one once a decision is Accepted; if a
later decision reverses an earlier one, mark the old record Superseded and link
to the new one instead of deleting it.
