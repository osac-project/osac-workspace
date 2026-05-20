"""Publish HTML dashboard to GitHub Pages via the Contents API."""

import base64
import json
import logging
import subprocess
from datetime import datetime, timezone

from models import DashboardConfig

logger = logging.getLogger(__name__)


def _get_file_sha(repo: str, path: str, branch: str) -> str | None:
    """Get the SHA of an existing file, or None if it doesn't exist."""
    result = subprocess.run(
        [
            "gh", "api",
            f"repos/{repo}/contents/{path}?ref={branch}",
            "--jq", ".sha",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def _put_file(
    repo: str, path: str, branch: str, content: str, message: str
) -> None:
    """Create or update a file on a branch via the GitHub Contents API."""
    encoded = base64.b64encode(content.encode()).decode()
    sha = _get_file_sha(repo, path, branch)

    payload: dict = {
        "message": message,
        "content": encoded,
        "branch": branch,
    }
    if sha:
        payload["sha"] = sha

    result = subprocess.run(
        [
            "gh", "api",
            f"repos/{repo}/contents/{path}",
            "--method", "PUT",
            "--input", "-",
        ],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        timeout=60,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"Failed to publish {path}: {result.stderr.strip()}"
        )


def _ensure_nojekyll(repo: str, branch: str) -> None:
    """Create .nojekyll if it doesn't already exist."""
    if _get_file_sha(repo, ".nojekyll", branch) is None:
        _put_file(repo, ".nojekyll", branch, "", "Add .nojekyll")
        logger.info("Created .nojekyll on %s", branch)


def publish_dashboard(html_content: str, config: DashboardConfig) -> str:
    """Push the HTML dashboard to the gh-pages branch.

    Returns the published dashboard URL.
    """
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    _ensure_nojekyll(config.repo, config.branch)
    _put_file(
        config.repo,
        "index.html",
        config.branch,
        html_content,
        f"Update PR dashboard — {now}",
    )
    url = config.base_url.rstrip("/") + "/"
    logger.info("Published dashboard to %s", url)
    return url
