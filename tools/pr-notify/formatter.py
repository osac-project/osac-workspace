"""Slack mrkdwn formatter for classified PRs.

Converts a list of ClassifiedPR into a Slack-ready mrkdwn message,
grouped by repository with summary stats and staleness indicators.
"""

from datetime import date

from models import ClassifiedPR, PRStatus

# Maximum PRs shown per repo before collapsing.
_MAX_PRS_PER_REPO = 6

# Emoji mapping for each PR status.
_STATUS_EMOJI: dict[PRStatus, str] = {
    PRStatus.NEEDS_REVIEW: ":eyes:",
    PRStatus.NEEDS_RE_REVIEW: ":warning:",
    PRStatus.CHANGES_REQUESTED: ":red_circle:",
    PRStatus.CI_FAILING: ":x:",
}

# Human-readable labels for each status.
_STATUS_LABEL: dict[PRStatus, str] = {
    PRStatus.NEEDS_REVIEW: "needs review",
    PRStatus.NEEDS_RE_REVIEW: "needs re-review",
    PRStatus.CHANGES_REQUESTED: "changes requested",
    PRStatus.CI_FAILING: "CI failing",
}


def _staleness_indicator(age_days: int) -> str:
    """Return a staleness emoji suffix based on PR age."""
    if age_days >= 14:
        return " :rotating_light:"
    if age_days >= 7:
        return " :hourglass:"
    return ""


def _format_pr_line(cpr: ClassifiedPR) -> str:
    """Format a single classified PR as a Slack mrkdwn line."""
    emoji = _STATUS_EMOJI[cpr.status]
    label = _STATUS_LABEL[cpr.status]

    # Append reviewer name for CHANGES_REQUESTED.
    if cpr.status == PRStatus.CHANGES_REQUESTED and cpr.reviewer_name:
        label = f"changes requested by {cpr.reviewer_name}"

    stale = _staleness_indicator(cpr.age_days)

    return f"  {emoji} <{cpr.pr.url}|{cpr.pr.title}> — {cpr.pr.author} · {cpr.age_days}d · {label}{stale}"


def format_message(classified_prs: list[ClassifiedPR], repos: list[str]) -> str:
    """Format classified PRs into a Slack mrkdwn message.

    Args:
        classified_prs: List of classified PRs to format.
        repos: Full list of monitored repos (used for empty-state count).

    Returns:
        Slack mrkdwn string ready for posting.
    """
    classified_prs = [
        cpr for cpr in classified_prs
        if cpr.status not in (PRStatus.DRAFT, PRStatus.APPROVED)
    ]

    if not classified_prs:
        return f"All clear — no open PRs across {len(repos)} repos :tada:"

    # Group PRs by repo, preserving repo order from the list.
    prs_by_repo: dict[str, list[ClassifiedPR]] = {}
    for cpr in classified_prs:
        prs_by_repo.setdefault(cpr.pr.repo, []).append(cpr)

    # Compute summary stats.
    total = len(classified_prs)
    repos_with_prs = len(prs_by_repo)
    needs_review = sum(
        1 for cpr in classified_prs if cpr.status == PRStatus.NEEDS_REVIEW
    )
    stale = sum(1 for cpr in classified_prs if cpr.age_days >= 7)

    today = date.today().strftime("%Y-%m-%d")
    header = f"*PR Status Summary* — {today}\n"
    header += f"{total} open across {repos_with_prs} repos | {needs_review} need review | {stale} stale (7+ days)"

    # Build per-repo sections with per-repo cap.
    sections: list[str] = []
    for repo, prs in prs_by_repo.items():
        pulls_url = f"https://github.com/{repo}/pulls"
        repo_header = f"\n*<{pulls_url}|{repo}>* ({len(prs)})"
        shown = prs[:_MAX_PRS_PER_REPO]
        lines = [_format_pr_line(cpr) for cpr in shown]
        remaining = len(prs) - len(shown)
        if remaining > 0:
            lines.append(f"  _<{pulls_url}|... and {remaining} more>_")
        sections.append(repo_header + "\n" + "\n".join(lines))

    return header + "\n" + "\n".join(sections)
