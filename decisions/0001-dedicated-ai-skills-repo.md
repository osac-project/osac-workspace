# 0001. Dedicated AI Skills Repo, `osac/` as Primary Workspace, Phased `osac-workspace` Retirement

- **Status:** Accepted
- **Date:** 2026-08-06

## Context

Most of OSAC's component repos have consolidated into a single mono-repo (`osac`).
Two concrete gaps remain now that most day-to-day development happens there
instead of in a checked-out meta-repo:

1. **Developer ergonomics.** Using OSAC's AI skills (Claude Code / Cursor /
   Gemini CLI) today requires checking out a separate meta-repo
   (`osac-workspace`) even though the actual product code lives in `osac/`.
   A developer who only wants to work in `osac/` still has to clone, and keep
   up to date, a second repo just to get skills.
2. **Automated AI SDLC tooling.** Frameworks and bots that operate directly
   against `osac/` — Forge, fullsend, jira-autofix, agentic-ci, and similar —
   need a reliable way to get OSAC's skills with the right context. Unlike a
   human, these often run in ephemeral or CI-triggered environments where
   there's no guarantee an interactive bootstrap step gets run, or anyone
   around to run it.

Separately, and useful as real-world validation rather than a starting
assumption: RHEM's Flight Control team — whose `ai-workflows` tooling OSAC
itself already consumes — was asked directly how they handle the same
questions (skill placement, spec placement, protecting instruction/spec files
from the agents they constrain) and volunteered their own working setup.
Their answers, condensed:

