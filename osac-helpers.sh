#!/bin/bash
# shellcheck shell=bash
#
# osac-helpers.sh — source this file to get OSAC developer workflow utilities.
#
# Usage:
#   source osac-helpers.sh
#   osac-new-worktree feat/my-feature

osac-new-worktree() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "❌ Error: Not inside a Git repository."
        return 1
    fi

    local repo_root repo_root_name
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
    repo_root_name=$(basename "$repo_root")
    if [ "$repo_root_name" != "osac-workspace" ]; then
        echo "❌ Error: This command must be run inside 'osac-workspace'."
        echo "   (Current repository root detected as: '$repo_root_name')"
        return 1
    fi

    if [ -z "$1" ]; then
        echo "❌ Error: Please provide a branch name."
        echo "Usage: osac-new-worktree <branch-name>"
        return 1
    fi

    local branch_name=$1
    if [[ "$branch_name" =~ [[:space:]] || "$branch_name" == *..* || "$branch_name" == /* ]]; then
        echo "❌ Error: Branch name must not contain spaces, '..', or start with '/'."
        return 1
    fi

    local worktree_suffix
    worktree_suffix=$(basename "$branch_name")
    local target_dir
    target_dir="$(dirname "$repo_root")/osac-workspace-$worktree_suffix"

    echo "🌿 Creating worktree for branch '$branch_name' at '$target_dir'..."
    if ! git -C "$repo_root" worktree add -b "$branch_name" "$target_dir"; then
        echo "❌ Error: Failed to create worktree."
        echo "   Possible causes:"
        echo "   - Branch '$branch_name' already exists (use: git branch -d $branch_name)"
        echo "   - Worktree path conflicts with an existing directory"
        echo "   To list existing worktrees: git worktree list"
        return 1
    fi

    cd "$target_dir" || return 1
    echo "🚀 Switched to worktree: $(pwd)"

    # Bootstrapping
    if ! ./bootstrap.sh; then
        echo "❌ Error: bootstrap.sh failed."
        return 1
    fi

    # If the branch name contains a Jira ticket, append context to .claude/CLAUDE.md
    local ticket=""
    if [[ "$branch_name" =~ (OSAC-[0-9]+) ]]; then
        ticket="${BASH_REMATCH[1]}"
        echo "🎫 Fetching Jira ticket $ticket..."
        local raw summary issue_type
        raw=$(jira issue view "$ticket" --raw 2>/dev/null)
        if [ -n "$raw" ]; then
            summary=$(echo "$raw" | jq -r '.fields.summary // empty' 2>/dev/null)
            issue_type=$(echo "$raw" | jq -r '.fields.issuetype.name // empty' 2>/dev/null)
            if [ -n "$summary" ]; then
                mkdir -p .claude
                printf '\n## Current Work\n- **Jira:** [%s](https://redhat.atlassian.net/browse/%s)\n- **Summary:** %s\n- **Type:** %s\n' \
                    "$ticket" "$ticket" "$summary" "${issue_type:-Unknown}" >> .claude/CLAUDE.md
                echo "📋 Appended Jira context to .claude/CLAUDE.md"
            else
                echo "⚠️  Jira ticket $ticket has no summary field."
            fi
        else
            echo "⚠️  Could not fetch Jira ticket $ticket (is jira CLI configured?)"
        fi
    fi
}
