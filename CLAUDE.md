# CLAUDE.md

## Project Context

OSAC (Open Sovereign AI Cloud) is a fulfillment system for provisioning Kubernetes clusters and compute instances with networking capabilities. Primary languages: Go, YAML, Python. Primary tools: kubectl, jira CLI, gh CLI.

## Critical Rules

- **`osac-workspace/` is the project root** — all work happens from here; component `CLAUDE.md` files are loaded via progressive disclosure
- **Read component CLAUDE.md first** before making changes in any component repo
- **Never skip tenant isolation metadata** (`osac.openshift.io/tenant`, `osac.openshift.io/owner-reference` annotations) in new resources
- **Always `buf lint` before committing** proto changes; regenerate with `buf generate`
- **Fork-based workflow**: always push to `fork` remote, never to `origin`. PRs go from `fork/<branch>` to `origin/main`
- **AI attribution**: use `Assisted-by: Claude Code <noreply@anthropic.com>` trailer on commits — never use `Co-Authored-By` for AI tools (Red Hat attribution standard)
- When debugging Kubernetes operators, check for stale vendor directories and cached images before rebuilding

## Repository Structure

Meta-workspace — run `./bootstrap.sh` to clone/update all component repos to latest `main`.

| Component | Description | CLAUDE.md |
|-----------|-------------|-----------|
| [`fulfillment-service`](https://github.com/osac-project/fulfillment-service) | gRPC server + REST gateway, PostgreSQL, integrated API definitions | Yes |
| [`osac-operator`](https://github.com/osac-project/osac-operator) | Kubernetes operator for OpenShift clusters via Hosted Control Planes | Yes |
| [`osac-aap`](https://github.com/osac-project/osac-aap) | Ansible Automation Platform roles for network provisioning | Yes |
| [`osac-installer`](https://github.com/osac-project/osac-installer) | Installation manifests and prerequisites | — |
| [`osac-test-infra`](https://github.com/osac-project/osac-test-infra) | Integration testing infrastructure | — |
| [`osac-ui`](https://github.com/osac-project/osac-ui) | OSAC UI web console | — |
| [`enhancement-proposals`](https://github.com/osac-project/enhancement-proposals) | Design documents and RFCs | — |
| [`docs`](https://github.com/osac-project/docs) | Architecture docs and guides (see `docs/architecture/`) | — |
| [`host-management-openstack`](https://github.com/osac-project/host-management-openstack) | Bare metal host management via OpenStack | — |
| [`bare-metal-fulfillment-operator`](https://github.com/osac-project/bare-metal-fulfillment-operator) | Kubernetes operator for bare metal fulfillment | — |

Note: `fulfillment-api` and `fulfillment-common` were merged into `fulfillment-service`.

## Deployment Coordination

`osac-installer/setup.sh` pins component versions (AAP collections, fulfillment-service images) via submodule refs. When making changes that cross component boundaries, always update `osac-installer` to match:

- **Proto field additions** in `fulfillment-service` → update CI overlays in `osac-installer` to use the new image version
- **New AAP roles or collections** in `osac-aap` → bump the submodule ref in `osac-installer`
- **New CRD types** in `osac-operator` → register in the fulfillment-service reconciler

Failing to update `osac-installer` after cross-component changes causes CI failures and deployment mismatches. See `.planning/codebase/CONVENTIONS.md` for the full cross-repo dependency table.

## Common Fix Locations

Use this table to go directly to the right file for common bug patterns instead of grepping from scratch:

| Bug pattern | File(s) to check |
|-------------|-----------------|
| `unknown object type` or unhandled type in switch | `internal/servers/generic_server.go` — `setPayload()` switch statement |
| Public API missing field (Create/Update not persisting a field) | `internal/servers/*_server.go` — `Create()` and `Update()` methods |
| Table rendering missing or incorrect column | `internal/rendering/tables/*.yaml` — table definition files |

## PRD and Design Configuration

OSAC uses the flightctl ai-workflows PRD and design skills with project-level template overrides in `.design/templates/`. The two-stage flow replaces the single-step `/ep-create` for new enhancement proposals.

### Docs Repo

- Both PRD and design workflows publish to the `enhancement-proposals` repo
- Local path: `./enhancement-proposals/`
- When the publish phase asks for the docs repo, provide this path

### File Path Conventions

When publishing PRDs and design documents to the enhancement-proposals repo:
- Skip the "release" question — use `enhancements` as the fixed directory prefix
- Feature directory: `enhancements/<feature-slug>/` (e.g., `enhancements/storage-network/`)
- PRD filename: `prd.md`
- Design (EP) filename: `README.md` (not `design.md` — this is the main EP file)
- Both files live in the same directory: `enhancements/<slug>/prd.md` and `enhancements/<slug>/README.md`

### Fork-Based Workflow

Push to the `fork` remote in the enhancement-proposals repo, not `origin`. PRs go from `fork/<branch>` to `origin/main`.

### Feature Dimensions Context

Both `/prd:ingest` and `/design:ingest` must read all files in `.design/context/` during their ingest phase:

- **`osac-dimensions.md`** — Cross-cutting dimensions (services, personas, tenant onboarding, inventory, provisioning, networking, storage, installation, E2E testing, documentation, UI) that every OSAC feature must address. Use it to guide clarifying questions during `/prd:clarify` and persona/user-story scope during `/prd:draft` (see § Personas and `osac-docs/personas.md`); ensure the design covers all relevant dimensions.
- **`review-patterns.md`** — Common EP reviewer feedback themes, anti-patterns, and the EP reference library. Use during `/prd:draft` and `/design:draft` to anticipate reviewer expectations.

### Template Overrides

- Design template: `.design/templates/design.md` (EP format with PRD-aware modifications)
- Design section guidance: `.design/templates/section-guidance.md`
- PRD template: uses the flightctl default (no override)

## Quick Reference Commands

```bash
# fulfillment-service
cd fulfillment-service
go build                              # Build
ginkgo run -r internal                # Unit tests (excludes integration)
ginkgo run it                         # Integration tests (requires kind)
IT_KEEP_KIND=true ginkgo run it       # Preserve kind cluster for debugging
buf lint && buf generate              # Proto lint + codegen

# osac-operator
cd osac-operator
make image-build image-push IMG=<registry>/osac-operator:tag
make install                          # Install CRDs
make deploy IMG=<registry>/osac-operator:tag
```

## Operator Architecture (osac-operator)

The osac-operator uses controller-runtime to reconcile OSAC custom resources on Kubernetes. Key patterns:

- **All controllers follow the same reconciliation pattern**: finalizer → status update → provisioning/deprovisioning lifecycle
- **Shared provisioning lifecycle**: Controllers use `provisioning.RunProvisioningLifecycle()` for provision and manual deprovision handling
- **CRD types**: ClusterOrder, ComputeInstance, Tenant, VirtualNetwork, Subnet, SecurityGroup, PublicIPPool, PublicIP
- **Multi-cluster support**: Controllers use `multicluster-runtime` for management/workload cluster separation
- **Management-state annotation**: All controllers should check `osac.openshift.io/management-state` and skip reconciliation when set to `Unmanaged`
- **Namespace isolation**: Networking controllers filter to a configured namespace via `NetworkingNamespacePredicate`

When fixing bugs or adding features, **check all controllers** that follow the same pattern — a bug in one controller likely exists in others. A missing feature in one controller is also a bug if all controllers are expected to behave consistently.

## Detailed Rules (auto-loaded from `.claude/rules/`)

- **`protobuf-conventions.md`** — Proto naming, API structure, field guidelines, type/service patterns
- **`cross-repo-workflow.md`** — Git worktrees, cross-component changes, PR rules
- **`architecture-patterns.md`** — Multi-tenancy, resource hierarchy, service stack, integration testing
## Reference Documentation

| Location | Content |
|----------|---------|
| `.planning/codebase/ARCHITECTURE.md` | System design and layers |
| `.planning/codebase/CONVENTIONS.md` | Naming and coding patterns |
| `.planning/codebase/STACK.md` | Technology stack |
| `.planning/codebase/TESTING.md` | Test patterns and frameworks |
| `.planning/codebase/STRUCTURE.md` | File organization |
| [`docs/architecture/`](https://github.com/osac-project/docs/tree/main/architecture) | High-level diagrams and design documents |
| [`enhancement-proposals/`](https://github.com/osac-project/enhancement-proposals) | RFCs and design proposals |

## AI-Assisted Development Workflow

See [`AI-assisted-development-workflow.md`](AI-assisted-development-workflow.md) for the full workflow: Feature → PRD → Design → Jira sync → Implement.

## E2E Test Skills

Two complementary skills for E2E tests, available from the `osac-workspace/` root:

- `/e2e` (ai-workflows) — Full story-to-test workflow: `/e2e:ingest` a Jira [QE] story → `/e2e:plan` scenarios → `/e2e:code` tests → `/e2e:validate` → `/e2e:publish` PR. Framework-agnostic — discovers osac-test-infra's pytest patterns during ingest.
- `/debug-e2e` (osac-test-infra) — Debug a failing Prow CI job using build logs and gathered OSAC artifacts. Use after tests exist and fail in CI.

The `/e2e` workflow writes tests in `osac-test-infra/tests/` following the conventions in `osac-test-infra/.claude/skills/e2e.md` (gRPC client patterns, K8s client patterns, wait helpers, pytest fixtures). The `/debug-e2e` skill reads Prow logs and OSAC gathered artifacts to diagnose failures.

## Development Notes

- OSAC uses Jira **Tasks** (not Stories) — the implement workflow's "story" references mean Tasks in this project
- Use `jira` CLI for Jira access (e.g., `jira issue view OSAC-1234 --plain`), not Jira MCP
- AI workflow skills are installed via `bootstrap.sh` from [flightctl/ai-workflows](https://github.com/flightctl/ai-workflows)

## OpenShift Deployment

```bash
kubectl annotate ingresses.config/cluster ingress.operator.openshift.io/default-enable-http2=true
kubectl apply -k fulfillment-service/manifests
export token=$(kubectl create token -n osac client)
export route=$(kubectl get route -n osac fulfillment-api -o json | jq -r '.spec.host')
grpcurl -insecure -H "Authorization: Bearer ${token}" ${route}:443 fulfillment.v1.VirtualNetworks/List
```
