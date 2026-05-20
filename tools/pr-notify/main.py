#!/usr/bin/env python3
"""PR status notifier -- fetches open PRs and surfaces stale/blocked ones."""

import argparse
import logging
import sys
from datetime import datetime, timezone

from classifier import classify_prs
from config import load_config
from formatter import format_compact_summary, format_html_dashboard, format_message
from github import fetch_open_prs
from publisher import publish_dashboard
from slack import post_message


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
    """Entry point: load config, fetch PRs, classify, format, and post."""
    parser = argparse.ArgumentParser(
        description="Fetch open PR status from GitHub repos"
    )
    parser.add_argument(
        "--config",
        required=True,
        help="Path to TOML config file",
    )
    parser.add_argument(
        "--mode",
        choices=["slack", "dashboard"],
        default="slack",
        help="slack: full Slack message (default); dashboard: HTML dashboard + compact Slack summary",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print formatted message to stdout instead of posting to Slack",
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

        classified = classify_prs(prs)
        logger.info("Classified %d PRs", len(classified))

        if args.mode == "dashboard":
            if not config.dashboard:
                raise SystemExit(
                    "Dashboard mode requires a [dashboard] section in config"
                )

            html = format_html_dashboard(classified, config.repos)
            logger.info("Generated HTML dashboard (%d chars)", len(html))

            if args.dry_run:
                dashboard_url = config.dashboard.base_url
                logger.info("Dry run -- skipping publish")
            else:
                try:
                    dashboard_url = publish_dashboard(html, config.dashboard)
                    logger.info("Published dashboard: %s", dashboard_url)
                except SystemExit as pub_err:
                    logger.error("Dashboard publish failed: %s", pub_err)
                    logger.info("Falling back to full Slack message")
                    message = format_message(classified, config.repos)
                    logger.info("Formatted message (%d chars)", len(message))
                    if not args.dry_run:
                        post_message(config.slack_channel, message, config.slack_creds_dir)
                        logger.info("Posted to Slack (fallback)")
                    return 0

            message = format_compact_summary(
                classified, config.repos, dashboard_url
            )
            logger.info("Compact summary (%d chars)", len(message))
        else:
            message = format_message(classified, config.repos)
            logger.info("Formatted message (%d chars)", len(message))

        if args.dry_run:
            print(message)
            logger.info("Dry run -- message printed to stdout")
        else:
            post_message(config.slack_channel, message, config.slack_creds_dir)
            logger.info("Posted to Slack")

        return 0

    except SystemExit as e:
        logger.error("Fatal: %s", e)
        return 1
    except Exception:
        logger.exception("Unexpected error")
        return 1


if __name__ == "__main__":
    sys.exit(main())
