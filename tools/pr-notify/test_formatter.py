"""Unit tests for the Slack mrkdwn formatter."""

import unittest
from datetime import date
from unittest.mock import patch

from formatter import format_message
from models import ClassifiedPR, PRData, PRStatus


def _make_pr_data(**overrides) -> PRData:
    """Create a PRData with sensible defaults."""
    defaults = {
        "title": "Fix widget rendering",
        "url": "https://github.com/osac-project/fulfillment-service/pull/42",
        "author": "alice",
        "repo": "osac-project/fulfillment-service",
        "created_at": "2026-04-20T10:00:00Z",
        "is_draft": False,
        "labels": [],
        "reviews": [],
        "review_requests": [],
        "last_commit_date": "2026-04-20T10:00:00Z",
        "ci_status": None,
    }
    defaults.update(overrides)
    return PRData(**defaults)


def _make_classified(
    status: PRStatus = PRStatus.NEEDS_REVIEW,
    age_days: int = 2,
    reviewer_name: str | None = None,
    **pr_overrides,
) -> ClassifiedPR:
    """Create a ClassifiedPR with defaults."""
    return ClassifiedPR(
        pr=_make_pr_data(**pr_overrides),
        status=status,
        age_days=age_days,
        reviewer_name=reviewer_name,
    )


