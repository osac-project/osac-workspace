# Cross-Repo Development Workflow

## Component Routing

Each component repo has its own CLAUDE.md. **Always read it before making changes.**

| Component | Focus |
|-----------|-------|
| `osac/fulfillment-service/CLAUDE.md` | Build, test, server patterns, database layer |
| `osac/osac-operator/CLAUDE.md` | Operator build, CRDs, deployment |
| `osac/osac-aap/CLAUDE.md` | Ansible roles, infrastructure provisioning |
| `osac/osac-installer/CLAUDE.md` | Installation manifests, Helm charts, prerequisites |
| `osac/bare-metal-fulfillment-operator/CLAUDE.md` | Bare-metal fulfillment operator |
| `osac/osac-csi-driver/CLAUDE.md` | CSI storage driver (no `CLAUDE.md` yet — see its `README.md`) |
| `osac-test-infra/CLAUDE.md` | E2E tests, pytest fixtures, gRPC/K8s clients |
| `osac-ui/CLAUDE.md` | Web console, React, PatternFly 6 |

## Git Worktrees

**Use worktrees for**: multi-commit features, long-running branches, parallel work, PR isolation.

`fulfillment-service`, `osac-operator`, `osac-aap`, `osac-installer`,
`bare-metal-fulfillment-operator`, and `osac-csi-driver` are subdirectories of one
`osac/` mono-repo, so a single worktree covers all six — this is what makes a
cross-component change land as one branch/one PR instead of several:

```bash
cd osac
git worktree add -b feature-branch ../osac-feature-branch
cd ../osac-feature-branch
# Work here, then clean up:
git worktree remove ../osac-feature-branch
```

**Work directly on main for**: quick fixes, docs, exploration, running tests.

## Cross-Component Changes

`fulfillment-service`, `osac-operator`, `osac-aap`, `osac-installer`,
`bare-metal-fulfillment-operator`, and `osac-csi-driver` live in one mono-repo
(`osac/`) — a feature spanning any of them is a single branch and PR there. When
a feature also spans a genuinely separate repo (e.g., `osac` + `osac-test-infra`):

1. Plan dependency order (which repo lands first?)
2. Create branches with consistent names (e.g., `feature/add-storage-api`)
3. Use worktrees for multi-commit work
4. Link PRs in descriptions ("Depends on osac-project/osac#123")
5. Merge foundation changes first

## Git Workflow

### Branching

- **Always create a feature branch** for any work — never commit directly to `main`
- Branch naming: `<type>/<ticket-or-description>` (e.g., `feat/OSAC-23607`, `fix/duplicate-aap-jobs`)

### Remotes
- **Default names** from `bootstrap.sh`: `origin` = upstream osac-project repo, `fork` = developer fork
- **Manual setups** may reverse these (e.g., `origin` = fork, `upstream` = osac-project)
- Run `eval $(tools/resolve-remotes.sh <component-path>)` to resolve `$UPSTREAM_REMOTE` and `$PUSH_REMOTE` dynamically

### Pushing and PR Submission

- **Always push to `$PUSH_REMOTE`**, never to `$UPSTREAM_REMOTE`
- PRs go from the push remote's branch to the upstream repo's `main`
- Always include the Jira ticket key in the PR title (e.g., "OSAC-12345: fix subnet race condition")
- **Use the `create-pr` skill** (`/create-pr`) to run repo-specific validation, push, and create the PR

### Commit Conventions

- Sign off all commits with DCO: `git commit -s`
- Add AI attribution trailer when AI-assisted, naming whichever tool did the
  work — never `Co-Authored-By`:
  ```text
  Assisted-by: <tool> <contact>
  ```
  Example for Claude Code:
  ```text
  Assisted-by: Claude Code <noreply@anthropic.com>
  ```
