# 0001. Dedicated AI Skills Repo, `osac/` as Primary Workspace, Phased `osac-workspace` Retirement

- **Status:** Proposed
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
  "Since YOLO does not work, the human is accountable for any content. You
  need to review the generated content and approve it. The above statement
  should cover the strategy and all the rest just becomes implementation
  details." They explicitly avoid `CODEOWNERS` at their team's current size
  (~15 people), but noted they'd likely answer differently at OSAC's scale.
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
   one consumer repo), skill-backing assets, and the ADRs that govern this
   space. This includes the skill-quality eval harness that already exists
   today (currently `osac-workspace/evals/`, grading `design-review`/
   `prd-review` skill output — not a hypothetical future addition), and any
   eval coverage added later for other skills follows it to the same repo,
   for the same reason: it only exists to grade skill output, so it has no
   independent reason to live anywhere else. Exact name and final content
   boundary are an open follow-up (see below); this record settles the
   *shape* of the decision, not the label on it.
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
3. **Automated frameworks consume the same vendored copy, pinned rather than
   floating** — e.g. a `git submodule` reference checked directly into
   `osac/` at a known SHA, so skills are already present the moment `osac/`
   is checked out, with no script execution required. This gives Forge/
   fullsend/jira-autofix/agentic-ci-style consumers a reproducible, reviewable
   dependency. **This is new automation to build, not a reuse of an existing
   one** — `osac` has no real `git submodule` anywhere today (confirmed: no
   `.gitmodules` file, no `160000` gitlink entries in the tree), and its
   existing `bump-submodules.yaml` bot bumps a SHA string embedded in
   workflow YAML for a GitHub Actions *reusable-workflow reference*
   (`osac-test-infra`), not a submodule checkout — a different mechanism
   that produces no local file tree, so it couldn't back a skill fan-out on
   its own. What *is* directly reusable is the pattern that bot already
   proves: poll upstream, diff a pinned SHA, open a real PR for human
   review. A new bump-bot for an actual `git submodule` pin needs to be
   built following that pattern, not assumed to already exist.
4. **`osac-workspace` keeps its current meta-repo role, unchanged, for a
   defined transition window.** It is not degraded or partially dismantled
   while `osac/`-based development is being proven out — in-flight work is
   not disrupted for this migration.
5. **Decommission `osac-workspace` once `osac/`-based development is proven
   fully equivalent**, against concrete exit criteria (see Consequences),
   not a calendar date alone.

## Naming Candidates (Not Yet Decided)

Not settling on a name here — the Slack thread that prompted this record
already agreed naming can wait until scope is clear — but worth laying out
the candidates side by side against the content-boundary question, since
the two decisions are coupled:

| Candidate | Fits if... | Risk |
|---|---|---|
| `osac-ai-skills` | Content stays skill files (+ light supporting docs) only | Undersells scope today, not just hypothetically: the skill-quality eval harness (`design-review`/`prd-review` grading) already exists and is proposed to travel here alongside the fan-out script, `.skillsaw.yaml`, and `decisions/` — an eval harness (fixtures, graded output, harness code) reads less like "a skill" than like infrastructure that happens to test skills, and would only grow as eval coverage expands to more skills over time. Note: the bootstrap/orchestration script itself is *not* part of this scope question — Decision item 2 keeps that in `osac/` regardless of what this repo is named |
| `osac-ai-workflows` | Content is broader — skills plus the tooling/process around them, mirroring `flightctl/ai-workflows`'s naming | **Name collision risk, not just style**: `flightctl/ai-workflows` is already vendored into this ecosystem today (`.ai-workflows/` is the actual local directory name after bootstrap runs) — a same-named OSAC repo would make "which `ai-workflows` do you mean" a real, recurring, concrete confusion, not a matter of degree |
| `osac-ai-helpers` | Same broad scope, mirrors OpenShift's `ai-helpers` naming | No real collision risk — checked directly, OSAC doesn't actually consume OpenShift's `ai-helpers` anywhere (no vendored directory, nothing cloned, nothing referenced in tooling), unlike `flightctl/ai-workflows`. It's purely a naming-convention echo of an unrelated project's tooling repo, not a functional relationship — OSAC provisioning OpenShift clusters is a product fact that has nothing to do with what OSAC names its own AI tooling repo |
| `osac-ai-tooling` | Broad scope, deliberately neutral/generic | No collision risk, no borrowed identity either way — but also no positive case beyond "safe" |

