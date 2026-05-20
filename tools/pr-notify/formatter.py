"""Formatters for classified PRs: Slack mrkdwn and HTML dashboard."""

import html
from datetime import date, datetime, timezone

from models import ClassifiedPR, PRStatus

# Maximum PRs shown per repo before collapsing.
_MAX_PRS_PER_REPO = 6

_MAX_MESSAGE_LENGTH = 3900

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
        reviewer_link = f"<https://github.com/{cpr.reviewer_name}|{cpr.reviewer_name}>"
        label = f"changes requested by {reviewer_link}"

    stale = _staleness_indicator(cpr.age_days)
    author_link = f"<https://github.com/{cpr.pr.author}|{cpr.pr.author}>"

    return f"  {emoji} <{cpr.pr.url}|{cpr.pr.title}> — {author_link} · {cpr.age_days}d · {label}{stale}"


_REVIEWABLE_STATUSES = frozenset(
    {PRStatus.NEEDS_REVIEW, PRStatus.NEEDS_RE_REVIEW, PRStatus.CHANGES_REQUESTED}
)


def format_message(classified_prs: list[ClassifiedPR], repos: list[str]) -> str:
    """Format classified PRs into a Slack mrkdwn message.

    Only reviewable PRs (needs review, needs re-review, changes requested) are
    listed individually.  CI-failing, draft, and approved PRs are summarized in
    a single footer line so the message stays focused on what the team can act on.

    Args:
        classified_prs: List of classified PRs to format.
        repos: Full list of monitored repos (used for empty-state count).

    Returns:
        Slack mrkdwn string ready for posting.
    """
    actionable = [
        cpr for cpr in classified_prs
        if cpr.status not in (PRStatus.DRAFT, PRStatus.APPROVED)
    ]
    reviewable = [cpr for cpr in actionable if cpr.status in _REVIEWABLE_STATUSES]
    ci_failing = [cpr for cpr in actionable if cpr.status == PRStatus.CI_FAILING]

    if not reviewable and not ci_failing:
        return f"All clear — no open PRs across {len(repos)} repos :tada:"

    # Group reviewable PRs by repo.
    prs_by_repo: dict[str, list[ClassifiedPR]] = {}
    for cpr in reviewable:
        prs_by_repo.setdefault(cpr.pr.repo, []).append(cpr)

    # Compute summary stats.
    needs_review = sum(
        1 for cpr in reviewable if cpr.status == PRStatus.NEEDS_REVIEW
    )
    stale = sum(1 for cpr in reviewable if cpr.age_days >= 7)

    today = date.today().strftime("%Y-%m-%d")
    header = f"*PR Status Summary* — {today}\n"
    header += f"{len(reviewable)} ready for review across {len(prs_by_repo)} repos"
    if needs_review:
        header += f" | {needs_review} need review"
    if stale:
        header += f" | {stale} stale (7+ days)"

    if not reviewable:
        n = len(ci_failing)
        footer = f"\n:x: {n} PR{'s' if n != 1 else ''} with CI failures (author action needed)"
        return header + footer

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

    if ci_failing:
        n = len(ci_failing)
        sections.append(
            f"\n:x: {n} PR{'s' if n != 1 else ''} with CI failures (author action needed)"
        )

    message = header + "\n" + "\n".join(sections)

    if len(message) > _MAX_MESSAGE_LENGTH:
        while sections and len(message) > _MAX_MESSAGE_LENGTH:
            sections.pop()
            message = header + "\n" + "\n".join(sections)
            message += "\n_... additional repos truncated_"

    return message


# ---------------------------------------------------------------------------
# Compact Slack summary (for dashboard mode)
# ---------------------------------------------------------------------------

def format_compact_summary(
    classified_prs: list[ClassifiedPR],
    repos: list[str],
    dashboard_url: str,
) -> str:
    actionable = [
        cpr for cpr in classified_prs
        if cpr.status not in (PRStatus.DRAFT, PRStatus.APPROVED)
    ]
    reviewable = [cpr for cpr in actionable if cpr.status in _REVIEWABLE_STATUSES]
    ci_failing = [cpr for cpr in actionable if cpr.status == PRStatus.CI_FAILING]
    stale = sum(1 for cpr in reviewable if cpr.age_days >= 7)

    if not reviewable and not ci_failing:
        return (
            f"All clear — no actionable PRs across {len(repos)} repos :tada:\n"
            f":chart_with_upwards_trend: <{dashboard_url}|Full PR Dashboard>"
        )

    parts = []
    if reviewable:
        parts.append(f"{len(reviewable)} need review")
    if ci_failing:
        parts.append(f"{len(ci_failing)} CI failing")
    if stale:
        parts.append(f"{stale} stale (7+ days)")

    today = date.today().strftime("%Y-%m-%d")
    summary = f"*PR Status* — {today} | " + " · ".join(parts)
    summary += f"\n:chart_with_upwards_trend: <{dashboard_url}|Full PR Dashboard>"
    return summary


