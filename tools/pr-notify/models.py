from dataclasses import dataclass, field
from enum import Enum


class PRStatus(Enum):
    NEEDS_REVIEW = "needs_review"
    NEEDS_RE_REVIEW = "needs_re_review"
    CHANGES_REQUESTED = "changes_requested"
    APPROVED = "approved"
    CI_FAILING = "ci_failing"
    DRAFT = "draft"


@dataclass
class Config:
    repos: list[str]
    slack_channel: str
    slack_creds_dir: str
    stale_days: list[int] = field(default_factory=lambda: [3, 7, 14])


@dataclass
class PRData:
    title: str
    url: str
    author: str
    repo: str
    created_at: str
    is_draft: bool
    labels: list[str]
    reviews: list[dict]
    review_requests: list[str]
    last_commit_date: str
    ci_status: str | None


@dataclass
class ClassifiedPR:
    pr: PRData
    status: PRStatus
    age_days: int
    reviewer_name: str | None = None