class TestFormatter(unittest.TestCase):
    """Tests for the Slack mrkdwn formatter covering format, grouping, and limits."""

    @patch("formatter.date")
    def test_single_pr_formats_correctly(self, mock_date):
        """1. Single PR formats correctly with all fields."""
        mock_date.today.return_value = date(2026, 4, 23)
        mock_date.side_effect = lambda *a, **kw: date(*a, **kw)

        cpr = _make_classified(
            status=PRStatus.NEEDS_REVIEW,
            age_days=3,
            title="Fix widget rendering",
            url="https://github.com/osac-project/fulfillment-service/pull/42",
            author="alice",
            repo="osac-project/fulfillment-service",
        )
        result = format_message([cpr], ["osac-project/fulfillment-service"])

        self.assertIn("*PR Status Summary*", result)
        self.assertIn("2026-04-23", result)
        self.assertIn(":eyes:", result)
        self.assertIn(
            "<https://github.com/osac-project/fulfillment-service/pull/42|Fix widget rendering>",
            result,
        )
        self.assertIn("alice", result)
        self.assertIn("3d", result)
        self.assertIn("needs review", result)

    @patch("formatter.date")
    def test_prs_grouped_by_repo(self, mock_date):
        """2. PRs grouped by repo with correct headers."""
        mock_date.today.return_value = date(2026, 4, 23)
        mock_date.side_effect = lambda *a, **kw: date(*a, **kw)

        prs = [
            _make_classified(repo="osac-project/fulfillment-service", title="PR 1"),
            _make_classified(repo="osac-project/osac-operator", title="PR 2"),
            _make_classified(repo="osac-project/fulfillment-service", title="PR 3"),
        ]
        result = format_message(
            prs, ["osac-project/fulfillment-service", "osac-project/osac-operator"]
        )

        self.assertIn("*osac-project/fulfillment-service* (2)", result)
        self.assertIn("*osac-project/osac-operator* (1)", result)

    def test_empty_pr_list_all_clear(self):
        """3. Empty PR list returns 'All clear' message."""
        repos = ["osac-project/fulfillment-service", "osac-project/osac-operator"]
        result = format_message([], repos)

        self.assertEqual(result, "All clear — no open PRs across 2 repos :tada:")

    @patch("formatter.date")
    def test_status_emoji_mapping(self, mock_date):
        """4. Status emoji mapping for all 6 states."""
        mock_date.today.return_value = date(2026, 4, 23)
        mock_date.side_effect = lambda *a, **kw: date(*a, **kw)

        mapping = {
            PRStatus.NEEDS_REVIEW: ":eyes:",
            PRStatus.NEEDS_RE_REVIEW: ":warning:",
            PRStatus.CHANGES_REQUESTED: ":red_circle:",
            PRStatus.APPROVED: ":white_check_mark:",
            PRStatus.CI_FAILING: ":x:",
            PRStatus.DRAFT: ":construction:",
        }
        for status, expected_emoji in mapping.items():
            reviewer = "bob" if status == PRStatus.CHANGES_REQUESTED else None
            cpr = _make_classified(status=status, reviewer_name=reviewer)
            result = format_message([cpr], ["osac-project/fulfillment-service"])
            self.assertIn(
                expected_emoji, result, f"Missing emoji {expected_emoji} for {status}"
            )

    @patch("formatter.date")
    def test_staleness_7_days(self, mock_date):
        """5a. Staleness indicator at 7 days (hourglass)."""
        mock_date.today.return_value = date(2026, 4, 23)
        mock_date.side_effect = lambda *a, **kw: date(*a, **kw)

        cpr = _make_classified(age_days=7)
        result = format_message([cpr], ["osac-project/fulfillment-service"])
        self.assertIn(":hourglass:", result)
        self.assertNotIn(":rotating_light:", result)

    @patch("formatter.date")
    def test_staleness_14_days(self, mock_date):
        """5b. Staleness indicator at 14 days (rotating_light)."""
        mock_date.today.return_value = date(2026, 4, 23)
        mock_date.side_effect = lambda *a, **kw: date(*a, **kw)

        cpr = _make_classified(age_days=14)
        result = format_message([cpr], ["osac-project/fulfillment-service"])
        self.assertIn(":rotating_light:", result)
        self.assertNotIn(":hourglass:", result)

    @patch("formatter.date")
    def test_changes_requested_shows_reviewer(self, mock_date):
        """6. Changes requested shows reviewer name."""
        mock_date.today.return_value = date(2026, 4, 23)
        mock_date.side_effect = lambda *a, **kw: date(*a, **kw)

        cpr = _make_classified(
            status=PRStatus.CHANGES_REQUESTED,
            reviewer_name="carol",
        )
        result = format_message([cpr], ["osac-project/fulfillment-service"])
        self.assertIn("changes requested by carol", result)

    @patch("formatter.date")
    def test_summary_stats_header(self, mock_date):
        """7. Summary stats header has correct counts."""
        mock_date.today.return_value = date(2026, 4, 23)
        mock_date.side_effect = lambda *a, **kw: date(*a, **kw)

        prs = [
            _make_classified(
                status=PRStatus.NEEDS_REVIEW,
                age_days=2,
                repo="osac-project/fulfillment-service",
            ),
            _make_classified(
                status=PRStatus.APPROVED,
                age_days=8,
                repo="osac-project/fulfillment-service",
            ),
            _make_classified(
                status=PRStatus.NEEDS_REVIEW,
                age_days=15,
                repo="osac-project/osac-operator",
            ),
        ]
        result = format_message(
            prs, ["osac-project/fulfillment-service", "osac-project/osac-operator"]
        )

        # 3 open across 2 repos | 2 need review | 2 stale (7+ days)
        self.assertIn("3 open across 2 repos", result)
        self.assertIn("2 need review", result)
        self.assertIn("2 stale (7+ days)", result)

    @patch("formatter.date")
    def test_message_truncation(self, mock_date):
        """8. Message truncation when exceeding length limit."""
        mock_date.today.return_value = date(2026, 4, 23)
        mock_date.side_effect = lambda *a, **kw: date(*a, **kw)

        # Create many PRs with long titles to exceed 3900 chars.
        long_title = "A" * 120
        prs = [
            _make_classified(
                title=f"{long_title} #{i}",
                url=f"https://github.com/osac-project/fulfillment-service/pull/{i}",
            )
            for i in range(40)
        ]
        result = format_message(prs, ["osac-project/fulfillment-service"])

        self.assertLessEqual(len(result), 3900 + 100)  # Allow for suffix
        self.assertIn("... and", result)
        self.assertIn("more PRs", result)

    @patch("formatter.date")
    def test_repos_with_no_prs_omitted(self, mock_date):
        """9. Repos with no PRs are omitted from output."""
        mock_date.today.return_value = date(2026, 4, 23)
        mock_date.side_effect = lambda *a, **kw: date(*a, **kw)

        cpr = _make_classified(repo="osac-project/fulfillment-service")
        result = format_message(
            [cpr],
            ["osac-project/fulfillment-service", "osac-project/osac-operator"],
        )

        self.assertIn("*osac-project/fulfillment-service*", result)
        self.assertNotIn("osac-operator", result)


if __name__ == "__main__":
    unittest.main()