- **Skill placement:** depends on scope, but "if no other good reason,
  I will lean towards keep the skills apart from the code." Generic skills
  deserve their own place, same as any open-source project would treat them.
  Even privately-scoped, dedicated skills are worth keeping decoupled from
  the code — it forces cleaner separation of concerns. The one real exception
  they name explicitly: a skill that must physically execute *next to* the
  code (e.g., something invoked from that repo's own CI) is a genuinely
  different case from a skill that merely operates *on* that code from
  outside.
- **Spec/design-doc placement:** "definitely apart." Colocating PRDs/design
  docs with product code makes the repo grow with content that goes stale
  fast — "very rare circumstances" justify digging up a year-old PRD, so
  there's little upside to paying that cost.
- **Protecting instruction/spec files from the agents they constrain:**
  their stance, condensed — the human stays accountable for any generated
  content, and reviewing/approving it before it merges is the actual
  mechanism; everything else is implementation detail. They explicitly
  avoid `CODEOWNERS` at their team's current size (~15 people), but noted
  they'd likely answer differently at OSAC's scale.
- **What they actually run:** three separate repos — product code, AI
  workflows (skills), and design docs (PRD/design/test-plan, kept private
  since it references their Jira instance heavily) — reporting that this
  separation of concerns "is working very well."

That last point — three repos, not two — is the concrete new data point this
record acts on: it validates keeping skills *and* design docs apart from
product code as a pattern already proven elsewhere, not just an OSAC-specific
guess.

## Decision

1. **Create a new, dedicated repo whose only purpose is hosting OSAC's AI
   skills and the content/tooling that only exists to support or validate
   them** — the skill files themselves, the skill-authoring/linting
   convention (`.skillsaw.yaml` + its CI), the *generic* skill fan-out logic
   (today's `link-agent-skills.sh` — turning a `skills/` directory into
   `.claude/`/`.cursor/`/`.gemini/` symlinks, a property of the skills
   content itself and portable to whatever clones it, not specific to any
   one consumer repo), and skill-backing assets. This includes the
   skill-quality eval harness that already exists today (currently
   `osac-workspace/evals/`, grading `design-review`/`prd-review` skill
   output — not a hypothetical future addition), and any eval coverage
   added later for other skills follows it to the same repo, for the same
   reason: it only exists to grade skill output, so it has no independent
   reason to live anywhere else. **Final name: `osac-ai-skills`** (repo
   created 2026-08-10, `osac-project/osac-ai-skills`) — see Naming
   Candidates below for how that lands relative to this record's own
   analysis, and note explicitly that the content boundary above (fan-out
   script, `.skillsaw.yaml`, eval harness — not just skill files) stays as
   proposed; the name was decided pragmatically, not by narrowing scope to
   match it.
   **Explicitly not moving yet: the `decisions/` ADR history, including
   this record.** An earlier pass of this item listed "the ADRs that govern
   this space" as part of what moves here, but `decisions/` in
   `osac-workspace` today isn't skills-only — it also holds
   [0002](0002-osac-ui-monorepo-consolidation.md), an unrelated
   `osac-ui`/`osac` topology decision — so "move the ADRs" isn't a clean
   directory copy without first splitting skills-governance records from
   everything else `decisions/` accumulates. Deferred rather than decided:
   `decisions/` stays in `osac-workspace` for now, and whether skills-
   specific ADRs eventually get a home in `osac-ai-skills` (by splitting
   the history, starting a fresh ADR trail there, or something else) is an
   open question, not a rejected one. See the exit-criteria list in
   Consequences, which now carries this as its own item.
2. **What does *not* move here: the bootstrap/orchestration logic that
   decides what to clone and when.** That's `osac/`'s own onboarding entry
   point — it already partially exists as `osac/tools/bootstrap.sh` today —
   and it grows there, not in the new skills repo. Extend it to: (a) vendor
   the new skills repo and invoke its fan-out script, so a developer who
   only ever clones `osac/` gets skill parity with today's `osac-workspace`
   experience, no second interactive checkout required; and (b) **clone
   `enhancement-proposals` as a sibling too**, for the identical
   dev-ergonomics reason — several skills (e.g. the PRD/design `/respond`
   phases) depend on it being present, and `osac-workspace`'s bootstrap
   already clones it today. Build this as an extensible, declarative list of
   siblings to clone (starting with the new skills repo and
   `enhancement-proposals`; `osac-ux`/`osac-test-infra`/others added as
   concrete skill needs are identified), not a one-off hardcoded case that
   has to be re-architected every time another sibling turns out to be
   needed.
3. **Automated frameworks consume a pinned copy of the skills repo, not a
   floating one — populated the moment `osac/` is checked out, with a bump
   showing up as a small, auditable diff against `osac/`'s own history, not
   a dependency that can change underneath a consumer with no PR to
   review.** That's the actual requirement; this record does not name a
   specific mechanism for it, for a concrete reason: **an earlier draft did
   name one — a plain `git submodule` reference — and that was wrong, not
   just imprecisely worded.** A submodule entry is only a pointer (a
   `.gitmodules` line plus a `160000` gitlink SHA in the tree); by default,
   `git clone`/checkout of `osac/` leaves that directory **empty**, not
   populated, unless whatever does the checkout separately runs `git
   submodule update --init --recursive` (or clones with
   `--recurse-submodules`, or a CI checkout action is explicitly configured
   with `submodules: true`/`recursive`). A mechanism that can silently yield
   an empty directory instead of either real content or a hard failure
   doesn't satisfy "populated the moment it's checked out" — it just moves
   the same missing-step problem `osac/`'s bootstrap script already solves
   for humans (item 2) onto every automated consumer's own checkout
   configuration instead, with a worse failure mode (silent, not loud) than
   not having a mechanism at all. Reusable-workflow SHA-bumping precedent
   doesn't rescue this either: `osac`'s existing `bump-submodules.yaml` bot
   bumps a SHA string embedded in workflow YAML for a GitHub Actions
   *reusable-workflow reference* (`osac-test-infra`), not a submodule
   checkout — a different mechanism that produces no local file tree, so it
   couldn't back a skill fan-out on its own regardless. `osac` also has no
   real `git submodule` anywhere today to build on (confirmed: no
   `.gitmodules` file, no `160000` gitlink entries in the tree).

   **Candidate mechanisms that actually meet the requirement** — populated
   without a separate opt-in step, *and* pinned/reviewable, evaluated but
   not chosen between here, the same treatment as Naming Candidates below:

   | Candidate | Meets the requirement because... | Cost |
   |---|---|---|
   | `git subtree` | Content is physically copied into `osac/`'s own tree/history at merge time — any plain clone already has it, no population step exists to forget | Each bump is a full-content diff, not a one-line pointer change (noisier, though arguably more literally reviewable); `git subtree`'s UX has a real learning-curve reputation |
   | Custom vendor/copy bot | Same physically-present outcome as `subtree`, via bespoke automation that copies files and opens a PR — reuses the poll/diff/open-a-PR *pattern* `bump-submodules.yaml` already proves, just copying content instead of bumping a pointer | New automation to build and maintain, same as any option here; OSAC fully owns and understands it, unlike a third-party tool |

   A `git submodule`, a bare `git clone` (floating, matching item 2's own
   precedent), and marketplace/registry-style or agent-skill-package-manager
   pointers/tools — Microsoft's APM included (see Options Considered below)
   — are all excluded from this table — each was checked directly above or
   below and found not to meet the requirement, or (for the package-manager
   category) to be solving a different problem than the one this table is
   for. Whichever candidate is chosen, a new bump-bot still needs to be
   built following the poll/diff/open-a-PR *pattern* `bump-submodules.yaml`
   already proves — that pattern is reusable regardless of mechanism; the
   mechanism itself is new work either way, not an assumption that one
   already exists.
4. **`osac-workspace` keeps its current meta-repo role, unchanged, for a
   defined transition window.** It is not degraded or partially dismantled
   while `osac/`-based development is being proven out — in-flight work is
   not disrupted for this migration. **This creates a real, named risk this
   record does not fully resolve:** once `skills/` migrates out of
   `osac-workspace` into `osac-ai-skills`, `osac-workspace`'s own copy needs
   to become a *consumer* of the new repo (vendored the same way `osac/`
   will, per item 2) rather than an independently-editable leftover —
   otherwise the transition window itself recreates the exact
   two-source-of-truth drift this record exists to eliminate, just between
   `osac-workspace` and `osac-ai-skills` instead of between `osac-workspace`
   and `osac/`. Whoever executes the migration should not treat
   `osac-workspace/skills/` as done merely by copying it out — the copy
   left behind needs to stop being a live source, not just gain a sibling.
5. **Decommission `osac-workspace` once `osac/`-based development is proven
   fully equivalent**, against concrete exit criteria (see Consequences),
   not a calendar date alone.

## Naming Candidates

**Decided: `osac-ai-skills`** (repo created 2026-08-10). The analysis below
predates that decision and is kept as the record of what was actually
weighed — including why this record's own analysis leaned toward a
different name — not as a still-open question:

| Candidate | Fits if... | Risk |
|---|---|---|
| `osac-ai-skills` | Content stays skill files (+ light supporting docs) only | Weaker risk than an earlier draft of this table claimed — reviewed feedback pointed out that keeping a skill's evaluation right next to the skill (or in the same repo) is itself common practice, so the eval harness's presence doesn't by itself force a broader name; `osac-ai-skills` can still hold `design-review`/`prd-review` grading comfortably. What's left of the risk is narrower: the fan-out script and `.skillsaw.yaml` linting read a little less like "skills" than infrastructure *around* skills, and would only grow as eval coverage expands — a real but softer scope mismatch than originally framed. Note: the bootstrap/orchestration script itself is *not* part of this scope question — Decision item 2 keeps that in `osac/` regardless of what this repo is named |
| `osac-ai-workflows` | Content is broader — skills plus the tooling/process around them, mirroring `flightctl/ai-workflows`'s naming | **Name collision risk, not just style**: `flightctl/ai-workflows` is already vendored into this ecosystem today (`.ai-workflows/` is the actual local directory name after bootstrap runs) — a same-named OSAC repo would make "which `ai-workflows` do you mean" a real, recurring, concrete confusion, not a matter of degree |
| `osac-ai-helpers` | Same broad scope, mirrors OpenShift's `ai-helpers` naming | No real collision risk — checked directly, OSAC doesn't actually consume OpenShift's `ai-helpers` anywhere (no vendored directory, nothing cloned, nothing referenced in tooling), unlike `flightctl/ai-workflows`. It's purely a naming-convention echo of an unrelated project's tooling repo, not a functional relationship — OSAC provisioning OpenShift clusters is a product fact that has nothing to do with what OSAC names its own AI tooling repo |
| `osac-ai-tooling` | Broad scope, deliberately neutral/generic | No collision risk, no borrowed identity either way — but also no positive case beyond "safe" |

`osac-ai-workflows` is ruled out regardless of scope — that's a concrete
collision (an identical name already in active use in this ecosystem), not
a soft risk to weigh.

**Keep the `osac-` prefix regardless of suffix — don't drop to a bare
`ai-skills`/`skills`.** Living in the `osac-project` GitHub org only
disambiguates the name within GitHub's own URLs and UI; the moment it's
`git clone`'d locally (which defaults to a folder named after the repo, not
the org) or vendored as a sibling inside `osac/`'s own tree (Decision item
2), that org context disappears entirely. This isn't a hypothetical
collision to weigh, either — checked directly, `ai-skills` and bare
`skills` are both already in active, unrelated use as repo names for
exactly this category of tool (`lgtm-hq/ai-skills`, `PMelch/ai-skills`,
`kevin-lee/ai-skills`, `anthropics/skills`), several of which are
themselves skill-management CLIs that create their own local `ai-skills`/
`skills` directory. That's the same class of risk that already rules out
`osac-ai-workflows` against `flightctl/ai-workflows` above, just against a
far more generic, far more commonly-chosen term — so the case against
dropping the prefix is at least as strong. It also matches the org's
existing convention: every live OSAC product/tooling repo carries the
`osac-` prefix (`osac`, `osac-ui`, `osac-ux`, `osac-workspace`,
`osac-test-infra`, `osac-aap`, `osac-installer`, `osac-csi-driver`,
`osac-operator` and its variants); the unprefixed exceptions
(`enhancement-proposals`, `docs`) are content repos whose names are
unambiguous enough on their own not to need it — `ai-skills` doesn't share
that property.

