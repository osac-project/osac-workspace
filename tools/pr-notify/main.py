#!/usr/bin/env python3
"""PR status notifier -- fetches open PRs and surfaces stale/blocked ones."""

import argparse
import logging
import sys
from datetime import datetime, timezone

from config import load_config
from github import fetch_open_prs


def setup_logging() -> None:
    """Configure logging to stderr and a timestamped file in /tmp/."""
    log_file = f"/tmp/pr-notify-{datetime.now(timezone.utc).strftime('%Y-%m-%d')}.log"
    log_format = "%(asctime)s %(levelname)s %(name)s: %(message)s"

    handlers: list[logging.Handler] = [
        logging.StreamHandler(sys.stderr),
        logging.FileHandler(log_file, mode="a"),
    ]

    logging.basicConfig(
        level=logging.INFO,
        format=log_format,
        handlers=handlers,
    )

    logging.getLogger(__name__).info("Log file: %s", log_file)


def main() -> int:
    """Entry point: load config, fetch PRs, print summary."""
    parser = argparse.ArgumentParser(
        description="Fetch open PR status from GitHub repos"
    )
    parser.add_argument(
        "--config",
        required=True,
        help="Path to TOML config file",
    )
    args = parser.parse_args()

    setup_logging()
    logger = logging.getLogger(__name__)

    try:
        config = load_config(args.config)
        logger.info(
            "Loaded config: %d repos, channel=%s",
            len(config.repos),
            config.slack_channel,
        )

        prs = fetch_open_prs(config.repos)
        logger.info(
            "Fetched %d open PRs across %d repos",
            len(prs),
            len(config.repos),
        )

        # Print summary to stdout (classification/formatting comes in later phases)
        print(f"\n{'='*60}")
        print(f"Open PRs: {len(prs)} across {len(config.repos)} repos")
        print(f"{'='*60}")
        for pr in prs:
            draft_tag = " [DRAFT]" if pr.is_draft else ""
            ci_tag = f" CI:{pr.ci_status}" if pr.ci_status else ""
            reviews_count = len(pr.reviews)
            print(
                f"  [{pr.repo}] {pr.title}{draft_tag}{ci_tag}"
                f" (by {pr.author}, {reviews_count} reviews)"
            )
        print()

        return 0

    except SystemExit as e:
        logger.error("Fatal: %s", e)
        raise
    except Exception:
        logger.exception("Unexpected error")
        return 1


if __name__ == "__main__":
    sys.exit(main())
