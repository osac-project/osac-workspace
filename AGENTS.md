# OSAC Workspace

Meta-workspace that bootstraps all OSAC (Open Sovereign AI Cloud) component repos for cross-component development, testing, and AI-assisted workflows. OSAC is a fulfillment system for provisioning Kubernetes clusters and compute instances with networking capabilities. Primary languages: Go, YAML, Python. Primary tools: kubectl, jira CLI, gh CLI.

## Critical Rules

- **Workspace architecture decisions** (topology, skill distribution, repo boundaries) are recorded in [`decisions/`](decisions/) — read before proposing changes to how `osac-workspace` itself is structured
- **`osac-workspace/` is the project root** — all work happens from here; component docs are loaded via progressive disclosure
- **Never skip tenant isolation metadata** (`osac.openshift.io/tenant`, `osac.openshift.io/owner-reference` annotations) in new resources
- **Always `buf lint` before committing** proto changes; regenerate with `buf generate`
- **Fork-based workflow**: push to `$PUSH_REMOTE`, never to `$UPSTREAM_REMOTE` — resolve with `tools/resolve-remotes.sh`
- **AI attribution**: use an `Assisted-by: <tool> <contact>` trailer on commits, naming whichever AI tool actually did the work — never use `Co-Authored-By` for AI tools (Red Hat attribution standard). Example for Claude Code: `Assisted-by: Claude Code <noreply@anthropic.com>`
- When debugging Kubernetes operators, check for stale vendor directories and cached images before rebuilding
- **Don't raise `.skillsaw.yaml`'s `context-budget` skill limit to silence a token-count warning** — split the oversized `SKILL.md` into `references/`/`steps/` instead (see Skill Authoring Conventions)
- **Bump `metadata.version` in any `skills/*/SKILL.md` you modify** — the `check-skill-version-bump` CI job fails if a skill's content changes without a version bump. Use semver patch increments (e.g. `0.1.0` → `0.1.1`) for fixes and improvements, minor increments (`0.1.0` → `0.2.0`) for new capabilities.

## Dev Environment

### Option A: Distrobox (recommended)

All dev tools are packaged in a Fedora 42 container (`Containerfile`). Requires `podman` and `distrobox`.

```bash
make enter                     # Build image and enter distrobox
make status                    # Check image and distrobox status
make rebuild                   # Rebuild image from scratch
```

### Option B: Local toolchain

Install Go, Node.js, buf, kubectl, kind, jira CLI, gh CLI, jq directly.

### Bootstrap

```bash
./bootstrap.sh                 # Clone all repos with fork setup (requires gh CLI)
./bootstrap.sh --no-fork       # Clone read-only without forking
```

Re-run `./bootstrap.sh` anytime to update all repos to latest `main`.

## Repository Structure

Meta-workspace — run `./bootstrap.sh` to clone/update all component repos to latest `main`. **In component repos, read `CLAUDE.md` first** (progressive disclosure). Use that component's `AGENTS.md` where the table below shows **Yes** for tool-agnostic build/test conventions.

Note: `fulfillment-api` and `fulfillment-common` were merged into `fulfillment-service`, which was then merged with `osac-operator`, `osac-aap`, `osac-installer`, `bare-metal-fulfillment-operator`, and `osac-csi-driver` into the `osac` mono-repo below.

