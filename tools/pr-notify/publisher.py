"""Publish dashboard data to GitHub via a PR-based flow.

Creates a branch, uploads data.json via the Contents API, opens a PR,
and merges it using admin privileges to bypass required reviews.
"""

import base64
import json
import logging
import subprocess
from datetime import datetime, timezone

from models import DashboardConfig

logger = logging.getLogger(__name__)

_BRANCH_NAME = "dashboard-data"
_PR_TITLE = "Update PR dashboard data"


def _gh_api(args: list[str], input_data: str | None = None) -> subprocess.CompletedProcess:
    cmd = ["gh", "api", *args]
    return subprocess.run(
        cmd,
        input=input_data,
        capture_output=True,
        text=True,
        timeout=30,
    )


def _get_main_sha(repo: str, branch: str) -> str:
    result = _gh_api([f"repos/{repo}/git/ref/heads/{branch}", "--jq", ".object.sha"])
    if result.returncode != 0:
        raise SystemExit(f"Failed to get {branch} SHA: {result.stderr.strip()}")
    return result.stdout.strip()


def _ensure_branch(repo: str, base_branch: str) -> None:
    """Create or force-update the dashboard-data branch to base branch HEAD."""
    sha = _get_main_sha(repo, base_branch)

    result = _gh_api([
        f"repos/{repo}/git/refs/heads/{_BRANCH_NAME}",
        "--jq", ".object.sha",
    ])

    if result.returncode == 0 and result.stdout.strip():
        _gh_api([
            f"repos/{repo}/git/refs/heads/{_BRANCH_NAME}",
            "--method", "PATCH",
            "--input", "-",
        ], json.dumps({"sha": sha, "force": True}))
        logger.info("Updated branch %s to %s", _BRANCH_NAME, sha[:8])
    else:
        _gh_api([
            f"repos/{repo}/git/refs",
            "--method", "POST",
            "--input", "-",
        ], json.dumps({"ref": f"refs/heads/{_BRANCH_NAME}", "sha": sha}))
        logger.info("Created branch %s at %s", _BRANCH_NAME, sha[:8])


def _get_file_sha(repo: str, path: str, branch: str) -> str | None:
    result = _gh_api([f"repos/{repo}/contents/{path}?ref={branch}", "--jq", ".sha"])
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def _put_file(repo: str, path: str, branch: str, content: str, message: str) -> None:
    encoded = base64.b64encode(content.encode()).decode()
    sha = _get_file_sha(repo, path, branch)

    payload: dict = {
        "message": message,
        "content": encoded,
        "branch": branch,
    }
    if sha:
        payload["sha"] = sha

    result = _gh_api([
        f"repos/{repo}/contents/{path}",
        "--method", "PUT",
        "--input", "-",
    ], json.dumps(payload))

    if result.returncode != 0:
        raise SystemExit(f"Failed to upload {path}: {result.stderr.strip()}")


def _find_open_pr(repo: str) -> int | None:
    result = subprocess.run(
        [
            "gh", "pr", "list",
            "--repo", repo,
            "--head", _BRANCH_NAME,
            "--state", "open",
            "--json", "number",
            "--jq", ".[0].number",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        return int(result.stdout.strip())
    except ValueError:
        return None


def _create_pr(repo: str, base_branch: str) -> int:
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    result = subprocess.run(
        [
            "gh", "pr", "create",
            "--repo", repo,
            "--head", _BRANCH_NAME,
            "--base", base_branch,
            "--title", _PR_TITLE,
            "--body", f"Automated PR dashboard data update for {today}.",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        raise SystemExit(f"Failed to create PR: {result.stderr.strip()}")

    pr_url = result.stdout.strip()
    logger.info("Created PR: %s", pr_url)

    pr_number = pr_url.rstrip("/").rsplit("/", 1)[-1]
    return int(pr_number)


def _merge_pr(repo: str, pr_number: int) -> None:
    result = subprocess.run(
        [
            "gh", "pr", "merge",
            str(pr_number),
            "--repo", repo,
            "--merge",
            "--admin",
            "--delete-branch",
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if result.returncode != 0:
        raise SystemExit(f"Failed to merge PR #{pr_number}: {result.stderr.strip()}")
    logger.info("Merged PR #%d", pr_number)


def publish_data(data_json: str, config: DashboardConfig) -> str:
    """Push data.json to a branch, create a PR, and merge it.

    Returns the published dashboard URL.
    """
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    _ensure_branch(config.repo, config.branch)
    _put_file(
        config.repo,
        config.data_path,
        _BRANCH_NAME,
        data_json,
        f"Update PR dashboard data - {now}",
    )

    pr_number = _find_open_pr(config.repo)
    if pr_number is None:
        pr_number = _create_pr(config.repo, config.branch)

    _merge_pr(config.repo, pr_number)

    url = config.base_url.rstrip("/") + "/"
    logger.info("Published data to %s", url)
    return url
