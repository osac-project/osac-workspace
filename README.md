# OSAC Project

Development workspace for the Open Sovereign AI Cloud (OSAC) project. This repo provides a meta-workspace that bootstraps all OSAC components for cross-component development and testing, with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [GSD workflow](https://github.com/cyanheads/gsd) integration pre-configured.

## Prerequisites

Choose one of the two development setups:

### Option A: Distrobox (recommended)

All dev tools are packaged in a container — no need to install toolchains on your host.

- **git**
- **make**
- **[podman](https://podman.io/)** and **[distrobox](https://distrobox.it/)**

See [Distrobox Dev Environment](#distrobox-dev-environment) to get started.

### Option B: Local toolchain

Install tools directly on your host.

- **git**
- **[gh CLI](https://cli.github.com/)**: Install and authenticate with `gh auth login` (required for fork workflow; use `--no-fork` if you only need read-only access)
- Go, Node.js, buf, kubectl, kind, jira CLI (see [Setup](#setup) for details)

## Getting Started

```bash
# Clone the workspace
git clone https://github.com/osac-project/osac-workspace.git
cd osac-workspace

# Bootstrap all component repos with fork setup (requires gh CLI)
./bootstrap.sh

# Or clone read-only without forking
./bootstrap.sh --no-fork
```

The bootstrap script clones all OSAC repos into the workspace. Each repo is an independent Git repository on its `main` branch with remotes configured as:
- `origin` = osac-project (upstream source, PR target)
- `fork` = your GitHub fork (push target for feature branches)

Use `--no-fork` if you only need read-only access or are running in CI.

## Components

| Repository | Description |
|------------|-------------|
| [fulfillment-service](https://github.com/osac-project/fulfillment-service) | gRPC/REST API server with PostgreSQL backend — manages VirtualNetworks, Subnets, SecurityGroups, ComputeInstances |
| [osac-operator](https://github.com/osac-project/osac-operator) | Kubernetes operator for deploying OpenShift clusters via Hosted Control Planes |
| [osac-aap](https://github.com/osac-project/osac-aap) | Ansible Automation Platform roles and playbooks for VM and network provisioning |
| [osac-installer](https://github.com/osac-project/osac-installer) | Installation manifests, prerequisites, and demo scripts |
| [osac-test-infra](https://github.com/osac-project/osac-test-infra) | Integration testing infrastructure |
| [osac-ui](https://github.com/osac-project/osac-ui) | OSAC UI web console for managing cloud resources |
| [enhancement-proposals](https://github.com/osac-project/enhancement-proposals) | Design documents and enhancement proposals |
| [docs](https://github.com/osac-project/docs)[^1] | Architecture documentation, diagrams, and design guides |

[^1]: Cloned into a subdirectory as `osac-docs`

## What's Included

This workspace provides a pre-configured AI-assisted development environment:

| File | Purpose |
|------|---------|
| `bootstrap.sh` | Clones or updates all component repos to latest `main` — re-run anytime to sync |
| `CLAUDE.md` | Project instructions Claude Code reads automatically — build commands, architecture patterns, conventions |
| `.claude/settings.json` | Pre-approved shell commands (git, ls, cat, etc.) so Claude doesn't prompt for routine operations |
| `.planning/config.json` | GSD workflow configuration (parallelization, verification, auto-advance) |
| `skills/` | AI skills for Claude Code — EP generation, Jira management, bug fix workflows, demo recording |
| `.gitignore` | Ignores cloned repos, `.planning/`, `.claude/`, credentials, editor files, and build artifacts |

## Distrobox Dev Environment

A containerized development environment is provided via [distrobox](https://distrobox.it/), packaging all required tools (Go, Node.js, buf, kubectl, kind, gh, jira, Claude Code) in a Fedora 42-based container. This gives you a reproducible environment without installing toolchains on your host.

```bash
# Build the image and enter the distrobox
make enter

# Or run Claude Code directly inside the distrobox
make claude

# Pass flags to Claude Code
make claude ARGS="--resume"

# Check status of image and distrobox
make status

# Rebuild from scratch
make rebuild
```

The distrobox shares your home directory by default (override with `HOME_DIR`). All host files, SSH keys, and credentials are available inside the container.

| Target | Description |
|--------|-------------|
| `make image` | Build the container image |
| `make enter` | Enter the distrobox (creates on first run) |
| `make claude` | Run Claude Code inside the distrobox |
| `make stop` | Stop the running container |
| `make rm` | Remove the distrobox |
| `make rebuild` | Rebuild image from scratch and enter |
| `make status` | Show image and distrobox status |

## Setup

After running `./bootstrap.sh` to clone all repos:

1. **kubeconfig**: Place your cluster kubeconfig at `./kubeconfig` (gitignored)
2. **Tools**: `buf`, `grpcurl`, `kubectl`, `jq`, [`rg`](https://github.com/BurntSushi/ripgrep)
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

## Enhancement Proposals

This workspace includes two approaches for creating OSAC Enhancement Proposals with Claude Code.

### Two-Stage Flow (PRD + Design) — Recommended

Follows the same pattern as flightctl: create a PRD first, merge it, then create the design document (EP). The design template is a lightly modified version of the standard EP format — requirements-heavy sections (Summary, Motivation, User Stories) are shortened with PRD references, and four new subsections are added (Security Considerations, Failure Handling, RBAC/Tenancy, Observability).

**Stage 1 — PRD:**

```text
/prd:ingest OSAC-XXXXX      # Fetch requirements from Jira
/prd:clarify                 # Iterative Q&A to resolve ambiguities
/prd:draft                   # Generate PRD
/prd:publish                 # Submit PR to enhancement-proposals repo
/prd:respond                 # Address reviewer comments
```

**Stage 2 — Design (EP):**

```text
/design:ingest OSAC-XXXXX   # Read PRD, explore codebase, capture context
/design:draft                # Generate EP using OSAC design template
/design:publish              # Submit PR to enhancement-proposals repo
/design:respond              # Address reviewer comments
/design:decompose            # Break into Jira-ready epics and stories
/design:sync                 # Sync epics/stories to Jira
```

Both stages publish to the `enhancement-proposals` repo under `enhancements/<feature-slug>/` — the PRD as `prd.md` and the design document as `README.md`.

### Single-Step Flow (Legacy)

For simpler proposals that don't need a separate PRD:

```text
/ep.create
```

Provide rough requirements, meeting notes, or a Jira ticket (e.g., `OSAC-XXXXX`) and the skill will explore the codebase, ask clarifying questions, generate a full EP, and submit a PR.

### Post-Approval

**Convert an approved EP into Jira work items:**

```
/ep.to-jira
```

This creates a Jira epic with ordered sub-tasks (proto, backend, controller, tests, docs) and a complexity assessment.

**Prerequisites:** `gh` (authenticated), `jira` CLI, `rg`

## Architecture

```
NetworkClass (platform-defined)
  └── VirtualNetwork (tenant L2 network with CIDR)
        ├── Subnet (CIDR range within VirtualNetwork)
        └── SecurityGroup (firewall rules)
              └── ComputeInstance (KubeVirt VM, attached to Subnet + SecurityGroups)
```

See `CLAUDE.md` for detailed development instructions and conventions.
