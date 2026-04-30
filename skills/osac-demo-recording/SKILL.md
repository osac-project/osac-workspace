---
name: osac-demo-recording
description: Use when creating asciinema recordings of OSAC REST/gRPC API workflows for documentation or demos
---

# OSAC Demo Recording

## Overview

Interactive workflow for creating polished asciinema recordings of OSAC API demos with authentication, async resource handling, and asciinema.org upload.

## When to Use

- Demonstrating OSAC networking, compute, or cluster API workflows
- Multi-step resource creation (VirtualNetwork → Subnet → SecurityGroup → ComputeInstance)
- Resources requiring async provisioning

## Workflow

**1. Analyze Context**
- Read recent files, CLAUDE.md, git history to understand current work
- Identify API resources involved
- Propose demo flow based on context (e.g., "I see you created networking resources - shall we demo: List NetworkClasses → Create VirtualNetwork → Create Subnet → SecurityGroup → ComputeInstance?")

**2. Discovery Questions**
- Confirm/refine proposed workflow
- Namespace and route name for auth
- Polish level: simple (plain) or polished (colors/animations)
- Cleanup strategy: keep resources or delete with `--cleanup` flag

**3. Generate Script**
- Use `template-simple.sh` or `template-polished.sh` from this directory
- Fill in: namespace, API base path, demo steps based on workflow
- Add `wait_for_state()` calls for async resources (check `.status.state` in API responses)
- Track created resources for cleanup

**4. Record**
- Dry-run: `./demo.sh --dry-run` (validates auth, endpoints, flow)
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
| Auth | `refresh_auth()` - call before API requests, in wait loops |
| API call | `api GET/POST/DELETE "<path>" [-d '{"json"}']` |
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

Real implementation: `demos_and_workflows/networking-demo/record-demo.sh`
