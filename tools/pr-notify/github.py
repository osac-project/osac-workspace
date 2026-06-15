import json
import logging
import subprocess
import time

from models import CheckRun, PRData

logger = logging.getLogger(__name__)

INITIAL_BACKOFF_SECONDS = 2
MAX_RETRIES = 3
DELAY_BETWEEN_QUERIES_SECONDS = 1


def _build_graphql_query(repos: list[str]) -> str:
    """Build a single GraphQL query fetching open PRs from multiple repos.

    Each repo gets an aliased sub-query (repo_0, repo_1, etc.) so all data
    comes back in one API call.
    """
    repo_fragments = []
    for idx, repo in enumerate(repos):
        owner, name = repo.split("/", 1)
        alias = f"repo_{idx}"
        repo_fragments.append(f"""
    {alias}: repository(owner: "{owner}", name: "{name}") {{
      nameWithOwner
      pullRequests(states: OPEN, first: 50) {{
        totalCount
        pageInfo {{ hasNextPage }}
        nodes {{
          title
          url
          author {{ login }}
          createdAt
          isDraft
          mergeable
          labels(first: 20) {{ nodes {{ name }} }}
          reviews(last: 20) {{
            nodes {{
              author {{ login }}
              state
              submittedAt
            }}
          }}
          reviewRequests(first: 10) {{
            nodes {{
              requestedReviewer {{
                ... on User {{ login }}
              }}
            }}
          }}
          commits(last: 1) {{
            nodes {{
              commit {{
                committedDate
                statusCheckRollup {{
                  state
                }}
                checkSuites(first: 10) {{
                  pageInfo {{ hasNextPage }}
                  nodes {{
                    checkRuns(first: 20) {{
                      pageInfo {{ hasNextPage }}
                      nodes {{
                        name
                        conclusion
                        detailsUrl
                      }}
                    }}
                  }}
                }}
              }}
            }}
          }}
        }}
      }}
    }}""")

    return "{\n" + "\n".join(repo_fragments) + "\n}"


def _parse_pr_nodes(repo_name: str, pr_nodes: list[dict]) -> list[PRData]:
    """Convert raw GraphQL PR nodes into PRData dataclass instances."""
    results = []
    for pr in pr_nodes:
        # Extract last commit info
        commit_nodes = pr.get("commits", {}).get("nodes", [])
        last_commit = commit_nodes[0]["commit"] if commit_nodes else {}
        last_commit_date = last_commit.get("committedDate", "")

        # CI status from statusCheckRollup
        rollup = last_commit.get("statusCheckRollup")
        ci_status = rollup.get("state") if rollup else None

        # Individual check runs
        check_suites_data = last_commit.get("checkSuites") or {}
        if check_suites_data.get("pageInfo", {}).get("hasNextPage"):
            logger.warning(
                "PR '%s' has more than 10 check suites; results truncated",
                pr.get("title", ""),
            )
        check_runs = []
        for suite in check_suites_data.get("nodes") or []:
            if suite is None:
                continue
            check_runs_data = suite.get("checkRuns")
            if check_runs_data is None:
                continue
            if check_runs_data.get("pageInfo", {}).get("hasNextPage"):
                logger.warning(
                    "PR '%s' has more than 20 check runs in a suite; results truncated",
                    pr.get("title", ""),
                )
            for run in check_runs_data.get("nodes") or []:
                if run is None:
                    continue
                check_runs.append(CheckRun(
                    name=run.get("name", ""),
                    conclusion=run.get("conclusion"),
                    details_url=run.get("detailsUrl", ""),
                ))

        # Reviews
        review_nodes = pr.get("reviews", {}).get("nodes", [])
        reviews = [
            {
                "author": r.get("author", {}).get("login", "unknown"),
                "state": r.get("state", ""),
                "submitted_at": r.get("submittedAt", ""),
            }
            for r in review_nodes
            if r.get("author")
        ]

        # Review requests
        rr_nodes = pr.get("reviewRequests", {}).get("nodes", [])
        review_requests = [
            rr.get("requestedReviewer", {}).get("login", "")
            for rr in rr_nodes
            if rr.get("requestedReviewer") and rr["requestedReviewer"].get("login")
        ]

        # Labels
        label_nodes = pr.get("labels", {}).get("nodes", [])
        labels = [label.get("name", "") for label in label_nodes]

        author_obj = pr.get("author") or {}
        results.append(
            PRData(
                title=pr.get("title", ""),
                url=pr.get("url", ""),
                author=author_obj.get("login", "ghost"),
                repo=repo_name,
                created_at=pr.get("createdAt", ""),
                is_draft=pr.get("isDraft", False),
                labels=labels,
                reviews=reviews,
                review_requests=review_requests,
                last_commit_date=last_commit_date,
                ci_status=ci_status,
                mergeable=pr.get("mergeable"),
                check_runs=check_runs,
            )
        )
    return results


