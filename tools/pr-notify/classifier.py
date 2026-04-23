"""PR classification engine.

Assigns one of 6 status states to each PR based on review history,
CI status, and draft flag.
"""

from datetime import datetime, timezone

from models import ClassifiedPR, PRData, PRStatus

# Bot authors whose reviews should be filtered out.
_BOT_AUTHORS = frozenset(
    {
        "ghost",
        "dependabot",
        "dependabot[bot]",
        "renovate",
        "renovate[bot]",
        "github-actions",
        "github-actions[bot]",
        "codecov",
        "codecov[bot]",
        "sonarcloud[bot]",
    }
)


def _parse_iso_date(date_str: str) -> datetime:
    """Parse ISO 8601 date string (GitHub format ending with Z)."""
    clean = date_str.replace("Z", "+00:00")
    return datetime.fromisoformat(clean)


def _latest_review_per_author(reviews: list[dict]) -> dict[str, dict]:
    """Return the latest review per unique author.

    Filters out bot reviews and dismissed reviews. A DISMISSED review
    is treated as if the reviewer has no active review.
    """
    latest: dict[str, dict] = {}
    for review in reviews:
        author = review.get("author", "")
        if not author or author.lower() in _BOT_AUTHORS:
            continue

        submitted = review.get("submitted_at", "")
        if not submitted:
            continue

        existing = latest.get(author)
        if existing is None or submitted > existing["submitted_at"]:
            latest[author] = review

    # Remove authors whose latest review is DISMISSED -- treat as no review.
    return {
        author: rev for author, rev in latest.items() if rev.get("state") != "DISMISSED"
    }


def _classify_single(pr: PRData) -> ClassifiedPR:
    """Classify a single PR according to priority rules."""
    age_days = (datetime.now(timezone.utc) - _parse_iso_date(pr.created_at)).days

    # Priority 1: Draft overrides everything.
    if pr.is_draft:
        return ClassifiedPR(pr=pr, status=PRStatus.DRAFT, age_days=age_days)

    # Priority 2: CI failing overrides review state.
    if pr.ci_status == "FAILURE":
        return ClassifiedPR(pr=pr, status=PRStatus.CI_FAILING, age_days=age_days)

    latest_reviews = _latest_review_per_author(pr.reviews)

    # Priority 3: Any reviewer with CHANGES_REQUESTED blocks.
    for author, review in latest_reviews.items():
        if review.get("state") == "CHANGES_REQUESTED":
            return ClassifiedPR(
                pr=pr,
                status=PRStatus.CHANGES_REQUESTED,
                age_days=age_days,
                reviewer_name=author,
            )

    # Collect approvals for priority 4 and 5 checks.
    approvals = [
        rev for rev in latest_reviews.values() if rev.get("state") == "APPROVED"
    ]

    if approvals:
        # Priority 4: Needs re-review if new commits after latest approval.
        latest_approval_date = max(rev["submitted_at"] for rev in approvals)
        if pr.last_commit_date and pr.last_commit_date > latest_approval_date:
            return ClassifiedPR(
                pr=pr,
                status=PRStatus.NEEDS_RE_REVIEW,
                age_days=age_days,
            )

        # Priority 5: Approved -- all latest reviews are approvals.
        return ClassifiedPR(pr=pr, status=PRStatus.APPROVED, age_days=age_days)

    # Priority 6: No meaningful reviews (none, or only COMMENTED).
    return ClassifiedPR(pr=pr, status=PRStatus.NEEDS_REVIEW, age_days=age_days)


def classify_prs(prs: list[PRData]) -> list[ClassifiedPR]:
    """Classify a list of PRs into status states.

    Classification priority (highest wins):
      1. Draft
      2. CI Failing
      3. Changes Requested
      4. Needs Re-review
      5. Approved
      6. Needs Review
    """
    return [_classify_single(pr) for pr in prs]