**This record's own analysis leaned toward `osac-ai-tooling`** — it fits the
broader content this repo is expected to hold, and needs no borrowed story
to justify it. `osac-ai-skills` was flagged as a closer contender than an
earlier pass of this table suggested (review feedback noted that colocating
a skill's eval with the skill itself is normal practice, so the eval
harness alone doesn't disqualify it), but was still expected to read
narrower than the fan-out script and `.skillsaw.yaml` linting this repo
also carries.

**The actual decision landed on `osac-ai-skills` anyway** — the name
originally floated informally in the Slack thread that prompted this
record, before this table's deeper analysis existed. The content boundary
did not narrow to match it: this repo still carries the full scope Decision
item 1 describes (minus `decisions/`, deferred per that item), not just
skill files. Worth naming plainly for anyone reading this later: the chosen
name and this record's own top pick diverged, and that's fine —
`osac-ai-skills` is not a bad name for what's actually there, just a less
precise one than `osac-ai-tooling` would have been for the broader content.

## Options Considered

- **Fold skills directly into `osac/`, no dedicated repo.** Rejected: most
  current OSAC skills are inherently cross-repo by nature (they operate
  across `osac`, `osac-ui`/`osac-ux`, `enhancement-proposals`, etc.), which
  doesn't fit living inside any single component repo. Also loses the
  structural separation Flight Control specifically credits for forcing
  decoupled thinking, and collapses the natural boundary that keeps a
  product-code PR and a skill-instructions PR visibly distinct.
- **Keep `osac-workspace` as the permanent skill source of truth,
  unchanged.** Rejected: solves neither concrete gap above — a developer
  working purely in `osac/` still needs a second checkout, and automated
  frameworks still need to reach into a separate repo with no pinned,
  reviewable reference.
- **A new, dedicated skills repo, vendored by `osac/`.** Chosen — matches
  Flight Control's validated three-repo pattern, solves both concrete gaps,
  and doesn't force an immediate, disruptive decommission of
  `osac-workspace`.
- **Distribute the new skills repo through a Claude Code plugin marketplace
  instead of a plain git-clonable repo.** Considered, deferred: this
  ecosystem already tried this once and reversed it. Before April 2026,
  OSAC's skills ran through Claude Code plugin marketplaces
  (`osac-dev`/`jira`/`osac-ep-generator`), and were migrated into a plain
  repo-local `skills/` directory specifically "to eliminate the plugin
  marketplace setup requirement" so skills "work for everyone who clones
  the repo with zero additional config" (`da0a6f95`) — that's also where
  the now-stale `osac-dev:fix-bug` reference fixed elsewhere came from.
  Revisiting it now would need to explain what's actually changed since;
  checked directly, little has. The mechanism is Claude-Code-specific —
  `.claude-plugin/marketplace.json` has no Cursor/Gemini CLI equivalent —
  so it can't replace the plain repo this decision already calls for.
  Cursor/Gemini consumers, and item 3's pinned-copy requirement for
  automated frameworks, would still need the plain repo regardless, meaning
  a marketplace could only ever be an *additional* mechanism layered on
  top, not a substitute for one. It also wouldn't match the one real
  vendoring precedent already in place: `flightctl/ai-workflows` is
  vendored via plain `git clone`/`git rebase` into `.ai-workflows/`
  (`bootstrap.sh`), not a marketplace. On version-control maturity
  specifically: `CLAUDE_CODE_PLUGIN_SEED_DIR` genuinely solves
  non-interactive CI consumption for Claude-Code-based automated
  consumers, but SHA-pinning for one marketplace repo holding many
  relative-path plugins (this repo's actual shape) is still an open,
  unshipped upstream feature request (`anthropics/claude-code#33653`) —
  less mature than the plain-git-mechanism candidates (`git subtree`, a
  custom copy-bot) item 3 lists above, which pin by committed content
  rather than a plugin cache's resolved version string.
  It also wouldn't simplify the naming question above: marketplace and
  plugin names are flat, manually-chosen strings with no automatic
  org-scoping (unlike, say, npm's `@scope/package`), so the same collision
  logic that argues for keeping the `osac-` prefix on the repo would just
  move to the marketplace/plugin name instead — as it already did the
  first time around (`osac-dev:fix-bug`). Worth revisiting later as an
  optional, additional path specifically for Claude-Code-based automated
  frameworks (the open follow-up on framework consumption below), not as
  this record's primary mechanism.
- **Build a registry-catalog layer (à la `opendatahub-io/skills-registry`)
  on top of the new skills repo, and use it to also reference
  `flightctl/ai-workflows`.** Surfaced during review with a concrete
  example (`opendatahub-io/skills-registry`, plus a specific proposal to
  install flightctl's workflows as `flightctl@prd` through it). Checked
  both halves directly rather than evaluating in the abstract:

  - **What the reference example actually is, confirmed against its live
    `registry.yaml`:** a catalog of pointers (`source: {repo, ref}` +
    `skills_dir`) to skill files living in *other* repos — the registry
    itself vendors nothing; a generated `.claude-plugin/marketplace.json`
    is what Claude Code reads, and it fetches real content from each
    entry's source repo at install time. That's the same
    Claude-Code-specific, pointer-not-vendor category already weighed
    above, just with a catalog layer in front of it — so it inherits the
    same conclusion (doesn't replace the plain repo; Cursor/Gemini still
    need direct installation per that project's own README). It also adds
    a concrete, observed data point to the version-control-maturity
    question above: of the ~20 externally-sourced entries in that live
    `registry.yaml`, **zero use `sha:` pinning — all 20 float on a branch
    `ref`** — despite the schema supporting commit-SHA pinning. That's the
    floating-dependency risk item 3 is explicitly designed against, shown
    happening in practice in a real, comparable implementation, not just
    a theoretical gap.
  - **Whether `flightctl/ai-workflows` specifically could be referenced
    this way:** checked its actual layout directly — no
    `.claude-plugin`/`plugin.json` anywhere in that repo, so it isn't
    already shaped as an installable plugin bundle. Each workflow (e.g.
    `prd/`) splits into a `skills/` directory *and* a separate `commands/`
    directory — the latter holding the thin wrapper files (e.g.
    `prd:ingest`) that are the actual `/prd:ingest`-style invocation
    surface `AGENTS.md` documents. A `skills_dir`-only registry pointer,
    which is all the reference implementation's schema supports (checked:
    every one of its ~20 entries sets `skills_dir`, none anything
    equivalent for commands), would only capture the `skills/` half. The
    command wrapper content itself turned out to be simple, static,
    relative-path pointer files rather than deeply project-templated —
    so capturing both halves isn't structurally impossible — but doing so
    would mean OSAC building and maintaining its own extended
    registry schema/generator against `flightctl/ai-workflows`'s internal
    directory conventions, duplicating translation work `install.sh`
    already does and keeps in sync on flightctl's own side. If flightctl
    restructures a workflow's internal layout, that bespoke entry drifts
    silently; today's `install.sh`-driven vendoring absorbs that risk
    instead. The payoff for taking it on is thin — a nicer Claude-Code-
    only discovery/`/plugin update` UX, no new capability `bootstrap.sh`'s
    existing fetch-and-rebase doesn't already provide, and nothing for
    Cursor/Gemini CLI consumers either way.
  - **Conclusion, sharpened after weighing it directly (not just
    scoping it, rejecting the pattern itself):** the registry-catalog
    *pattern* is built to solve a federation problem — checked the live
    `registry.yaml` again specifically for this: all 20 entries point
    outward to external repos, spanning five different orgs/individuals,
    with zero self-hosted/local entries. That's the whole point of the
    layer — aggregating skills scattered across many separately-owned
    repos into one catalog. OSAC doesn't have that problem: Decision item
    1 already centralizes every OSAC skill into one repo by design, so
    there's no scattered ownership to federate. Layering a `registry.yaml`
    + generator on top of a single, already-centralized repo solves
    nothing a direct `.claude-plugin/marketplace.json` in that same repo
    wouldn't already solve more simply. And even that simpler, direct
    marketplace.json doesn't move either of this record's two concrete
    problems (Context, above): it reaches only Claude Code, one of three
    supported harnesses, and does nothing for automated/non-interactive
    consumption — the plain-repo-plus-fan-out-script path already planned
    covers all three harnesses uniformly, with no extra interactive step.
    So: **not planned, and not treated as a live open follow-up** — a
    bare `marketplace.json` (skipping the registry/generator layer
    entirely) stays a cheap, low-priority *maybe* if Claude-Code-specific
    discovery UX ever becomes something people actually ask for, not
    something to build speculatively now. `flightctl/ai-workflows` stays
    exactly what it is today: a separate, `install.sh`-driven dependency,
    untouched by any of this.
- **Distribute/pin the new skills repo through Microsoft's APM (Agent
  Package Manager) or an equivalent "AI agent skill package manager."**
  Surfaced during review; evaluated, then the whole category was ruled
  out — not treated as a live open follow-up.
  Unlike a bare Claude Code plugin marketplace, APM is genuinely
  cross-agent: one `apm.yml` manifest deploys the same declared primitives
  to Claude Code, Cursor, Gemini, Copilot, and others from a single
  command, and its docs describe deployed output as committed into the
  *consuming* repo (avoiding the empty-directory failure mode above), with
  a content-hash-pinned lockfile (`apm.lock.yaml`) and a `--frozen` CI
  mode. On "Microsoft-authored" specifically being a blocker for a Red Hat
  project — checked directly, not assumed: `microsoft/apm` is MIT-licensed
  (confirmed against its actual `LICENSE` file), the same permissive
  category as other Microsoft-originated projects Red Hat already
  consumes or contributes to (VS Code, TypeScript, and others). Licensing
  was never the real question.
  **What actually rules the category out is fit, not trust, and not any
  one tool's specific flaws.** A deliberate landscape check beyond APM
  alone (Microsoft's is not the only entrant — `PSPM`, `spazyCZ/`
  `agent-package-manager`, `helincao/skilled`, `usescrolls/scribe`,
  `chrismdp/airskills`, and `EvanL1/aitoolsync` all showed up covering
  overlapping ground) confirms this whole tool category is solving a
  different problem than OSAC has: distributing many independently-versioned
  skills from many separate authors/sources across 30-40+ agent harnesses
  a given developer might have installed locally. OSAC has one already-
  centralized skills repo (Decision item 1), a small, known set of
  consumers, and exactly three harnesses to support (Claude Code, Cursor,
  Gemini CLI) — a problem OSAC's own ~50-line `link-agent-skills.sh` fan-out
  script already solves today, understood and owned in-house. Every tool
  found, APM included, is also comparably young (all created within
  roughly the last year as of this check) and comparably unproven at OSAC's
  trust bar — so even setting the fit problem aside, none of them is a
  clearly *safer* choice than APM specifically, which removes the "maybe a
  better APM-like alternative exists" escape hatch along with APM itself.
  Adopting any of them would mean taking on a new third-party dependency to
  replace something already working, not to solve something otherwise
  unsolved. `git subtree` and a custom copy-bot (item 3's remaining
  candidates) need nothing beyond plain `git` and this ecosystem's existing
  poll/diff/open-a-PR pattern.

## Consequences

- Fully solves one of the two concrete touch points from Context — developer
  ergonomics (item 2's bootstrap extension) — without requiring
  `osac-workspace` to disappear on day one. **The other, automated framework
  consumption, is only partially solved: item 3 states the actual
  requirement and rules out the mechanism an earlier draft wrongly assumed
  (`git submodule`), but does not pick a mechanism from its own candidate
  list.** Until that choice is made, Forge/fullsend/jira-autofix/agentic-ci
  have no concrete way to consume skills yet — one of this record's two
  founding problems stays open in practice, not just as an implementation
  detail to fill in later.
- Matches a real, working pattern already proven by a peer AI SDLC framework
  OSAC itself depends on, rather than a purely internal guess.
- **Resolved — naming.** `osac-ai-skills` is the final name
  (`osac-project/osac-ai-skills`, created 2026-08-10), decided ahead of
  this record's own analysis rather than by it — see Naming Candidates for
  the full account, including that the content boundary stayed broad
  (fan-out script, `.skillsaw.yaml` linting, eval harness) rather than
  narrowing to match the name. `decisions/` is the one exception — see
  Decision item 1 and the exit-criteria item below.
- **Open follow-up — concrete exit criteria for decommissioning
  `osac-workspace`.** "Once we're sure development from within `osac/` is
  100%" needs to become a checkable list before it can actually trigger
  action. At minimum, this needs: (a) the new skills repo live and vendored
  successfully by `osac/`'s bootstrap; (b) `osac-workspace`'s root context
  (`AGENTS.md`/`CLAUDE.md`) reconciled into `osac/`'s own, since they've
  evolved independently and don't just concatenate; (c) a decided new home
  for `osac-workspace`'s live PR-dashboard site, which has nothing to do
  with skills and needs its own resolution; (d) a decision on whether
  `osac-workspace`'s dev-container tooling (`Containerfile`, distrobox
  `Makefile` targets) is ported to `osac/` or intentionally dropped; (e) a
  decided placement for `osac-workspace`'s cross-repo `reference/` docs,
  which describe the multi-repo ecosystem as a whole rather than any one
  component; (f) a decided placement for `decisions/` itself (this ADR
  history, plus [0002](0002-osac-ui-monorepo-consolidation.md) and
  whatever accumulates alongside it) — deliberately not moved into
  `osac-ai-skills` by Decision item 1, so it needs its own resolution
  before `osac-workspace` can go away, not just a default "it goes wherever
  skills went."
- **Open follow-up — protection strategy for the new skills repo.** OSAC's
  baseline expectation here is the same one used everywhere else in this
  ecosystem: a human reviews and approves a change before it merges —
  that's the actual strategy, not a new practice invented for this repo.
  Flight Control's answer corroborates that this expectation holds up at
  their scale too, but it's evidence for the approach, not the source of
  it. OSAC already has a per-component `OWNERS` file convention (Prow-style
  `approvers`/`reviewers` YAML — `osac/OWNERS`,
  `osac/fulfillment-service/OWNERS`, `osac-workspace/OWNERS`, etc.), so
  adding one for the new skills repo is just following existing practice,
  not introducing anything new. **But it's worth being precise that this
  convention isn't actually enforced today**: confirmed directly against
  the `osac-project/osac` repo that no `.github/CODEOWNERS` file exists (the
  `OWNERS` files are a different, Prow-native format that GitHub itself
  doesn't read), there's no branch-protection rule on `main`, and the one
  active ruleset (`ci-status-checks`) only gates required status checks, not
  review requirements. So today, `OWNERS` files are a documentation/
  convention layer for humans to know who to tag, not a technical gate —
  anyone with write access can currently merge without an `OWNERS`-listed
  approval. Whether to close that gap (a native `.github/CODEOWNERS` file
  plus a ruleset requiring code-owner review, or a Prow-style bot that
  actually reads `OWNERS`) is a real, OSAC-wide question that applies
  equally to every existing repo/component, not something specific to
  introduce just for the new skills repo.
- **`osac/`'s bootstrap clones `enhancement-proposals` too, not skills
  alone** (Decision item 2). **Still open:** which
  additional siblings beyond `enhancement-proposals` (`osac-ux`,
  `osac-test-infra`) actually need to be in that default clone list versus
  added only when a concrete skill need identifies them, and whether
  automated frameworks need the same sibling set or their own narrower
  answer per framework. Decision item 2 asks for this to be built as an
  extensible, declarative list specifically so that question doesn't have
  to be fully answered up front.
- **Open follow-up — trust boundary for non-interactive bot consumption.**
  A pinned skills repo consumed automatically by CI-triggered frameworks
  (no human bootstrap step in between) means a bad or malicious skill
  change could reach an automated pipeline with real credentials/deploy
  access as soon as its PR merges and the pin bumps — even if a human
  reviewed the skill PR itself, they may not have full visibility into what
  a given automated framework actually grants that skill at runtime. This
  is a distinct risk from the reward-hacking/self-certification concern
  already named for skill *authorship* — this one is about blast radius
  once a change is consumed, not about who wrote it. Not resolved here.
- **Resolved — does OSAC actually control how these frameworks consume
  skills?** Confirmed directly (2026-08-10): yes. OSAC controls
  configuration for Forge, fullsend, jira-autofix, and agentic-ci even
  where the underlying engine is shared — jira-autofix's engine is
  understood to be part of Flight Control's tooling (the same provider
  behind `ai-workflows`, which OSAC already depends on), but OSAC
  configures and uses it for its own purposes, the same
  shared-engine/OSAC-configured relationship assumed for the other three.
  This answers the precondition the previous version of this bullet
  flagged as blocking: picking a pinned-copy mechanism (item 3) does not
  need another team's buy-in — OSAC can require its own consumption path
  from these frameworks unilaterally. **Confidence note:** this is a
  first-hand confirmation, not independently verified against each
  framework's own documentation (none of the four have any footprint in
  this workspace to check against — confirmed by grepping the full
  workspace, including git history, for all four names before asking).
  Item 3's mechanism choice (`git subtree` vs. a copy-bot) remains the
  next actionable decision — no longer blocked, just not yet made.

## Non-Goals

- Does not move `decisions/` (this ADR history) into `osac-ai-skills` —
  deferred, not decided against. It isn't skills-only content today (see
  Decision item 1), so moving it needs its own resolution rather than
  riding along with the rest of this record's content boundary.
- Does not commit to a specific decommission date for `osac-workspace` —
  ties it to exit criteria instead.
- Does not change anything about `enhancement-proposals` staying a separate
  *repo* from `osac` — Flight Control's answer on spec/design-doc placement
  reaffirms that direction. `osac/`'s bootstrap cloning it as a sibling
  (Decision item 2) is a dev-ergonomics change, not a merge — it stays a
  fully independent repo with its own history, ownership, and lifecycle,
  the same relationship it already has with `osac-workspace` today.
- Does not specify the exact migration tooling (`git filter-repo`, `git
  subtree`, or similar) for the one-time move of `skills/` and its
  supporting directories out of `osac-workspace` into the new repo — an
  implementation detail for whoever executes this, and a different
  question from item 3's candidate mechanisms above (which cover pulling
  the new repo's content back *into* `osac/` on an ongoing basis, not this
  one-time split — `git subtree` shows up in both discussions for
  unrelated reasons, don't conflate them).
- Does not pick a mechanism for item 3's pinned-copy requirement — `git
  subtree` and a custom copy-bot are laid out as candidates (APM and the
  wider "AI agent skill package manager" category were evaluated and
  ruled out, not left open — see Options Considered), with the choice
  between these two remaining candidates deferred to implementation.

## References

- `osac-project/osac-ai-skills` (created 2026-08-10, confirmed empty via
  `gh api repos/osac-project/osac-ai-skills` — no branches, no content yet)
  — the actual repo, settling the naming question this record's own
  analysis (Naming Candidates) had left as a `osac-ai-tooling` lean
- Internal Slack discussion, 2026-08 — naming proposal (`osac-ai-skills`)
  and the question of why `flightctl`/OpenShift name their equivalent repos
  `ai-workflows`/`ai-helpers` rather than something skills-specific
- Internal Slack discussion with Amir Yogev (Flight Control / RHEM),
  2026-08 — real-world validation of the three-repo (code / AI workflows /
  design docs) separation, and the human-review-first protection stance
- `osac/.github/workflows/bump-submodules.yaml` — existing, working
  precedent for the poll/diff/open-a-PR *pattern* a new pin-bump bot for the
  skills repo would need to follow; note it bumps a reusable-workflow SHA
  string, not an actual `git submodule` (`osac` has none today), so the
  mechanism itself is new work, not reuse
- `osac/tools/bootstrap.sh` (`OSAC-3557`) — the existing standalone
  bootstrap this record proposes extending
- `osac/OWNERS`, `osac/fulfillment-service/OWNERS`, and siblings — existing,
  unenforced Prow-style `OWNERS` convention already used per-component
- GitHub API checks against `osac-project/osac` (2026-08-06): no
  `.github/CODEOWNERS`, no branch protection on `main`, and the only active
  ruleset (`ci-status-checks`) gates status checks only — confirming the
  `OWNERS` convention isn't currently a technically-enforced gate
- Workspace-wide search (2026-08-06): no vendored `ai-helpers` directory,
  clone, or tooling reference anywhere in this ecosystem — confirming
  OpenShift's `ai-helpers` is a naming-convention mention only, not an
  actual OSAC dependency the way `flightctl/ai-workflows` is
- GitHub search (2026-08-10): `lgtm-hq/ai-skills`, `PMelch/ai-skills`,
  `kevin-lee/ai-skills`, `anthropics/skills` — unrelated, actively
  maintained repos already using `ai-skills`/`skills` as a bare repo name
  for the same category of tool, grounding the case against dropping the
  `osac-` prefix
- `gh repo list osac-project` (2026-08-10) — confirms every live OSAC
  product/tooling repo in the org already carries the `osac-` prefix
- `git log --all --grep=marketplace` (2026-08-10) — commit `da0a6f95`
  ("feat: migrate plugin skills to repo-local skills/ directory",
  2026-04-30), the prior reversal away from Claude Code plugin
  marketplaces this record's Options Considered weighs against
  reintroducing
- `osac-workspace/bootstrap.sh` (2026-08-10 read) — confirms
  `flightctl/ai-workflows` is vendored via plain `git clone`/`git fetch`/
  `git rebase` into `.ai-workflows/`, not a plugin marketplace add
- Claude Code plugin marketplace docs, code.claude.com/docs/en/
  plugin-marketplaces (fetched 2026-08-10) — `CLAUDE_CODE_PLUGIN_SEED_DIR`
  for non-interactive/CI consumption; marketplace/plugin `name` fields are
  flat, manually-chosen, unscoped strings, not automatically tied to the
  underlying GitHub org/repo
- `anthropics/claude-code#33653` (checked 2026-08-10) — open feature
  request to extend commit-SHA pinning to relative-path plugins within a
  single marketplace repo, confirming that reproducibility gap is still
  unshipped upstream for this repo's actual shape
- PR review feedback from `eranco74` on this record (2026-08-10,
  `#194`) — flagged that a plain `git submodule` reference is only a
  pointer and leaves the directory empty on a default `git clone`/
  checkout, corrected in Decision item 3; also pointed to
  `opendatahub-io/skills-registry`, "lola," and Microsoft's APM as
  agent-skills tooling that can install from a marketplace "for all
  agents," which prompted the APM entry in Options Considered
- `opendatahub-io/skills-registry` README (checked 2026-08-10) — confirms
  it is a genuine Claude Code marketplace, but its own docs state Cursor,
  Gemini CLI, Codex, and OpenCode "do not have a marketplace aggregation
  mechanism" and require per-harness config files instead — corroborating
  rather than contradicting this record's claim that bare Claude
  marketplaces don't cover Cursor/Gemini
- Microsoft APM docs, microsoft.github.io/apm and github.com/microsoft/apm
  (fetched 2026-08-10) — cross-agent manifest/lockfile tool (`apm.yml`/
  `apm.lock.yaml`) deploying to Claude Code, Cursor, Gemini, Copilot, and
  others from one command; content-hash-pinned lockfile; deployed output
  described as committed into the consuming repo rather than left as a
  pointer; `apm install --frozen` for CI drift detection — basis for the
  APM entry in Options Considered
- `microsoft/apm`'s `LICENSE` file (checked 2026-08-10) — confirms MIT,
  ruling licensing in/out as a factor in whether a Red Hat project can
  adopt it; and `microsoft/apm` discussion #86, "APM moves to Microsoft OSS
  organization" (checked 2026-08-10) — confirms the repo moved from
  `danielmeppiel/apm` to the `microsoft/apm` org in February 2026 (project
  created September 2025), and is described as "community-driven" with
  support routed through GitHub Issues rather than Microsoft customer
  support — the maturity/governance data point behind this entry's
  Microsoft-vendor discussion
- Web search, "AI agent skill package manager" landscape (2026-08-10) —
  surfaced `pspm.dev`/`anyt-io/pspm-cli`, `spazyCZ/agent-package-manager`,
  `helincao/skilled`, `usescrolls/scribe`, `chrismdp/airskills`, and
  `EvanL1/aitoolsync`, all covering the same npm-for-many-skills-across-
  30-40+-harnesses ground as APM and all comparably young (roughly the
  last year) — basis for ruling out the whole category rather than
  treating APM as an outlier worth a dedicated follow-up
- Workspace-wide grep, including git history, for `Forge`, `fullsend`,
  `jira-autofix`, and `agentic-ci` (2026-08-10) — confirmed none of the
  four have any footprint in `osac-workspace` (no config, no vendored
  dependency, no docs) except `jira-autofix-merged`/`jira-autofix-rejected`
  Jira-label references in `evals/review/docs/measurement-taxonomy.md`,
  which map to OSAC's own bugfix-skill workflow, not a separate tool —
  basis for asking the framework-ownership question directly rather than
  guessing from repo evidence alone
- Direct confirmation from Tommy Hughes (OSAC, 2026-08-10) — OSAC controls
  configuration for Forge, fullsend, jira-autofix, and agentic-ci even
  where the underlying engine is shared (jira-autofix's engine understood
  to be part of Flight Control's tooling); basis for resolving the
  "does OSAC actually control..." Consequences bullet from an open
  follow-up to Resolved
- Live `registry.yaml` from `opendatahub-io/skills-registry` (fetched and
  grepped directly, 2026-08-10) — of ~20 externally-sourced entries, `sha:`
  appears 0 times and `ref:` appears 20 times; every entry that sets a
  skill location uses `skills_dir`, none anything equivalent for a
  commands directory — basis for the registry-catalog entry in Options
  Considered
- `osac-workspace/.ai-workflows/` (local vendored copy, inspected
  2026-08-10) — confirms no `.claude-plugin`/`plugin.json` anywhere in
  `flightctl/ai-workflows`; each workflow (e.g. `prd/`) splits into
  separate `skills/` and `commands/` directories; a sampled command
  wrapper (`prd/commands/ingest.md`) is a short, static, relative-path
  pointer file, not project-templated content
