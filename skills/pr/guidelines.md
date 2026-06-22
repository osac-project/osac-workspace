# PR Workflow Guidelines

## Principles

- **Component-first.** Every phase starts by resolving the target component directory. If the user didn't specify one, ask — never guess.
- Capture reviewer comments verbatim. Do not paraphrase or soften feedback.
- Respect reviewer intent. When a comment is ambiguous, present both interpretations.
- Separate code changes from clarifications. Make this distinction explicit for each comment.
- Preserve the review trail. Posted responses become permanent project record.
- Group related comments. Surface patterns so the user addresses a concern once rather than per-occurrence.
- **Use PRD and design context when available.** If related PRD requirements or design decisions exist in `.artifacts/`, use them to inform reviews, categorize comments, and justify responses. Cite specific requirements when they support the approach taken. Flag reviewer requests that fall outside the documented scope as potential follow-up items.

## Hard Limits

- **No posting responses without explicit user approval.** Propose every response first, then wait for the user to approve, modify, or reject it. No exceptions.
- **Never push to `origin`.** Always push to the `fork` remote. This is the project's fork-based workflow.
- **No force-pushing** without explicit user confirmation.
- **No closing, merging, or marking PRs as ready.** The workflow reads PR state and posts replies — it never changes PR lifecycle state.
- No fabricating reviewer positions. Use what the reviewer actually wrote.
- No auto-advancing between phases. Always wait for the user.
- No modifying comments or reviews posted by others.
- No skipping validation checks during `/create`.

## Safety

- Show proposed responses before posting. The user reviews and approves each one.
- Indicate confidence when categorizing comments. If intent is unclear, say so.
- Flag comments that imply architectural or design-level changes.
- Before posting replies, confirm the target PR number and repository.
- Before pushing, verify the branch and remote are correct.
- When checking out PRs for review, use temporary worktrees to avoid disturbing the user's working tree.

## Quality

- Responses should be concise and address the reviewer's specific concern.
- When a comment requires a code change, describe the change precisely before making it.
- Track which comments have been addressed and which remain open.
- Reviews should reference specific file paths and line numbers.
- PR titles must include the Jira ticket key when one exists.

## Escalation

Stop and request human guidance when:

- Reviewer comments contradict each other
- A comment requests an architectural change beyond the PR's scope
- The reviewer's intent is unclear after reading the full thread
- A comment references requirements or context not available in the codebase
- Validation checks fail during `/create` — do not proceed to push
- The push to fork is rejected — do not force-push automatically

## Working With the Project

- Read and follow the component repo's `CLAUDE.md` before running validation or creating PRs.
- Use the project's configured remotes and branching strategy.
- Use repo-specific validation commands (build, test, lint) as documented in each component's CLAUDE.md.
- Adopt the project's commit message conventions (DCO sign-off, AI attribution trailer).
