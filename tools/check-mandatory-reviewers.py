#!/usr/bin/env python3
"""Structural check backing tools/check-mandatory-reviewers.sh.

Parses skills/.config/create-pr-reviewers.yaml as real YAML (not text
patterns) and verifies the security-review entry is intact: present under
its exact name, mandatory is boolean true, enabled is not false, and skill
still points at its own skill file (a repointed skill: value would silently
swap out what "the mandatory reviewer" actually runs while every other
field stays untouched).

Usage: check-mandatory-reviewers.py <path-to-yaml>
"""
import sys

import yaml

MANDATORY_REVIEWER_NAME = "security-review"
EXPECTED_SKILL_PATH = "skills/security-review/SKILL.md"


def fail(message):
    print(f"FAIL: {message}")
    sys.exit(1)


def main():
    if len(sys.argv) != 2:
        fail(f"usage: {sys.argv[0]} <path-to-yaml>")

    path = sys.argv[1]

    try:
        with open(path, encoding="utf-8") as f:
            config = yaml.safe_load(f)
    except FileNotFoundError:
        fail(f"{path} not found")
    except yaml.YAMLError as e:
        fail(f"{path} is not valid YAML: {e}")

    if not isinstance(config, dict):
        fail(f"{path} does not parse to a mapping")

    reviewers = config.get("reviewers")
    if not isinstance(reviewers, list):
        fail(f"{path} has no top-level 'reviewers' list")

    # Exact name match against the parsed structure -- not a substring or
    # line-anchor search -- so a decoy entry like "security-review-legacy"
    # or "security-review-experimental" is never confused with the real one.
    matches = [
        r for r in reviewers
        if isinstance(r, dict) and str(r.get("name", "")).strip() == MANDATORY_REVIEWER_NAME
    ]

    if not matches:
        fail(
            f"no '{MANDATORY_REVIEWER_NAME}' entry found in {path} — the "
            "mandatory security reviewer appears to have been removed. See "
            "skills/create-pr/references/reviewer-config.md's Mandatory "
            "Reviewers section."
        )

    if len(matches) > 1:
        fail(
            f"{len(matches)} entries named '{MANDATORY_REVIEWER_NAME}' in "
            f"{path} — check 7's name-uniqueness requirement is violated"
        )

    entry = matches[0]

    # `is True` / `is False`, not truthiness -- PyYAML already normalizes
    # every YAML 1.1 boolean spelling (True/TRUE/no/off/...) to a real bool,
    # so this is not vulnerable to the spelling-variant bypass a text-based
    # substring match would be.
    if entry.get("mandatory") is not True:
        fail(
            f"'{MANDATORY_REVIEWER_NAME}' entry in {path} does not have "
            "'mandatory: true'"
        )

    if entry.get("enabled") is False:
        fail(
            f"'{MANDATORY_REVIEWER_NAME}' entry in {path} has 'enabled: "
            "false' alongside 'mandatory: true' — create-pr's own "
            "validation checklist (check 9) should already reject this, "
            "but failing loudly here too"
        )

    actual_skill = entry.get("skill")
    if actual_skill != EXPECTED_SKILL_PATH:
        fail(
            f"'{MANDATORY_REVIEWER_NAME}' entry in {path} has skill: "
            f"{actual_skill!r}, expected {EXPECTED_SKILL_PATH!r} — the "
            "mandatory entry now points somewhere else, which defeats the "
            "guarantee even though name/mandatory/enabled all look intact"
        )

    print(
        f"PASS: '{MANDATORY_REVIEWER_NAME}' entry present in {path}, "
        f"mandatory: true, not disabled, skill: {actual_skill}"
    )


if __name__ == "__main__":
    main()
