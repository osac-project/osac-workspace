import json
import logging
import subprocess

from models import PRData

logger = logging.getLogger(__name__)


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
        nodes {{
          title
          url
          author {{ login }}
          createdAt
          isDraft
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
        labels = [l.get("name", "") for l in label_nodes]

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
            )
        )
    return results


def fetch_open_prs(repos: list[str]) -> list[PRData]:
    """Fetch all open PRs from the given repos via a single GraphQL call.

    Args:
        repos: List of "owner/name" repository identifiers.

    Returns:
        List of PRData for all open PRs across all repos.

    Raises:
        SystemExit: If the gh CLI call fails entirely.
    """
    query = _build_graphql_query(repos)
    logger.debug("GraphQL query:\n%s", query)

    result = subprocess.run(
        ["gh", "api", "graphql", "-f", f"query={query}"],
        capture_output=True,
        text=True,
    )

    # gh CLI returns non-zero on GraphQL errors but may still include
    # partial data in stdout (e.g., one repo not found but others succeed).
    # Try to parse JSON first before treating as a hard failure.
    try:
        response = json.loads(result.stdout)
    except (json.JSONDecodeError, ValueError):
        if result.returncode != 0:
            error_msg = result.stderr.strip() or result.stdout.strip()
            raise SystemExit(f"GitHub GraphQL query failed: {error_msg}")
        raise SystemExit(f"Failed to parse GitHub API response (empty output)")

    # Handle GraphQL-level errors (partial or full)
    if "errors" in response:
        for err in response["errors"]:
            logger.warning("GraphQL error: %s", err.get("message", err))

    data = response.get("data", {})
    if not data:
        logger.warning("No data in GraphQL response")
        return []

    all_prs: list[PRData] = []
    for idx, repo in enumerate(repos):
        alias = f"repo_{idx}"
        repo_data = data.get(alias)
        if repo_data is None:
            logger.warning("No data returned for repo '%s' (alias %s)", repo, alias)
            continue

        repo_name = repo_data.get("nameWithOwner", repo)
        pr_nodes = repo_data.get("pullRequests", {}).get("nodes", [])
        all_prs.extend(_parse_pr_nodes(repo_name, pr_nodes))

    return all_prs
