# Cross-repository workflow

## Find the relevant instructions

For work in the `osac/` mono-repo, read `osac/AGENTS.md` and the `AGENTS.md`
of each affected component. The mono-repo includes fulfillment, the operator,
AAP, installer, bare-metal operator, CSI driver, metering, and UI. For a separate
repository, read its own instructions in that checkout.

## Worktrees and branches

Use a worktree for a long-running branch, parallel work, or PR isolation. One
`osac/` worktree covers all its components. Base each branch on the upstream
repository's default branch, and keep work for separate repositories in their
own branches and worktrees. Use an issue-prefixed branch name consistently
across repositories when coordinating one feature.

## Changes across repositories

A change spanning components inside `osac/` belongs in one branch and PR. When
it also changes a separate repository, such as `osac-test-infra` or
`enhancement-proposals`:

1. Identify the dependency order before editing.
2. Link dependent PRs in their descriptions, for example, "Depends on
   osac-project/osac#123".
3. Merge foundation changes before PRs that depend on them.

## Remotes and PRs

Inspect remote URLs before pushing. Bootstrap usually names the upstream
remote `origin` and the contributor fork `fork`, but manual setups may differ.
Use the vendored `resolve-remotes.sh` to identify `$UPSTREAM_REMOTE` and
`$PUSH_REMOTE` by URL. Push only to the contributor fork and target the
upstream default branch. The `create-pr` skill runs repository-specific
validation and opens the PR.
