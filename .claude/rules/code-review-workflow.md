# Code Review Workflow

## Self-Review Before Creating PRs

Before creating a PR or claiming work is complete, run `superpowers:requesting-code-review` to self-review your own changes. This catches issues before they reach human reviewers and ensures the code meets project standards.

## Reviewing Others' PRs

When asked to review a pull request (or when `/review` is invoked), use `code-review:code-review` to perform an automated multi-agent review. This launches parallel review agents that check for CLAUDE.md compliance, bugs, historical context, and code comment adherence, with confidence scoring to filter false positives.