# ---------------------------------------------------------------------------
# HTML dashboard
# ---------------------------------------------------------------------------

_CONCLUSION_STYLE: dict[str | None, tuple[str, str]] = {
    "SUCCESS": ("#3e8635", "Pass"),
    "FAILURE": ("#c9190b", "Fail"),
    "NEUTRAL": ("#6a6e73", "Neutral"),
    "SKIPPED": ("#6a6e73", "Skip"),
    "CANCELLED": ("#6a6e73", "Cancel"),
    "TIMED_OUT": ("#c9190b", "Timeout"),
    "ACTION_REQUIRED": ("#f0ab00", "Action"),
    None: ("#6a6e73", "Pending"),
}

_STATUS_COLOR: dict[PRStatus, str] = {
    PRStatus.NEEDS_REVIEW: "#f0ab00",
    PRStatus.NEEDS_RE_REVIEW: "#f0ab00",
    PRStatus.CHANGES_REQUESTED: "#c9190b",
    PRStatus.CI_FAILING: "#c9190b",
    PRStatus.APPROVED: "#3e8635",
    PRStatus.DRAFT: "#6a6e73",
}


def _status_badge(status: PRStatus) -> str:
    color = _STATUS_COLOR.get(status, "#6a6e73")
    label = _STATUS_LABEL.get(status, status.value)
    return f'<span class="badge" style="background:{color}">{html.escape(label)}</span>'


def _check_run_rows(cpr: ClassifiedPR) -> str:
    if not cpr.pr.check_runs:
        return '<tr><td colspan="3" class="muted">No check data</td></tr>'
    rows = []
    for cr in cpr.pr.check_runs:
        color, label = _CONCLUSION_STYLE.get(
            cr.conclusion, _CONCLUSION_STYLE[None]
        )
        name = html.escape(cr.name)
        if cr.details_url:
            name = f'<a href="{html.escape(cr.details_url)}">{name}</a>'
        rows.append(
            f'<tr><td>{name}</td>'
            f'<td style="color:{color};font-weight:600">{label}</td></tr>'
        )
    return "\n".join(rows)


