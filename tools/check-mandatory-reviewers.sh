#!/usr/bin/env bash
# Fails if skills/.config/create-pr-reviewers.yaml no longer has a
# security-review entry with mandatory: true and not disabled. Nothing else
# in this repo's tooling enforces this — create-pr's own Validation
# Checklist (check 9) only runs when create-pr is actually invoked, so a PR
# that deletes the security-review entry outright (explicitly documented as
# passing that checklist) would otherwise go unflagged. See
# skills/create-pr/references/reviewer-config.md's Mandatory Reviewers
# section.
#
# Deliberately not a full YAML parser -- it relies on the file's own
# documented schema (reviewer-config.md's Schema section): each reviewers[]
# entry is a flat mapping, one key per line at a fixed 2-space indent for
# "- name:" and 4-space indent for the rest, with a blank line separating
# entries and before the top-level prompt_template: key. If that shape ever
# changes, this check should be revisited alongside it.
# Usage: tools/check-mandatory-reviewers.sh [path-to-yaml]
set -euo pipefail

CONFIG="${1:-skills/.config/create-pr-reviewers.yaml}"

[[ -f "$CONFIG" ]] || { echo "FAIL: $CONFIG not found"; exit 1; }

entry=$(awk '
  /^  - name: security-review$/ { capture=1 }
  capture && /^  - name:/ && !/security-review/ { exit }
  capture && /^prompt_template:/ { exit }
  capture { print }
' "$CONFIG")

if [[ -z "$entry" ]]; then
  echo "FAIL: no 'security-review' entry found in $CONFIG — the mandatory security reviewer appears to have been removed."
  echo "See skills/create-pr/references/reviewer-config.md's Mandatory Reviewers section."
  exit 1
fi

if ! grep -q "mandatory: true" <<<"$entry"; then
  echo "FAIL: 'security-review' entry in $CONFIG no longer has 'mandatory: true'."
  exit 1
fi

if grep -q "enabled: false" <<<"$entry"; then
  echo "FAIL: 'security-review' entry in $CONFIG has 'enabled: false' alongside 'mandatory: true' — create-pr's own validation checklist (check 9) should already reject this, but failing loudly here too."
  exit 1
fi

echo "PASS: security-review entry present in $CONFIG, mandatory: true, not disabled."
