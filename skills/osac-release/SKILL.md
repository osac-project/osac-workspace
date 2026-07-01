---
name: osac-release
description: >
  Publish new OSAC Helm chart versions across all component repos and the
  umbrella chart. Auto-increments patch versions by default, tags upstream/main,
  monitors CI workflows, verifies OCI registry publication, and publishes the
  osac-installer umbrella chart with the new component versions. USE WHEN user
  says "osac-release", "osac release", "publish osac", "bump osac versions",
  "publish helm charts", or wants to release new OSAC chart versions.
triggers:
  - osac-release
  - osac release
  - publish osac
  - bump osac versions
  - publish helm charts
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /osac-release -- OSAC Helm Chart Release Wizard

Guided release workflow for publishing Helm charts across all OSAC component
repos and the umbrella chart.

**CRITICAL RULES -- read these first:**
- **ZERO narration.** NEVER output filler text. Only formatted status lines
  with icons. No explanations, no transitions, no commentary.
- **Suppress bash output.** Redirect stdout with `>/dev/null`. Keep stderr for
  failure diagnosis. Never show raw git/helm/gh output on success.
- **Print progress BEFORE running.** Show icon lines before the bash command,
  result (✅/❌) after.

Read `guidelines.md` for the full output formatting rules, icon vocabulary,
and step-by-step output examples.

**Announce at start:** Print this banner, then proceed to Step 0.

```text
 ██████╗ ███████╗ █████╗  ██████╗    ██████╗ ███████╗██╗     ███████╗ █████╗ ███████╗███████╗
██╔═══██╗██╔════╝██╔══██╗██╔════╝    ██╔══██╗██╔════╝██║     ██╔════╝██╔══██╗██╔════╝██╔════╝
██║   ██║███████╗███████║██║         ██████╔╝█████╗  ██║     █████╗  ███████║███████╗█████╗
██║   ██║╚════██║██╔══██║██║         ██╔══██╗██╔══╝  ██║     ██╔══╝  ██╔══██║╚════██║██╔══╝
╚██████╔╝███████║██║  ██║╚██████╗    ██║  ██║███████╗███████╗███████╗██║  ██║███████║███████╗
 ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝    ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝
```

## Component Registry

Each component repo publishes Helm charts via a `publish-charts.yaml` GitHub
Actions workflow triggered by `v*` tag pushes. Chart.yaml files in component
repos use `version: 0.0.0` as a placeholder -- the real version is injected at
publish time.

| Component | Repo | Charts Published | Tag Pattern |
|-----------|------|-----------------|-------------|
| fulfillment-service | osac-project/fulfillment-service | `fulfillment-service` | `v0.0.X` |
| osac-operator | osac-project/osac-operator | `osac-operator` + `osac-operator-crds` | `v0.0.X` |
| osac-aap | osac-project/osac-aap | `osac-aap` | `v0.0.X` |
| bare-metal-fulfillment-operator | osac-project/bare-metal-fulfillment-operator | `bare-metal-fulfillment-operator` + `bare-metal-fulfillment-operator-crds` | `v0.0.X` |
| osac-ui | osac-project/osac-ui | `osac-ui` | `v0.0.X` |
| osac (umbrella) | osac-project/osac-installer | `osac` | `v0.0.X` or workflow_dispatch |

All charts are published to `oci://ghcr.io/osac-project/charts`.

## Repo Discovery

Repos are discovered dynamically using the `bootstrap.sh` sibling layout:

```text
/path/to/workspace/
  osac-workspace/                    <-- skill runs from here
  fulfillment-service/               <-- sibling repos
  osac-operator/
  osac-aap/
  bare-metal-fulfillment-operator/
  osac-ui/
  osac-installer/
```

Discovery steps:
1. Determine workspace root: `git rev-parse --show-toplevel` from `osac-workspace/`
2. For each component, check `$(dirname $WORKSPACE_ROOT)/<repo-name>/`
3. If not found, prompt user via AskUserQuestion for the repo path
4. Validate: `git remote get-url upstream` must match `osac-project/<repo-name>(.git)?$`

## Workflow

Execute steps in order. Read the referenced file for each phase:

| Phase | Steps | File |
|-------|-------|------|
| Pre-flight | 0, 0.5, 0.6, 0.7, 0.8 | `steps/preflight.md` |
| Tag & publish | 1, 2, 3, 4, 5, 6 | `steps/release.md` |
| Umbrella & summary | 7, 8, 9 | `steps/umbrella.md` |

## Error Handling

| Error | Action |
|-------|--------|
| `gh` or `helm` not found | Error with install instructions |
| Repo not found at expected path | Ask user for explicit path |
| No `upstream` remote | Error: `git remote add upstream git@github.com:osac-project/<repo>.git` |
| Uncommitted changes in repo | Warn (non-blocking) -- tags are on upstream/main |
| Tag already exists on same commit | Skip tagging, proceed to monitoring |
| Tag already exists on different commit | Ask: (a) delete and re-tag, (b) skip, (c) abort |
| Tag push fails after previous repos tagged | Ask: (a) rollback previous tags, (b) retry, (c) abort |
| Workflow fails | Show failed logs, offer: retry / skip / abort |
| Chart not in registry after workflow success | Wait 60s, retry up to 2 times. If still missing, ask user |
| Timeout (5 min per workflow) | Show current status, ask: keep waiting / abort |
| GitHub API rate limit | Back off to 30s polling interval, warn user |

## Important Notes

- osac-operator publishes TWO charts (operator + operator-crds) from a single
  tag push. Both use the same version number. Verify both exist before declaring
  success.
- bare-metal-fulfillment-operator also publishes TWO charts (operator +
  operator-crds) from a single tag push. Same verification pattern.
- osac-ui publishes ONE chart (`osac-ui`) from a single tag push.
- Always tag `upstream/main` to ensure the latest merged code is tagged.
- The umbrella chart uses `workflow_dispatch` (not tag push) to allow explicit
  version control over component dependencies.
- fulfillment-service also publishes container images and Go binaries via
  separate workflows -- these are triggered by the same tag but are not
  monitored by this skill (only the chart publish is critical).
- The osac-installer is tagged after Step 8 verification (not after dispatch)
  to avoid tagging a failed release.
