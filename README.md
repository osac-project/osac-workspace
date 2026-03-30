# OSAC Project

Development workspace for the Open Sovereign AI Cloud (OSAC) project. This repo aggregates all OSAC components as git submodules for cross-component development and testing, with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [GSD workflow](https://github.com/cyanheads/gsd) integration pre-configured.

## Getting Started

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/eranco74/claude-code-workspace-template.git osac-project
cd osac-project

# Or init submodules after cloning
git submodule update --init --recursive
```

## Components

| Submodule | Description |
|-----------|-------------|
| [fulfillment-service](https://github.com/osac-project/fulfillment-service) | gRPC/REST API server with PostgreSQL backend — manages VirtualNetworks, Subnets, SecurityGroups, ComputeInstances |
| [osac-operator](https://github.com/osac-project/osac-operator) | Kubernetes operator for deploying OpenShift clusters via Hosted Control Planes |
| [osac-aap](https://github.com/osac-project/osac-aap) | Ansible Automation Platform roles and playbooks for VM and network provisioning |
| [osac-installer](https://github.com/osac-project/osac-installer) | Installation manifests, prerequisites, and demo scripts |
| [osac-templates](https://github.com/osac-project/osac-templates) | AAP job templates for compute and networking provisioning |
| [osac-test-infra](https://github.com/osac-project/osac-test-infra) | Integration testing infrastructure |
| [enhancement-proposals](https://github.com/osac-project/enhancement-proposals) | Design documents and enhancement proposals |

## What's Included

Beyond the submodules, this repo provides a pre-configured AI-assisted development environment:

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project instructions Claude Code reads automatically — build commands, architecture patterns, conventions |
| `.claude/settings.json` | Pre-approved shell commands (git, ls, cat, etc.) so Claude doesn't prompt for routine operations |
| `.planning/config.json` | GSD workflow configuration (parallelization, verification, auto-advance) |
| `.gitignore` | Ignores `.planning/`, `.claude/`, credentials, editor files, and build artifacts |

## Setup

1. **kubeconfig**: Place your cluster kubeconfig at `./kubeconfig` (gitignored)
2. **Go**: Ensure Go is installed (see `CLAUDE.md` for direnv-based setup)
3. **Tools**: `buf`, `grpcurl`, `kubectl`, `jq`
4. **Claude Code**: Install from https://docs.anthropic.com/en/docs/claude-code

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
