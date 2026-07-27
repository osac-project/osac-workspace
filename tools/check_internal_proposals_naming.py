#!/usr/bin/env python3
"""Validate internal-proposals/ directory and file naming for paths new to a PR.

Adapted from enhancement-proposals' .github/scripts/check_ep_naming.py —
same grandfathering and validation logic, retargeted at this repo's
internal-proposals/ tree (see internal-proposals/README.md) instead of
enhancement-proposals' enhancements/.

Directories and files that already existed at the PR base branch are
grandfathered — this only enforces the naming convention on new work.

Enforcement requires a PR base SHA (set via PR_BASE_SHA, always present in
the CI job — see .github/workflows/internal-proposals-naming.yml). Local
runs without it are advisory-only (a note is printed, nothing is flagged)
so a local invocation never blocks something CI would pass.

PR_BASE_SHA is a snapshot of the PR's base branch taken from the
`pull_request` webhook payload at the PR's last open/synchronize event —
it does not advance just because the base branch gains new commits, and
re-running an old CI job replays that same stale payload rather than
refreshing it. For a long-lived PR that hasn't been pushed to since some
*other*, unrelated PR merged a still-non-compliant directory into the base
branch, that stale SHA predates the unrelated directory, so it looks "new"
here and gets (incorrectly) enforced against — even though the current PR
never touches it and it's already correctly grandfathered on the base
branch itself.

To avoid that false positive, grandfathering also checks the *live* tip of
the base branch (LIVE_BASE_REF, e.g. origin/main, fetched fresh at the
start of every CI run) in addition to the stale base SHA: a path is
grandfathered if it exists at *either* reference. This keeps enforcement
scoped to paths that are genuinely new — including for contributors
actively renaming their own non-compliant directory to fix it, who should
never be blocked by an unrelated pre-existing violation elsewhere in the
repo.
"""

import os
import re
import subprocess
import sys

NAME_RE = re.compile(r"^OSAC-[1-9][0-9]*-[a-z0-9]+(?:-[a-z0-9]+)*$")
CHECKED_FILENAMES = frozenset({"prd.md", "design.md"})
PROPOSALS_PREFIX = "internal-proposals/"

BASE_SHA_ENV_VAR = "PR_BASE_SHA"
LIVE_BASE_REF_ENV_VAR = "LIVE_BASE_REF"


def path_exists_at_ref(ref: str, path: str) -> bool:
    result = subprocess.run(
        ["git", "cat-file", "-e", f"{ref}:{path}"],
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def ref_exists(ref: str) -> bool:
    result = subprocess.run(
        ["git", "cat-file", "-e", ref], capture_output=True, check=False
    )
    return result.returncode == 0


def top_level_proposal_dir(path: str) -> str | None:
    if not path.startswith(PROPOSALS_PREFIX):
        return None
    rest = path[len(PROPOSALS_PREFIX):]
    if "/" not in rest:
        return None
    return rest.split("/", 1)[0]


def resolve_live_base_ref(live_base_ref: str | None) -> str | None:
    # The live ref is best-effort: it's only set in CI (and only useful once
    # actions/checkout has actually fetched it). If it's absent or doesn't
    # resolve, grandfathering silently falls back to the base-SHA-only
    # behavior below rather than erroring — this is a supplementary check,
    # not a required one.
    if live_base_ref is not None and ref_exists(live_base_ref):
        return live_base_ref
    return None


def is_grandfathered(
    path: str, base_sha: str | None, live_base_ref: str | None
) -> bool:
    if base_sha is not None and path_exists_at_ref(base_sha, path):
        return True
    if live_base_ref is not None and path_exists_at_ref(live_base_ref, path):
        return True
    return False


def validate_paths(
    paths: list[str],
    base_sha: str | None,
    live_base_ref: str | None = None,
) -> list[str]:
    # No base SHA at all means this is a local, non-CI run (CI always sets
    # PR_BASE_SHA). Enforcing here would block commits that CI would pass —
    # e.g. anyone editing a file in an existing legacy directory — and push
    # contributors toward `--no-verify`-style workarounds. So local runs are
    # advisory-only; CI remains the sole enforcement gate.
    if base_sha is None:
        print(
            "note: no PR base SHA available — normal for local, non-CI "
            "runs (this script has no way to know your PR's base branch "
            "outside CI). Skipping internal-proposals/ naming/casing "
            "checks here; the CI job (which sets PR_BASE_SHA) is the "
            "authoritative gate and will still catch violations before "
            "merge.",
            file=sys.stderr,
        )
        return []

    # A base SHA *was* provided (i.e. we're in CI) but doesn't resolve —
    # unlike the "no base SHA" case above, this indicates a CI
    # misconfiguration (e.g. a shallow checkout) and should stay fail-closed
    # rather than silently disabling enforcement. That fail-closed guarantee
    # covers the live ref too: a checkout broken enough that the base SHA
    # doesn't resolve can't be trusted to have fetched the live ref
    # correctly either, so grandfathering is disabled entirely here, not
    # just narrowed to one reference.
    if not ref_exists(base_sha):
        print(
            f"warning: PR base SHA '{base_sha}' is not available in this "
            "checkout (the checkout step needs fetch-depth: 0) — "
            "grandfathering disabled, every internal-proposals/ path will "
            "be validated as new",
            file=sys.stderr,
        )
        base_sha = None
        live_base_ref = None
    else:
        live_base_ref = resolve_live_base_ref(live_base_ref)

    violations = []
    for path in paths:
        dir_name = top_level_proposal_dir(path)
        if dir_name is None:
            continue

        dir_path = f"{PROPOSALS_PREFIX}{dir_name}"
        dir_is_grandfathered = is_grandfathered(dir_path, base_sha, live_base_ref)

        if not dir_is_grandfathered and not NAME_RE.match(dir_name):
            violations.append(
                f"{path}: directory '{dir_name}' doesn't match the "
                "required format <jira-key>-<slug> (e.g. "
                "OSAC-1110-example-proposal) — see "
                "internal-proposals/README.md for the full naming "
                "convention"
            )

        basename = path.rsplit("/", 1)[-1]
        if basename.lower() not in CHECKED_FILENAMES or basename.lower() == basename:
            continue

        file_is_grandfathered = is_grandfathered(path, base_sha, live_base_ref)
        if not file_is_grandfathered:
            violations.append(
                f"{path}: filename '{basename}' must be lowercase "
                f"('{basename.lower()}')"
            )

    return violations


def main(argv: list[str]) -> int:
    base_sha = os.environ.get(BASE_SHA_ENV_VAR) or None
    live_base_ref = os.environ.get(LIVE_BASE_REF_ENV_VAR) or None
    violations = validate_paths(argv, base_sha, live_base_ref)
    for violation in violations:
        print(violation, file=sys.stderr)
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
