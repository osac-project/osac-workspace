#!/usr/bin/env bash
# Fails if skills/.config/create-pr-reviewers.yaml no longer has a
# security-review entry with mandatory: true, not disabled, and still
# pointing at its own skill file. Nothing else in this repo's tooling
# enforces this — create-pr's own Validation Checklist (check 9) only runs
# when create-pr is actually invoked, so a PR that deletes the
# security-review entry outright (explicitly documented as passing that
# checklist), disables it, or silently repoints its skill: field would
# otherwise go unflagged. See skills/create-pr/references/reviewer-config.md's
# Mandatory Reviewers section.
#
# Delegates to a real YAML parser (tools/check-mandatory-reviewers.py) rather
# than approximating YAML semantics with text patterns -- an earlier
# grep/awk-based version of this check was itself defeated by YAML boolean
# spellings other than the literal string "false" (True/False/no/off/extra
# whitespace), a commented-out "mandatory: true" line satisfying a substring
# search, and an unanchored entry-boundary match that could be confused by an
# unrelated entry whose name merely contains "security-review" as a
# substring. A structural parse doesn't have any of those failure modes.
# Usage: tools/check-mandatory-reviewers.sh [path-to-yaml]
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG="${1:-skills/.config/create-pr-reviewers.yaml}"

python3 "${SCRIPT_DIR}/check-mandatory-reviewers.py" "$CONFIG"
