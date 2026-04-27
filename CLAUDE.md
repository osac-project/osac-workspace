# CLAUDE.md

## Project Context

OSAC (Open Sovereign AI Cloud) is a fulfillment system for provisioning Kubernetes clusters and compute instances with networking capabilities. Primary languages: Go, YAML, Python. Primary tools: kubectl, jira CLI, gh CLI.

## Critical Rules

- **Read component CLAUDE.md first** before making changes in any component repo
- **Never skip tenant isolation metadata** (`osac.openshift.io/tenant`, `osac.io/owner-reference` annotations) in new resources
- **Always `buf lint` before committing** proto changes; regenerate with `buf generate`
- **PRs target `origin` remote** unless explicitly told otherwise
- When debugging Kubernetes operators, check for stale vendor directories and cached images before rebuilding

## Repository Structure

Meta-workspace — run `./bootstrap.sh` to clone/update all component repos to latest `main`.

| Component | Description | CLAUDE.md |
|-----------|-------------|-----------|
| [`fulfillment-service`](https://github.com/osac-project/fulfillment-service) | gRPC server + REST gateway, PostgreSQL, integrated API definitions | Yes |
| [`osac-operator`](https://github.com/osac-project/osac-operator) | Kubernetes operator for OpenShift clusters via Hosted Control Planes | Yes |
| [`osac-aap`](https://github.com/osac-project/osac-aap) | Ansible Automation Platform roles for network provisioning | Check repo |
| [`osac-installer`](https://github.com/osac-project/osac-installer) | Installation manifests and prerequisites | — |
| [`osac-test-infra`](https://github.com/osac-project/osac-test-infra) | Integration testing infrastructure | — |
| [`enhancement-proposals`](https://github.com/osac-project/enhancement-proposals) | Design documents and RFCs | — |
| [`docs`](https://github.com/osac-project/docs) | Architecture docs and guides (see `docs/architecture/`) | — |

Note: `fulfillment-api` and `fulfillment-common` were merged into `fulfillment-service`.

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

When fixing bugs or adding features, **check all controllers** that follow the same pattern — a bug in one controller likely exists in others.

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

## GSD Workflow

This project uses the GSD workflow system. Planning artifacts live in `.planning/`.

- Use `/gsd:progress` to check project status
- Use `/gsd:plan-phase` for planning, `/gsd:execute-phase` for implementation
- GSD operates at workspace level but coordinates across component repos

## OpenShift Deployment

```bash
kubectl annotate ingresses.config/cluster ingress.operator.openshift.io/default-enable-http2=true
kubectl apply -k fulfillment-service/manifests
export token=$(kubectl create token -n osac client)
export route=$(kubectl get route -n osac fulfillment-api -o json | jq -r '.spec.host')
grpcurl -insecure -H "Authorization: Bearer ${token}" ${route}:443 fulfillment.v1.VirtualNetworks/List
```
