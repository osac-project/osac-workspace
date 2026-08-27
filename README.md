# OSAC Project

Development workspace for the Open Sovereign AI Cloud (OSAC) project. This repo provides a meta-workspace that bootstraps all OSAC components for cross-component development and testing, with AI-assisted workflows for Claude Code, Cursor, and Gemini CLI.

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

The bootstrap script clones all OSAC repos into the workspace. Each repo is an independent Git repository on its `main` branch. By default, remotes are named `origin` (upstream) and `fork` (push target). Use `--fork-name <name>` to choose a different push remote name (e.g., `--fork-name origin` for the conventional layout where `origin` is your fork and `upstream` is the project repo).

`resolve-remotes.sh` (vendored via `osac-ai-skills`, at `~/.osac-ai-skills` or `./.osac-ai-skills`) detects remotes by URL, so all skills and hooks work regardless of naming.

Use `--no-fork` if you only need read-only access or are running in CI. To override fork repo names (e.g., if your fork of `docs` is named `osac-docs`), copy `fork-overrides.sh.example` to `fork-overrides.sh` and edit it.

## Components

| Component | Description |
|-----------|-------------|
| [osac](https://github.com/osac-project/osac) | Mono-repo: fulfillment-service + osac-operator + osac-aap + osac-installer + bare-metal-fulfillment-operator + osac-csi-driver (see subdirectories below) |
| `osac/fulfillment-service` | gRPC/REST API server with PostgreSQL backend — manages VirtualNetworks, Subnets, SecurityGroups, ComputeInstances |
| `osac/osac-operator` | Kubernetes operator for deploying OpenShift clusters via Hosted Control Planes |
| `osac/osac-aap` | Ansible Automation Platform roles and playbooks for VM and network provisioning |
| `osac/osac-installer` | Installation manifests, prerequisites, and demo scripts |
| `osac/bare-metal-fulfillment-operator` | Kubernetes operator for bare metal fulfillment |
| `osac/osac-csi-driver` | CSI storage driver, routes to vendor backends via fulfillment-service storage tiers |
| [osac-test-infra](https://github.com/osac-project/osac-test-infra) | Integration testing infrastructure |
| [osac-ui](https://github.com/osac-project/osac-ui) | OSAC UI web console for managing cloud resources |
| [enhancement-proposals](https://github.com/osac-project/enhancement-proposals) | Design documents and enhancement proposals |
| [docs](https://github.com/osac-project/docs)[^1] | Architecture documentation, diagrams, and design guides |

[^1]: Cloned into a subdirectory as `osac-docs`

## What's Included

This workspace provides a pre-configured AI-assisted development environment:

| File | Purpose |
|------|---------|
| `bootstrap.sh` | Clones or updates all component repos, vendors `osac-ai-skills` and ai-workflows, and wires agent skill symlinks — re-run anytime to sync |
| `osac-helpers.sh` | Developer shell helpers — source to get worktree and workflow utilities |
| `AGENTS.md` | Tool-agnostic project instructions (Claude, Cursor, Gemini, Copilot) — build commands, architecture; bootstrap-linked skills for Claude/Cursor/Gemini; Copilot reads this file for conventions only |
| `CLAUDE.md` | Thin wrapper that loads `AGENTS.md` plus Claude-specific command syntax |
| `tools/link-agent-skills.sh` | Consumer wrapper: materializes `skills/` from vendored `osac-ai-skills`, then links `.claude`/`.cursor`/`.gemini` skills |
| `.claude/settings.json` | Pre-approved shell commands (git, ls, cat, etc.) so Claude doesn't prompt for routine operations |
| `AI-assisted-development-workflow.md` | Stub — canonical Feature → PRD → Design → Jira sync → Implement → E2E sequence lives in [osac-ai-skills](https://github.com/osac-project/osac-ai-skills#recommended-skill-sequence) |
| `skills/` | Bootstrap-managed overlay (symlinks into vendored `osac-ai-skills` + ai-workflows) — not an editable source |
| `.osac-ai-skills/` | Vendored clone of [`osac-project/osac-ai-skills`](https://github.com/osac-project/osac-ai-skills) (gitignored; or prefer `~/.osac-ai-skills`) |
| `.gitignore` | Ignores cloned repos, `.planning/`, `.claude/`, `.cursor/`, `.gemini/`, credentials, editor files, and build artifacts |

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
To update all repos to latest `main` at any time, simply re-run:
```bash
./bootstrap.sh
```

## Developer Helpers

`osac-helpers.sh` provides shell functions for common development workflows. Source it in your terminal to make them available:

```bash
source osac-helpers.sh
```

### `osac-new-worktree <branch-name>`

Creates an isolated git worktree for development:

```bash
osac-new-worktree feat/storage-qos
osac-new-worktree fix/login-bug
osac-new-worktree OSAC-1234
```

This will:
1. Create a new branch with the given name
2. Set up a worktree at `../osac-workspace-<basename>` (e.g., `../osac-workspace-storage-qos`)
3. Switch into the new directory
4. Run `bootstrap.sh` to clone all component repos
5. If the branch name contains an OSAC Jira ticket (e.g., `OSAC-1234`), fetch the ticket summary and append it to `.claude/CLAUDE.md`

Each worktree is a fully independent workspace — you can work on multiple features in parallel without stashing or switching branches.

**Clean up** when you're done (run from the original osac-workspace directory):

```bash
# First, exit the worktree if you're still in it
cd ~/path/to/original/osac-workspace
git worktree remove ../osac-workspace-storage-qos
```

**Note:** Git will refuse to remove a worktree with uncommitted changes. Commit or stash your work first, or use `git worktree remove --force` if you're certain you want to discard the changes.

**Tip:** Add `source /path/to/osac-workspace/osac-helpers.sh` to your `~/.bashrc` or `~/.zshrc` so the helpers are always available.

## Quick Reference

```bash
# Build and test fulfillment-service
cd osac/fulfillment-service
go build ./...
ginkgo run -r internal

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

## AI-Assisted Development Workflow

See the Recommended Skill Sequence in
[`osac-ai-skills`](https://github.com/osac-project/osac-ai-skills#recommended-skill-sequence)
(local after bootstrap: `~/.osac-ai-skills/README.md` or `.osac-ai-skills/README.md`)
for the full workflow: Feature → PRD → Design → Jira sync → Implement → E2E.
A local stub remains at
[`AI-assisted-development-workflow.md`](AI-assisted-development-workflow.md).

**Prerequisites:** `./bootstrap.sh` (vendors `osac-ai-skills`, installs ai-workflows, links agent skill directories), `gh` (authenticated), `jira` CLI, `rg`

After bootstrap, OSAC skills (from `osac-ai-skills`) and ai-workflows (`bugfix`, `implement`, `prd`, `design`, `e2e`) are discoverable via `.claude/skills/`, `.cursor/skills/`, and `.gemini/skills/` (each symlinked to the local `skills/` overlay). Edit skills only in [`osac-ai-skills`](https://github.com/osac-project/osac-ai-skills). See `AGENTS.md` for agent-specific paths.

Harnesses that skip `./bootstrap.sh` (e.g. jira-autofix) must import `osac-ai-skills` and run `tools/link-agent-skills.sh` themselves before relying on OSAC-native skills.

See `AGENTS.md` and `CLAUDE.md` for detailed development instructions and conventions.