def format_html_dashboard(
    classified_prs: list[ClassifiedPR], repos: list[str]
) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    today = date.today().strftime("%Y-%m-%d")

    actionable = [
        cpr for cpr in classified_prs
        if cpr.status not in (PRStatus.DRAFT, PRStatus.APPROVED)
    ]
    reviewable = [cpr for cpr in actionable if cpr.status in _REVIEWABLE_STATUSES]
    ci_failing = [cpr for cpr in actionable if cpr.status == PRStatus.CI_FAILING]
    approved = [cpr for cpr in classified_prs if cpr.status == PRStatus.APPROVED]
    drafts = [cpr for cpr in classified_prs if cpr.status == PRStatus.DRAFT]
    stale = [cpr for cpr in reviewable if cpr.age_days >= 7]

    cards = [
        ("Needs Review", len(reviewable), "#f0ab00"),
        ("CI Failing", len(ci_failing), "#c9190b"),
        ("Stale (7+ days)", len(stale), "#6a6e73"),
        ("Approved", len(approved), "#3e8635"),
        ("Draft", len(drafts), "#6a6e73"),
    ]
    cards_html = "\n".join(
        f'<div class="card" style="border-top:4px solid {c}">'
        f'<div class="card-num">{n}</div><div class="card-label">{l}</div></div>'
        for l, n, c in cards
    )

    prs_by_repo: dict[str, list[ClassifiedPR]] = {}
    for cpr in classified_prs:
        if cpr.status in (PRStatus.DRAFT, PRStatus.APPROVED):
            continue
        prs_by_repo.setdefault(cpr.pr.repo, []).append(cpr)

    repo_sections = []
    for repo_name in sorted(prs_by_repo):
        prs = prs_by_repo[repo_name]
        pulls_url = f"https://github.com/{repo_name}/pulls"
        rows = []
        for cpr in prs:
            age_class = "age-stale" if cpr.age_days >= 7 else ""
            checks_html = _check_run_rows(cpr)
            rows.append(f"""<tr>
<td>{_status_badge(cpr.status)}</td>
<td><a href="{html.escape(cpr.pr.url)}">{html.escape(cpr.pr.title)}</a></td>
<td><a href="https://github.com/{html.escape(cpr.pr.author)}">{html.escape(cpr.pr.author)}</a></td>
<td class="{age_class}">{cpr.age_days}d</td>
<td><details><summary>checks</summary><table class="checks">{checks_html}</table></details></td>
</tr>""")

        repo_sections.append(f"""
<section>
<h2><a href="{pulls_url}">{html.escape(repo_name)}</a> ({len(prs)})</h2>
<table class="pr-table">
<thead><tr><th>Status</th><th>Title</th><th>Author</th><th>Age</th><th>CI</th></tr></thead>
<tbody>{"".join(rows)}</tbody>
</table>
</section>""")

    ci_summary_rows = []
    for repo_name in sorted(set(cpr.pr.repo for cpr in classified_prs)):
        repo_prs = [cpr for cpr in classified_prs if cpr.pr.repo == repo_name]
        all_checks = [
            cr for cpr in repo_prs for cr in cpr.pr.check_runs
        ]
        if not all_checks:
            continue
        passed = sum(1 for cr in all_checks if cr.conclusion == "SUCCESS")
        total = len(all_checks)
        pct = int(passed / total * 100) if total else 0
        bar_color = "#3e8635" if pct >= 80 else "#f0ab00" if pct >= 50 else "#c9190b"
        ci_summary_rows.append(
            f'<tr><td>{html.escape(repo_name)}</td><td>{total}</td>'
            f'<td><div class="bar-bg"><div class="bar" style="width:{pct}%;background:{bar_color}"></div></div>'
            f'{pct}%</td></tr>'
        )

    ci_section = ""
    if ci_summary_rows:
        ci_section = f"""
<section>
<h2>CI Health</h2>
<table class="pr-table">
<thead><tr><th>Repo</th><th>Checks</th><th>Pass Rate</th></tr></thead>
<tbody>{"".join(ci_summary_rows)}</tbody>
</table>
</section>"""

    no_actionable = ""
    if not prs_by_repo:
        no_actionable = '<p class="all-clear">All clear — no actionable PRs</p>'

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OSAC PR Dashboard — {today}</title>
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:"Red Hat Display",system-ui,sans-serif;background:#f5f5f5;color:#151515;line-height:1.5}}
.container{{max-width:960px;margin:0 auto;padding:24px 16px}}
header{{margin-bottom:24px}}
header h1{{font-size:1.5rem;color:#151515}}
header .updated{{color:#6a6e73;font-size:.85rem}}
.cards{{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:32px}}
.card{{background:#fff;border-radius:8px;padding:16px 20px;min-width:120px;flex:1;box-shadow:0 1px 3px rgba(0,0,0,.1)}}
.card-num{{font-size:1.8rem;font-weight:700}}
.card-label{{font-size:.85rem;color:#6a6e73}}
section{{margin-bottom:32px}}
h2{{font-size:1.15rem;margin-bottom:12px}}
h2 a{{color:#151515;text-decoration:none}}
h2 a:hover{{text-decoration:underline}}
.pr-table{{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.1)}}
.pr-table th{{text-align:left;padding:10px 12px;background:#f0f0f0;font-size:.8rem;text-transform:uppercase;color:#6a6e73}}
.pr-table td{{padding:10px 12px;border-top:1px solid #eee;font-size:.9rem;vertical-align:top}}
.pr-table td a{{color:#06c;text-decoration:none}}
.pr-table td a:hover{{text-decoration:underline}}
.badge{{display:inline-block;padding:2px 8px;border-radius:12px;color:#fff;font-size:.75rem;white-space:nowrap}}
.age-stale{{color:#c9190b;font-weight:700}}
details summary{{cursor:pointer;color:#06c;font-size:.85rem}}
.checks{{margin-top:6px;font-size:.8rem;border-collapse:collapse}}
.checks td{{padding:3px 8px;border:none}}
.muted{{color:#6a6e73;font-style:italic}}
.bar-bg{{display:inline-block;width:100px;height:10px;background:#eee;border-radius:5px;vertical-align:middle;margin-right:6px}}
.bar{{height:100%;border-radius:5px}}
.all-clear{{text-align:center;color:#3e8635;font-size:1.2rem;padding:40px 0}}
footer{{text-align:center;color:#6a6e73;font-size:.8rem;margin-top:40px;padding-top:16px;border-top:1px solid #ddd}}
</style>
</head>
<body>
<div class="container">
<header>
<h1>OSAC PR Dashboard</h1>
<div class="updated">Last updated: {now}</div>
</header>
<div class="cards">{cards_html}</div>
{no_actionable}
{"".join(repo_sections)}
{ci_section}
<footer>Generated by pr-notify · {now}</footer>
</div>
</body>
</html>"""