`osac-ai-workflows` is ruled out regardless of scope — that's a concrete
collision (an identical name already in active use in this ecosystem), not
a soft risk to weigh.

**Top choice: `osac-ai-tooling`.** It fits the broader content this repo is
expected to hold, and needs no borrowed story to justify it — it just
describes what's there. `osac-ai-helpers` is a fine alternative with a bit
more personality, but its resemblance to OpenShift's naming isn't backed by
any actual relationship between the two repos, so it shouldn't be read as
more than a coincidence. `osac-ai-skills` only wins back out if the group
draws the content boundary narrower than this record proposes — e.g., the
eval harness gets its own repo instead of riding along
with skills. Decide the content boundary first; let that pick the name.

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

## Consequences

- Solves both concrete touch points (developer ergonomics, automated
  framework consumption) without requiring `osac-workspace` to disappear on
  day one.
- Matches a real, working pattern already proven by a peer AI SDLC framework
  OSAC itself depends on, rather than a purely internal guess.
- **Open follow-up — naming and exact content boundary.** A name like
  `osac-ai-skills` was floated informally, but whether that fits depends on
  what actually lands in the repo. If it's skill markdown files only, a
  narrow name fits. If it also carries the generic fan-out script, `.skillsaw.yaml`
  linting, the existing skill-quality eval harness, and this `decisions/`
  directory (as proposed above) — bootstrap/orchestration logic is out of
  scope for this question, since Decision item 2 keeps that in `osac/`
  regardless — a broader name fits better. See Naming Candidates for
  specifics, including which risk (`osac-ai-workflows`'s) is a hard fact
  versus which (`osac-ai-helpers`' vs. `osac-ai-tooling`'s) is closer to a
  toss-up. Resolve naming after the content boundary is final, not before.
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
  component.
- **Open follow-up — protection strategy for the new skills repo.** Baseline
  is mandatory human review/approval of any change, same as everywhere else
  — per Flight Control's stance, that's the real strategy, and the rest is
  implementation detail. OSAC already has a per-component `OWNERS` file
  convention (Prow-style `approvers`/`reviewers` YAML — `osac/OWNERS`,
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
- **Open follow-up — does OSAC actually control how these frameworks
  consume skills?** Decision item 3 assumes `osac` can dictate a pinned
  `git submodule` as the consumption mechanism for Forge/fullsend/
  jira-autofix/agentic-ci. If any of these are centrally-managed tooling
  shared across teams (plausible, given Flight Control's own `ai-workflows`
  is itself centrally-provided rather than OSAC-authored), that's a
  coordination dependency with each framework's owners, not something OSAC
  can unilaterally decide. Not confirmed either way by this record.

## Non-Goals

- Does not finalize the new repo's name — deliberately deferred until its
  content boundary is settled.
- Does not commit to a specific decommission date for `osac-workspace` —
  ties it to exit criteria instead.
- Does not change anything about `enhancement-proposals` staying a separate
  *repo* from `osac` — Flight Control's answer on spec/design-doc placement
  reaffirms that direction. `osac/`'s bootstrap cloning it as a sibling
  (Decision item 2) is a dev-ergonomics change, not a merge — it stays a
  fully independent repo with its own history, ownership, and lifecycle,
  the same relationship it already has with `osac-workspace` today.
- Does not specify the exact migration tooling (`git filter-repo`, `git
  subtree`, or similar) for moving `skills/` and its supporting directories
  into the new repo — an implementation detail for whoever executes this.

## References

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
