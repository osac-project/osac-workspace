# OSAC Project

Development workspace for the Open Sovereign AI Cloud (OSAC) project. This repo provides a meta-workspace that bootstraps all OSAC components for cross-component development and testing, with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [GSD workflow](https://github.com/cyanheads/gsd) integration pre-configured.

## Getting Started

```bash
# Clone the workspace
git clone https://github.com/osac-project/osac-workspace.git
cd osac-workspace

# Bootstrap all component repos (always pulls latest main)
./bootstrap.sh
```

The bootstrap script clones all OSAC repos into the workspace. Each repo is an independent Git repository on its `main` branch — no detached HEADs, no parent repo updates needed.

## Components

| Repository | Description |
|------------|-------------|
| [fulfillment-service](https://github.com/osac-project/fulfillment-service) | gRPC/REST API server with PostgreSQL backend — manages VirtualNetworks, Subnets, SecurityGroups, ComputeInstances |
| [osac-operator](https://github.com/osac-project/osac-operator) | Kubernetes operator for deploying OpenShift clusters via Hosted Control Planes |
| [osac-aap](https://github.com/osac-project/osac-aap) | Ansible Automation Platform roles and playbooks for VM and network provisioning |
| [osac-installer](https://github.com/osac-project/osac-installer) | Installation manifests, prerequisites, and demo scripts |
| [osac-test-infra](https://github.com/osac-project/osac-test-infra) | Integration testing infrastructure |
| [enhancement-proposals](https://github.com/osac-project/enhancement-proposals) | Design documents and enhancement proposals |
| [docs](https://github.com/osac-project/docs) | Architecture documentation, diagrams, and design guides |

## What's Included

This workspace provides a pre-configured AI-assisted development environment:

| File | Purpose |
|------|---------|
| `bootstrap.sh` | Clones or updates all component repos to latest `main` — re-run anytime to sync |
| `CLAUDE.md` | Project instructions Claude Code reads automatically — build commands, architecture patterns, conventions |
| `.claude/settings.json` | Pre-approved shell commands (git, ls, cat, etc.) so Claude doesn't prompt for routine operations |
| `.planning/config.json` | GSD workflow configuration (parallelization, verification, auto-advance) |
| `.gitignore` | Ignores cloned repos, `.planning/`, `.claude/`, credentials, editor files, and build artifacts |

## Setup

After running `./bootstrap.sh` to clone all repos:

1. **kubeconfig**: Place your cluster kubeconfig at `./kubeconfig` (gitignored)
2. **Tools**: `buf`, `grpcurl`, `kubectl`, `jq`
3. **Jira CLI**: `go install github.com/ankitpokhrel/jira-cli/cmd/jira@latest` (or `brew install ankitpokhrel/jira-cli/jira-cli`)
4. **GSD workflow**: `npx get-shit-done-cc@latest` (run from workspace root)
   - GSD hooks in `.claude/settings.json` are already configured and will no-op if GSD is not installed

To update all repos to latest `main` at any time, simply re-run:
```bash
./bootstrap.sh
```

## Quick Reference

```bash
# Build and test fulfillment-service
cd fulfillment-service
go build
ginkgo run -r

# Test API against a running cluster
export KUBECONFIG=./kubeconfig
export NAMESPACE=<your-namespace>
ROUTE=$(kubectl get route -n $NAMESPACE fulfillment-api -o jsonpath='{.spec.host}')
TOKEN=$(kubectl create token -n $NAMESPACE admin)

# List resources via REST
curl -sk -H "Authorization: Bearer $TOKEN" "https://$ROUTE/api/fulfillment/v1/virtual_networks" | jq
curl -sk -H "Authorization: Bearer $TOKEN" "https://$ROUTE/api/fulfillment/v1/subnets" | jq
curl -sk -H "Authorization: Bearer $TOKEN" "https://$ROUTE/api/fulfillment/v1/compute_instances" | jq

# List resources via gRPC
grpcurl -insecure -H "Authorization: Bearer $TOKEN" $ROUTE:443 osac.public.v1.VirtualNetworks/List
```

## GSD Workflow

Once you have Claude Code running in this workspace, use GSD commands to plan and execute work:

```
/gsd:new-project     # Initialize project with requirements gathering
/gsd:plan-phase      # Plan the next phase of work
/gsd:execute-phase   # Execute a planned phase
/gsd:progress        # Check current project status
/gsd:next            # Advance to the next logical step
```

| Task Type | GSD Command | When to Use |
|-----------|-------------|-------------|
| Epic / new feature | `/gsd:new-project` | Starting a multi-phase initiative |
| Jira ticket | `/gsd:quick` | Single-ticket work with commit tracking |
| Tiny fix | `/gsd:fast` | One-file fixes, no planning overhead |
| Check status | `/gsd:progress` | See where you are in the project |
| Next step | `/gsd:next` | Auto-advance to the next logical action |

GSD manages all state under `.planning/` — milestones, phases, plans, and verification are created as you work.

## Architecture

```
NetworkClass (platform-defined)
  └── VirtualNetwork (tenant L2 network with CIDR)
        ├── Subnet (CIDR range within VirtualNetwork)
        └── SecurityGroup (firewall rules)
              └── ComputeInstance (KubeVirt VM, attached to Subnet + SecurityGroups)
```

See `CLAUDE.md` for detailed development instructions and conventions.
