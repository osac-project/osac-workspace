# Cross-Repo Development Workflow

## Component Routing

Each component repo has its own CLAUDE.md. **Always read it before making changes.**

| Component | Focus |
|-----------|-------|
| `fulfillment-service/CLAUDE.md` | Build, test, server patterns, database layer |
| `osac-operator/CLAUDE.md` | Operator build, CRDs, deployment |
| `osac-aap/CLAUDE.md` | Ansible roles, network provisioning |
| `osac-installer/CLAUDE.md` | Installation manifests, prerequisites, demo scripts |

## Git Worktrees

**Use worktrees for**: multi-commit features, long-running branches, parallel work, PR isolation.

```bash
cd fulfillment-service
git worktree add ../fulfillment-service-feature-branch feature-branch
cd ../fulfillment-service-feature-branch
# Work here, then clean up:
git worktree remove ../fulfillment-service-feature-branch
```

**Work directly on main for**: quick fixes, docs, exploration, running tests.

## Cross-Component Changes

When a feature spans repos (e.g., API + operator):

1. Plan dependency order (which repo lands first?)
2. Create branches with consistent names (e.g., `feature/add-storage-api`)
3. Use worktrees for multi-commit work
4. Link PRs in descriptions ("Depends on fulfillment-service#123")
5. Merge foundation changes first

## Git Workflow

### Branching
- **Always create a feature branch** for any work — never commit directly to `main`
- Branch naming: `<type>/<ticket-or-description>` (e.g., `feat/MGMT-23607`, `fix/duplicate-aap-jobs`)

### Remotes
- `origin` — the upstream osac-project repo (push target for PRs)
- `fork` — optional developer fork (for contributors without write access)

### PR Submission
- PRs target `origin/main`
- Always include the Jira ticket key in the PR title (e.g., "MGMT-12345: fix subnet race condition")

### Commit Conventions
- Sign off all commits with DCO: `git commit -s`
- Add AI attribution trailer when AI-assisted:
  ```text
  Assisted-by: Claude Code <noreply@anthropic.com>
  ```
