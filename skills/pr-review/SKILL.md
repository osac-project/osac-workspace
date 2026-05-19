---
name: pr-review
description: |
  Review a PR against OSAC-specific conventions — tenant isolation, protobuf naming,
  controller patterns, cross-repo deps, commit format. Use instead of generic code-review
  for PRs in osac-project repos. Trigger on PR URLs containing osac-project, shorthand
  like osac-aap#309, or "review this PR" in osac-workspace context.
  Do NOT use for non-OSAC repos.
---

# OSAC PR Review

This skill delegates to the `osac-dev:pr-review` agent which runs in its own context.

## When to Use

- User provides a PR URL or PR number for an osac-project repo
- User says "review this PR", "check this PR", "is this PR ready"
- User asks about PR quality or convention compliance

## Parse Arguments

The `ARGUMENTS` string may contain:
- A PR URL (e.g., `https://github.com/osac-project/osac-aap/pull/309`) or shorthand (e.g., `osac-aap#309`)
- `--comment` flag — if present, post the review as a PR comment after the agent completes

Parse the arguments:
1. Check if `--comment` is present. If yes, set `POST_COMMENT=true` and strip it from the arguments.
2. The remaining argument is the PR URL or shorthand.

## Gather Inputs

Collect from conversation context. Ask only if truly ambiguous:

| Input | Required | Source |
|-------|----------|--------|
| PR URL or number | Yes | From argument or conversation |
| Repo name | Auto | Extracted from PR URL or shorthand |

If only a PR number is given without a repo, ask which repo.

## Determine Repo

Extract from the PR URL or shorthand:
- `osac-aap#N` or `github.com/osac-project/osac-aap/pull/N` → osac-aap
- `fulfillment-service#N` or `github.com/osac-project/fulfillment-service/pull/N` → fulfillment-service
- `osac-operator#N` or `github.com/osac-project/osac-operator/pull/N` → osac-operator
- `osac-installer#N` or `github.com/osac-project/osac-installer/pull/N` → osac-installer
- `enhancement-proposals#N` or `github.com/osac-project/enhancement-proposals/pull/N` → enhancement-proposals

Construct the full PR URL: `https://github.com/osac-project/<repo>/pull/<N>`

## Execute

Launch the pr-review agent:

```
Agent tool call:
  subagent_type: osac-dev:pr-review
  prompt: |
    Review this PR against OSAC conventions.

    PR URL: <full PR URL>
    Repo: <repo-name>
```

## Post-Agent: Handle --comment

When the agent completes:

1. Report the findings to the user (always).
2. If `POST_COMMENT` is true, post the review as a PR comment:
   ```bash
   gh pr comment <PR-URL> --body "<agent's review output>"
   ```
   Use a heredoc to pass the body to avoid quoting issues. Confirm to the user that the comment was posted.
