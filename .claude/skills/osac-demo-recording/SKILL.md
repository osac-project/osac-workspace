---
name: osac-demo-recording
description: Use when creating asciinema recordings of OSAC CLI and API workflows for documentation or demos
---

# OSAC Demo Recording

## Overview

Interactive workflow for creating polished asciinema recordings of OSAC demos with the `fulfillment-cli`, authentication, async resource handling, and asciinema.org upload.

## CLI-First Principle

Demos should use the `fulfillment-cli` as the primary interface. Only fall back to the public REST API for operations where the CLI has no support. Never use the private API in demos.

The CLI (`fulfillment-service/cmd/fulfillment-cli`) supports: `create`, `get`, `delete`, `edit`, `label`, `annotate`, `login`, `console`, and resource-specific subcommands like `create cluster`, `create computeinstance`, `get kubeconfig`, `get password`, `describe cluster`, `describe computeinstance`.

## When to Use

- Demonstrating OSAC networking, compute, or cluster workflows
- Multi-step resource creation (VirtualNetwork → Subnet → SecurityGroup → ComputeInstance)
- Resources requiring async provisioning

## Workflow

**1. Analyze Context**
- Read recent files, CLAUDE.md, git history to understand current work
- Identify resources involved
- Propose demo flow based on context (e.g., "I see you created networking resources - shall we demo: List NetworkClasses → Create VirtualNetwork → Create Subnet → SecurityGroup → ComputeInstance?")

**2. Discovery Questions**
- Confirm/refine proposed workflow
- Connection details for `fulfillment-cli login`
- Polish level: simple (plain) or polished (colors/animations)
- Cleanup strategy: keep resources or delete with `--cleanup` flag

**3. Generate Script**
- Use `template-simple.sh` or `template-polished.sh` from this directory
- Prefer `fulfillment-cli` commands; fall back to `api()` helper only for operations the CLI doesn't support
- Add `wait_for_state()` calls for async resources
- Track created resources for cleanup

**4. Record**
- Dry-run: `./demo.sh --dry-run` (runs the demo flow without recording)
- Record: `./demo.sh` or `./demo.sh --cleanup`
- Test: `asciinema play <file>.cast`

**5. Publish**
- Ask: "Upload to asciinema.org?"
- If yes: `asciinema upload <file>.cast`
- Provide shareable URL

## Templates

- `template-simple.sh` - Plain output, minimal formatting
- `template-polished.sh` - ANSI colors, typing animation, headers, spinners

Both include: `refresh_auth()`, `api()`, `wait_for_state()`, cleanup tracking.

## Quick Reference

| Task | Command/Pattern |
|------|-----------------|
| Login | `fulfillment-cli login --url <url> --token <token>` |
| List resources | `fulfillment-cli get virtual-networks` |
| Create from YAML | `fulfillment-cli create -f resource.yaml` |
| Delete | `fulfillment-cli delete virtual-network <id>` |
| Describe | `fulfillment-cli describe cluster <id>` (clusters, compute instances only) |
| Watch | `fulfillment-cli get clusters -w` |
| REST fallback | `api GET/POST/DELETE "<path>" [-d '{"json"}']` |
| Async wait | `wait_for_state "<path>" "<id>" "READY" <timeout>` |
| Track resource | `CREATED_RESOURCES+=("resourcetype/${id}")` |
| Dry-run | `./demo.sh --dry-run` |
| Record+cleanup | `./demo.sh --cleanup` |

## Common Issues

- **Token expires**: Tokens last ~1h. `refresh_auth()` in loops.
- **Stuck deleting**: Remove finalizers: `kubectl patch <res> -p '{"metadata":{"finalizers":null}}'`
- **Timeout**: VMs take longer (600s), networks faster (300s)
- **Cleanup order**: Delete children before parents (VM → SG → Subnet → VNet)

## Example

See `template-simple.sh` and `template-polished.sh` in this directory for ready-to-use templates.