def _run_graphql_query(query: str) -> dict:
    """Execute a GraphQL query via gh CLI with exponential backoff on rate limits.

    Returns the parsed JSON response data dict.
    Raises SystemExit on auth errors or persistent failures.
    """
    backoff = INITIAL_BACKOFF_SECONDS
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            result = subprocess.run(
                ["gh", "api", "graphql", "-f", f"query={query}"],
                capture_output=True,
                text=True,
                timeout=60,
            )
        except subprocess.TimeoutExpired:
            raise SystemExit("GitHub GraphQL query timed out after 60 seconds")

        try:
            response = json.loads(result.stdout)
        except (json.JSONDecodeError, ValueError):
            if result.returncode != 0:
                error_msg = result.stderr.strip() or result.stdout.strip()
                raise SystemExit(f"GitHub GraphQL query failed: {error_msg}")
            raise SystemExit("Failed to parse GitHub API response (malformed JSON)")

        if "errors" in response:
            is_rate_limit = False
            for err in response["errors"]:
                msg = err.get("message", str(err))
                if any(s in msg.lower() for s in ("auth", "forbidden", "unauthorized")):
                    raise SystemExit(f"GitHub auth error: {msg}")
                if "resource limits" in msg.lower() or "rate limit" in msg.lower():
                    is_rate_limit = True

            if is_rate_limit and attempt < MAX_RETRIES:
                logger.warning(
                    "GraphQL resource limits exceeded (attempt %d/%d), retrying in %ds",
                    attempt, MAX_RETRIES, backoff,
                )
                time.sleep(backoff)
                backoff *= 2
                continue

            for err in response["errors"]:
                logger.warning("GraphQL error: %s", err.get("message", str(err)))

        return response

    return response


def _fetch_repo_prs(repo: str) -> list[PRData]:
    """Fetch open PRs for a single repo with rate-limit handling."""
    query = _build_graphql_query([repo])
    logger.debug("Fetching PRs for %s", repo)

    response = _run_graphql_query(query)

    data = response.get("data", {})
    if not data:
        if "errors" in response:
            logger.warning("GraphQL query for '%s' returned errors with no data, skipping", repo)
            return []
        logger.warning("No data in GraphQL response for '%s'", repo)
        return []

    repo_data = data.get("repo_0")
    if repo_data is None:
        logger.warning("No data returned for repo '%s'", repo)
        return []

    repo_name = repo_data.get("nameWithOwner", repo)
    pr_data = repo_data.get("pullRequests", {})
    total_count = pr_data.get("totalCount", 0)
    has_next = pr_data.get("pageInfo", {}).get("hasNextPage", False)
    if has_next:
        logger.warning(
            "Repo '%s' has %d open PRs but only first 50 were fetched",
            repo_name, total_count,
        )
    pr_nodes = pr_data.get("nodes", [])
    return _parse_pr_nodes(repo_name, pr_nodes)


def fetch_open_prs(repos: list[str]) -> list[PRData]:
    """Fetch all open PRs from the given repos, one repo at a time.

    Queries repos individually to avoid GraphQL resource limits on large
    queries. Adds a small delay between requests to stay under rate limits.

    Args:
        repos: List of "owner/name" repository identifiers.

    Returns:
        List of PRData for all open PRs across all repos.
    """
    all_prs: list[PRData] = []
    for idx, repo in enumerate(repos):
        if idx > 0:
            time.sleep(DELAY_BETWEEN_QUERIES_SECONDS)
        try:
            prs = _fetch_repo_prs(repo)
            all_prs.extend(prs)
        except SystemExit:
            logger.error("Failed to fetch PRs for '%s' (continuing with remaining repos)", repo)
        except Exception:
            logger.error("Unexpected failure while fetching PRs for '%s' (continuing with remaining repos)", repo)

    return all_prs