| Component | Description | AGENTS.md |
|-----------|-------------|-----------|
| [`osac`](https://github.com/osac-project/osac) | Mono-repo: `fulfillment-service` + `osac-operator` + `osac-aap` + `osac-installer` + `bare-metal-fulfillment-operator` + `osac-csi-driver` + `osac-metering` (see subdirectories below) | — |
| `osac/fulfillment-service` | gRPC server + REST gateway, PostgreSQL, integrated API definitions | Yes |
| `osac/osac-operator` | Kubernetes operator for OpenShift clusters via Hosted Control Planes | Yes |
| `osac/osac-aap` | Ansible Automation Platform roles for infrastructure provisioning | Yes |
| `osac/osac-installer` | Helm charts and installation prerequisites | Yes |
| `osac/bare-metal-fulfillment-operator` | Kubernetes operator for bare metal fulfillment | Yes |
| `osac/osac-csi-driver` | CSI storage driver, routes to vendor backends via fulfillment-service storage tiers | Yes |
| `osac/osac-metering` | Metering pipeline for resource usage events and Kafka publishing | Yes |
| [`osac-test-infra`](https://github.com/osac-project/osac-test-infra) | Integration testing infrastructure | — |
| [`osac-ui`](https://github.com/osac-project/osac-ui) | OSAC UI web console | Yes |
| [`osac-ux`](https://github.com/osac-project/osac-ux) | React 19 + PatternFly 6 UI console — read-only UI reference | Yes (`osac-ux/AGENTS.md`) |
| [`enhancement-proposals`](https://github.com/osac-project/enhancement-proposals) | Design documents and RFCs | — |
| [`docs`](https://github.com/osac-project/docs) | Architecture docs and guides (see `osac-docs/architecture/`) | — |

## Build and Test

This workspace has no build step of its own. Each component repo documents build and test commands in its `AGENTS.md` or `CLAUDE.md`.

| Component                               | Build        | Unit Tests               | Lint                  |
|------------------------------------------|--------------|--------------------------|-----------------------|
| `osac/fulfillment-service/`             | `go build ./...` | `ginkgo run -r internal` | `uv run dev.py lint`  |
| `osac/osac-operator/`                   | `make build` | `make test`              | `make lint`           |
| `osac/osac-aap/`                        | —            | `make test`              | `uv run ansible-lint` |
| `osac/osac-installer/`                  | —            | —                        | `make helm-lint`      |
| `osac/bare-metal-fulfillment-operator/` | `make build` | `make test`              | `make lint`           |
| `osac/osac-csi-driver/`                 | `make build` | `make test`              | `make lint`           |
| `osac/osac-metering/`                   | —            | —                        | —                     |
| `osac-test-infra/`                      | —            | —                        | `make lint`           |
| `osac-ui/`                              | `pnpm build` | `pnpm test`              | `pnpm lint`            |

`osac/osac-installer/`'s `make helm-lint` fails unconditionally as shipped — `charts/osac/`'s values schema requires non-empty `service.externalHostname`/`internalHostname`, which every real values file leaves blank for runtime injection. See `skills/create-pr/SKILL.md`'s `osac-installer` validation block for the `--set` overrides needed to actually run it.

### Quick Reference

```bash
# osac/fulfillment-service
cd osac/fulfillment-service
go build ./...                        # Build
ginkgo run -r internal                # Unit tests (excludes integration)
ginkgo run it                         # Integration tests (requires kind)
IT_KEEP_KIND=true ginkgo run it       # Preserve kind cluster for debugging
buf lint && buf generate              # Proto lint + codegen

# osac/osac-operator
cd osac/osac-operator
make image-build image-push IMG=<registry>/osac-operator:tag
make install                          # Install CRDs
make deploy IMG=<registry>/osac-operator:tag
```

## Code Style

### Git Workflow

- **Fork-based**: push to `$PUSH_REMOTE`, never to `$UPSTREAM_REMOTE`
- **Branch naming**: `<type>/<ticket-or-description>` (e.g., `feat/OSAC-23607`, `fix/duplicate-aap-jobs`)
- **Resolve remotes**: `eval $(tools/resolve-remotes.sh <component-path>)` sets `$UPSTREAM_REMOTE` and `$PUSH_REMOTE` (handles both bootstrap and manual remote naming)
- **DCO sign-off**: `git commit -s` on all commits
- **AI attribution**: `Assisted-by: <tool> <contact>` trailer, naming whichever AI tool actually did the work — never `Co-Authored-By` for AI tools. Example for Claude Code: `Assisted-by: Claude Code <noreply@anthropic.com>`

### Cross-Component Changes

`fulfillment-service`, `osac-operator`, `osac-aap`, `osac-installer`,
`bare-metal-fulfillment-operator`, and `osac-csi-driver` all live in one
mono-repo (`osac/`) — a feature spanning any of them (proto definitions,
CRD types, Ansible roles/playbooks, Helm values) lands in a single branch
and PR there.

Link PRs in descriptions: "Depends on osac-project/osac#123".

## Deployment Coordination

`osac-installer`'s `scripts/sync-image-tags.sh` was removed upstream
(`OSAC-3367`) — there is no image-tag pinning/syncing step left at all.
`fulfillment-service`, `osac-operator`, `osac-aap`, `bare-metal-fulfillment-operator`,
and `osac-csi-driver` are all mono-repo-resident: `values/*/values.yaml` leaves their
image tags unpinned (`latest`), and real release tags are set automatically by `osac`'s
own CI (`publish-osac-installer-chart.yaml` and each component's tag-triggered image
workflow) at release time — not by a feature PR. What still needs an explicit update:

- **New CRD types** in `osac-operator` → register in the `fulfillment-service` reconciler (an in-repo change, same PR)
- **`osac-ui`** → a real external dependency (OCI chart + image, version-tagged), bumped deliberately when a new release is needed

See `reference/CONVENTIONS.md` for the full dependency table (regenerated via the repo-intel tooling, not hand-edited).

## Enhancement Proposals

OSAC uses the flightctl ai-workflows PRD and design skills with project-level template overrides. The two-stage flow produces a PRD followed by a design document.

### Docs Repo

- Both PRD and design workflows publish to the `enhancement-proposals` repo
- Local path: `./enhancement-proposals/` — give this path when `/publish` asks for the docs repo

### File Path Conventions

When publishing PRDs and design documents to the enhancement-proposals repo:

- Skip the "release" question — use `enhancements` as the fixed directory prefix
- Feature directory: `enhancements/<jira-key>-<feature-slug>/`, where `<jira-key>` is the Jira **Feature**-level key exactly as it appears in Jira (no zero-padding), placed first in the directory name (e.g., `enhancements/OSAC-42-example-feature/`)
- PRD filename: `prd.md`
- Design (EP) filename: `design.md`
- Both files live in the same directory: `enhancements/<jira-key>-<feature-slug>/prd.md` and `enhancements/<jira-key>-<feature-slug>/design.md`

### Fork-Based Workflow

Resolve remotes with `tools/resolve-remotes.sh`. Push to `$PUSH_REMOTE`, never to `$UPSTREAM_REMOTE`.

### Feature Dimensions Context

Both PRD and design ingest phases must read all files in `.design/context/`:

- **`osac-dimensions.md`** — Cross-cutting dimensions (services, personas, tenant onboarding, inventory, provisioning, networking, storage, installation, E2E testing, documentation, UI) that OSAC features should address where relevant — see `osac-dimensions.md`'s own triage rule for which dimensions apply to a given feature. Use it to guide clarifying questions during PRD clarify and persona/user-story scope during PRD draft (see Personas and `osac-docs/personas.md`); ensure the design covers the dimensions that actually apply.
- **`review-patterns.md`** — Common design reviewer feedback themes, anti-patterns, and the design reference library. Use during PRD draft and design draft to anticipate reviewer expectations.

### Component Conventions

Design and implement ingest phases must read the `AGENTS.md` of each component repo affected by the feature — authoritative on API design, database patterns, testing, and build tooling; the generic workspace rules summarize but don't replace them.

For features involving the fulfillment-service API (proto definitions, services, request/response patterns), `osac/fulfillment-service/AGENTS.md` points to [`osac/fulfillment-service/docs/API.md`](osac/fulfillment-service/docs/API.md) — the canonical API design guidelines. Read it before drafting or reviewing proto schemas.

### Template Overrides

- Design template: `enhancement-proposals/guidelines/design_template.md` (EP format with PRD-aware modifications)
- Design section guidance: `.design/templates/section-guidance.md` — stays local; hand-synced with `design_template.md`
- PRD template: `enhancement-proposals/guidelines/prd_template.md` (user stories by persona, In Scope/Out of Scope instead of FR-N/NFR-N)

## Jira Conventions

- OSAC uses Jira **Tasks** (not Stories) for implementation work — in the **implement** workflow, "story" references mean Tasks in this project
- Use `jira` CLI for Jira access (e.g., `jira issue view OSAC-1234 --plain`), not Jira MCP

## AI-Assisted Workflows

See [`AI-assisted-development-workflow.md`](AI-assisted-development-workflow.md) for the full workflow: Feature → PRD → Design → Jira sync → Implement.

Installed via `bootstrap.sh` from [flightctl/ai-workflows](https://github.com/flightctl/ai-workflows). Available in Claude Code, Cursor, and other AI tools (command syntax varies by tool).

### Development Workflows

- **bugfix** — Systematic bug fix: assess → reproduce → diagnose → fix → test → review → document → pr
- **implement** — Task-to-code: ingest Jira task → plan → code (TDD) → validate → publish PR

Both workflows are phase-based — you can jump to any phase directly (e.g., `bugfix:fix`, `implement:code`).

### PRD and Design Workflows

Two-stage enhancement proposal flow. See the Enhancement Proposals section above for docs repo, file path conventions, and templates.

**Stage 1 — PRD:** ingest → clarify → draft → publish → respond

**Stage 2 — Design (EP):** ingest → research → draft → publish → respond → decompose → sync

**Single-step (legacy):** `/ep.create` (registered legacy skill name; see `CLAUDE.md` for Claude command syntax)

### E2E Test Workflows

Two complementary skills for E2E tests, available from the `osac-workspace/` root:

- **e2e** (ai-workflows) — Full story-to-test workflow: `/e2e:ingest` a Jira [QE] story → `/e2e:plan` scenarios → `/e2e:code` tests → `/e2e:validate` → `/e2e:publish` PR. Framework-agnostic — discovers osac-test-infra's pytest patterns during ingest.
- **debug-e2e** (osac-test-infra) — Debug a failing Prow CI job using build logs and gathered OSAC artifacts. Use after tests exist and fail in CI.

The `/e2e` workflow writes tests in `osac-test-infra/tests/` following the conventions in `osac-test-infra/.claude/skills/e2e.md` (gRPC client patterns, K8s client patterns, wait helpers, pytest fixtures). The `/debug-e2e` skill reads Prow logs and OSAC gathered artifacts to diagnose failures.

### Skill discovery

Canonical skill definitions live in `skills/` (committed OSAC skills plus bootstrap-managed ai-workflows symlinks). Run `./bootstrap.sh` to wire skill discovery for each agent:

| Agent | Skill path | Phase commands |
|-------|------------|----------------|
| Claude Code | `.claude/skills/` → `skills/` | `.claude/commands/` (ai-workflows) |
| Cursor | `.cursor/skills/` → `skills/` | `.cursor/commands/` (ai-workflows) |
| Gemini CLI | `.gemini/skills/` → `skills/` | — |
| GitHub Copilot | `AGENTS.md` conventions only | — |

`.claude/`, `.cursor/`, and `.gemini/` are gitignored except project settings; bootstrap recreates agent skill symlinks via `tools/link-agent-skills.sh`.

`osac` also has its own root `AGENTS.md`/`tools/bootstrap.sh` upstream (`OSAC-3557`), which
installs the same ai-workflows skills for someone cloning `osac` standalone, outside this
workspace. **Don't run `osac/tools/bootstrap.sh` from within `osac-workspace`** — this
workspace's own `./bootstrap.sh` and skill-linking above already cover `osac/` as a
component; running both would install two separate, out-of-sync `.ai-workflows` clones.

### Skillsaw Linting

**Skillsaw linting** (version pinned in `Makefile` `SKILLSAW_VERSION`; scope is `skillsaw lint .` with blacklist via `.skillsaw.yaml` `exclude:`; strict lint only — no baseline file, see `.gitignore`):

- `make skillsaw` — lint full repo (on-demand; applies `SKILLSAW_VERSION`, `--strict`, `--no-baseline`)
- `make skillsaw SKILL=skills/<name>/` — lint one skill (same pin and flags; no bare `skillsaw` on PATH)
- Keep `Makefile`'s `SKILLSAW_VERSION` and `.github/workflows/skillsaw.yml`'s `version:` input in sync when bumping.
- **CI** — `stbenjam/skillsaw` action on PRs (same `.skillsaw.yaml`; fixed command, not `Makefile`); `skillsaw-review` workflow posts inline PR comments from the lint report (no PR code execution in the review job)

Skillsaw enforces [Agent Skills](https://agentskills.io/specification) structure (frontmatter, naming) and content quality heuristics. **Do not rewrite skill semantics just to pass lint** — tune `.skillsaw.yaml` for false positives or fix with backticks (see below).

### Skill Authoring Conventions

OSAC skills are workspace operators, not isolated skill bundles:

- **Context budget:** Keep `SKILL.md` body under **5,000 tokens** ([Agent Skills spec](https://agentskills.io/specification) Tier 2). Move reference material to `references/` or `steps/` and link from `SKILL.md` with explicit **read before** callouts at each workflow step.

| Reference type | Format | Example |
|----------------|--------|---------|
| File inside the skill directory | Markdown link ([Agent Skills spec](https://agentskills.io/specification)) | `[preflight.md](steps/preflight.md)` |
| Path at workspace repo root | Backtick path, not a markdown link | `` `presentations/themes/redhat.css` `` |
| Component or external doc | Backtick path or full URL | `` `osac/fulfillment-service/docs/API.md` `` |
| User-input markers in examples | Backtick the marker | `` `TODO:` `` in meeting notes (not bare `TODO` in headings) |
| Bad examples in calibration text | Backtick the quoted phrase | `` `handle edge cases appropriately` `` |

Put `CRITICAL` / `IMPORTANT` rules in the first 20% of `SKILL.md` (skillsaw `content-critical-position`). When stating a prohibition, include the required alternative (for example: do Y instead of X). When lint forces a trade-off between passing and preserving operational guidance, preserve the guidance and adjust config or formatting.

## Architecture

```text
osac/                              Mono-repo: fulfillment-service + osac-operator + osac-aap + osac-installer + bare-metal-fulfillment-operator + osac-csi-driver
  fulfillment-service              gRPC/REST API server, PostgreSQL, resource lifecycle
  osac-operator                    Kubernetes operator, provisions via AAP + Hosted Control Planes
  osac-aap                         Ansible playbooks for infrastructure provisioning
  osac-installer                   Helm charts, deploys all components to OpenShift
  bare-metal-fulfillment-operator  Kubernetes operator for bare metal fulfillment
  osac-csi-driver                  CSI storage driver, routes to vendor backends via storage tiers
osac-test-infra                    E2E test playbooks against fulfillment-service gRPC API
osac-ui                            Web console (React, PatternFly 6, pnpm workspace)
enhancement-proposals              Design documents and RFCs
osac-docs                          Architecture docs and guides
```

### Resource Hierarchy

```text
Tenant → namespace and network isolation
ClusterOrder → OpenShift clusters via Hosted Control Planes
VirtualNetwork → L2 network with CIDR (child of NetworkClass)
  ├── Subnet → CIDR range within VirtualNetwork
  └── SecurityGroup → firewall rules
ComputeInstance → KubeVirt VM, attached to Subnets + SecurityGroups
NatGateway → child of VirtualNetwork, SNATs egress traffic through an ExternalIP
ExternalIPPool → external IP address ranges
  ├── ExternalIP → allocated from pool
  └── ExternalIPAttachment → binds ExternalIP to ComputeInstance
```

### Operator Architecture (osac-operator)

The osac-operator uses controller-runtime to reconcile OSAC custom resources on Kubernetes. Key patterns:

- **All controllers follow the same reconciliation pattern**: finalizer → status update → provisioning/deprovisioning lifecycle
- **Shared provisioning lifecycle**: Controllers use `provisioning.RunProvisioningLifecycle()` for provision and manual deprovision handling
- **CRD types**: ClusterOrder, ComputeInstance, ExternalIP, ExternalIPAttachment, ExternalIPPool, NatGateway, SecurityGroup, Subnet, Tenant, VirtualNetwork
- **Multi-cluster support**: Controllers use `multicluster-runtime` for management/workload cluster separation
- **Management-state annotation**: All controllers should check `osac.openshift.io/management-state` and skip reconciliation when set to `Unmanaged`
- **Namespace isolation**: Networking controllers filter to a configured namespace via `NetworkingNamespacePredicate`

When fixing bugs or adding features, **check all controllers** that follow the same pattern — a bug in one controller likely exists in others. A missing feature in one controller is also a bug if all controllers are expected to behave consistently.

## UI Reference (osac-ux)

`osac-ux/` is cloned read-only from [osac-project/osac-ux](https://github.com/osac-project/osac-ux).
No PRs are created against it from backend workflow sessions (no push remote configured).

### What to read during /design:research and /implement:ingest

| Path | Purpose |
|------|---------|
| `osac-ux/libs/ui-components/src/pages/tenant/` | Tenant screens — form fields, list columns, actions |
| `osac-ux/libs/ui-components/src/pages/provider/` | Provider admin screens |
| `osac-ux/libs/ui-components/src/pages/admin/` | Tenant admin screens |
| `osac-ux/libs/ui-components/src/api/v1/` | @temp-api types — use as primary proto field input |
| `osac-ux/apps/e2e/cypress/e2e/flows/` | User journeys for Cypress scenario planning |

### @temp-api types are primary proto input

For **any EP** (new resource or existing resource enhancement), check whether
a matching `@temp-api` file exists at `osac-ux/libs/ui-components/src/api/v1/<resource>.ts`.
If it does, read it and use the TypeScript fields as the source for proto field names
(converting camelCase → snake_case). The EP must include a `## UX Alignment` section
with a field-by-field mapping table and a justification for any deviation.

For existing resources, the @temp-api file may contain fields the UI needs but the
backend has not yet returned — these are real requirements, not speculation.

### API coverage audit

Run `cd osac-ux && node scripts/gen-api-diff.mjs` to surface API gaps against the current UI.

## Common Fix Locations (osac/fulfillment-service)

| Bug pattern | File(s) to check |
|-------------|-----------------|
| `unknown object type` or unhandled type in switch | `internal/servers/generic_server.go` — `setPayload()` switch statement |
| Public API missing field (Create/Update not persisting a field) | `internal/servers/*_server.go` — `Create()` and `Update()` methods |
| Table rendering missing or incorrect column | `internal/rendering/tables/*.yaml` — table definition files |

## OpenShift Deployment

The Kustomize `manifests/` directory was removed from `fulfillment-service` — Helm is
now the only supported deployment method, and installation requires cert-manager, a
PostgreSQL operator, and Keycloak to be set up first. See
[`osac/fulfillment-service/docs/INSTALL.md`](osac/fulfillment-service/docs/INSTALL.md)
for the full OpenShift installation guide (that guide's first step is enabling HTTP/2,
shown below).

```bash
oc annotate ingresses.config.openshift.io cluster ingress.operator.openshift.io/default-enable-http2=true
```

Once deployed, verify with the `osac` CLI (see INSTALL.md's "Verify the installation" for the full
sequence, including extracting the CA bundle):

```bash
osac login --ca-file bundle.pem --flow credentials --client-id osac-admin \
  --client-secret "${OSAC_ADMIN_CLIENT_SECRET}" --private \
  https://fulfillment-internal-api-osac.${DOMAIN}
osac get clusters
```
