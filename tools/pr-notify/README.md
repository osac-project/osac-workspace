# pr-notify

Daily PR status monitor for OSAC repositories. Fetches open PRs from GitHub, classifies them by review/CI state, publishes an interactive dashboard to GitHub Pages, and posts a compact summary to Slack.

## How it works

```
Systemd timer (weekday 09:00 UTC)
  -> Fetch open PRs via GitHub GraphQL API
  -> Classify each PR (needs review, CI failing, stale, approved, draft)
  -> Generate data.json with all PR data
  -> Push data.json to osac-workspace via PR (auto-merged)
  -> GitHub Pages serves updated dashboard
  -> Post compact Slack summary with dashboard link
```

### Data/presentation separation

The dashboard is split into two parts:

- **Static HTML** (`docs/pr-dashboard/index.html`) - committed once, renders the dashboard client-side by fetching `data.json`. Only changes when the dashboard design is updated.
- **Data file** (`docs/pr-dashboard/data.json`) - updated daily by the script. Contains all PR statuses, CI health metrics, and timestamps.

This keeps daily PRs small (only the JSON data changes) and makes the dashboard cacheable.

### Publishing flow

1. Script creates (or reuses) a `dashboard-data` branch on `osac-project/osac-workspace`
2. Uploads the new `data.json` via GitHub Contents API
3. Opens a PR if one doesn't already exist
4. Merges the PR using admin privileges (`--admin` flag bypasses the required review)
5. GitHub Pages serves the updated dashboard from `docs/` on `main`

### PR classification

Each PR is assigned one status (highest priority wins):

| Priority | Status | Meaning |
|----------|--------|---------|
| 1 | Draft | PR is marked as draft |
| 2 | CI Failing | Last commit has failing checks |
| 3 | Changes Requested | A reviewer requested changes |
| 4 | Needs Re-review | New commits pushed after approval |
| 5 | Approved | All reviewers approved |
| 6 | Needs Review | No meaningful reviews yet |

PRs older than 7 days are flagged as stale; 14+ days as critical.

## Modes

### Dashboard mode (default for the timer)

```bash
python main.py --config config.toml --mode dashboard
```

Generates `data.json`, publishes it via PR, and posts a compact Slack summary with a link to the dashboard.

### Slack mode

```bash
python main.py --config config.toml --mode slack
```

Posts a full per-repo PR breakdown directly to Slack (no dashboard involved).

### Dry run

Add `--dry-run` to either mode to print output to stdout without publishing or posting:

```bash
python main.py --config config.toml --mode dashboard --dry-run
```

## Configuration

Copy `config.example.toml` to `config.toml` and edit:

```toml
repos = [
    "osac-project/fulfillment-service",
    "osac-project/osac-operator",
    "osac-project/osac-aap",
    "osac-project/enhancement-proposals",
]

slack_channel = "C08ESMFV85Q"
slack_creds_dir = "~/.config/slack/"

[dashboard]
repo = "osac-project/osac-workspace"
branch = "main"
base_url = "https://osac-project.github.io/osac-workspace/pr-dashboard"
data_path = "docs/pr-dashboard/data.json"
```

| Field | Description |
|-------|-------------|
| `repos` | GitHub repos to monitor (`owner/name` format) |
| `slack_channel` | Slack channel ID for posting |
| `slack_creds_dir` | Directory containing `xoxc_token` and `d_cookie` files |
| `dashboard.repo` | Target repo for dashboard data PRs |
| `dashboard.branch` | Base branch for PRs (usually `main`) |
| `dashboard.base_url` | GitHub Pages URL for the dashboard |
| `dashboard.data_path` | Path to `data.json` within the repo |

## Slack credentials

The tool uses xoxc token + browser cookie authentication (the same pattern used by `daily-status`).

**Directory layout:**

```
~/.config/slack/
├── xoxc_token    # Slack xoxc token (starts with "xoxc-...")
└── d_cookie      # Browser "d" cookie value
```

**Automatic extraction (recommended):**

Use [slack-creds-extractor](https://github.com/tzvatot/slack-creds-extractor) - a Chrome extension that extracts the tokens automatically and saves them to `~/.config/slack/` via native messaging. It also auto-refreshes every 6 hours.

**Manual extraction:**

1. Open Slack in your browser and log in to your workspace.
2. Open browser DevTools (F12) > Network tab.
3. Send any message or reload the page.
4. Find a request to `https://edgeapi.slack.com/` or `https://slack.com/api/`.
5. From the request headers:
   - Copy the `token` form parameter - this is your `xoxc_token`.
   - Copy the `d` value from the `Cookie` header - this is your `d_cookie`.
6. Save each value (plain text, no trailing newline) to the corresponding file.

Tokens expire periodically. When you see an auth error in the logs (`invalid_auth`, `token_revoked`, or `not_authed`), either rely on the Chrome extension's auto-refresh or repeat the manual steps above.

## Prerequisites

- Python 3.11+
- `gh` CLI authenticated with access to the monitored repos (and write access to the dashboard repo)
- Slack credentials in `~/.config/slack/`

## systemd installation

Install as a user service for autonomous daily runs.

**Note:** `pr-notify.service` assumes the repo is cloned at `~/work/src/github/osac-workspace`. If your checkout is elsewhere, edit the `ExecStart`, `WorkingDirectory`, and `--config` paths in the service file before copying.

```bash
cp pr-notify.service pr-notify.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now pr-notify.timer
```

Check status:

```bash
systemctl --user status pr-notify.timer
journalctl --user -u pr-notify.service --since today
```

## GitHub Pages setup

Enable GitHub Pages on `osac-project/osac-workspace`:

1. Go to Settings > Pages
2. Source: "Deploy from a branch"
3. Branch: `main`, Folder: `/docs`

The dashboard will be available at `https://osac-project.github.io/osac-workspace/pr-dashboard/`.

## Tests

```bash
python -m pytest -v
```

## Logs

Each run appends to a dated log file:

```
/tmp/pr-notify-YYYY-MM-DD.log
```

View today's log:

```bash
cat /tmp/pr-notify-$(date -u +%Y-%m-%d).log
```

Logs are also written to stderr, so `journalctl` captures them too:

```bash
journalctl --user -u pr-notify.service --since today
```

## Project structure

```
tools/pr-notify/
  main.py              # Entry point and CLI
  github.py            # GitHub GraphQL PR fetcher
  classifier.py        # PR status classification engine
  data_formatter.py    # JSON data generator for the dashboard
  formatter.py         # Slack message formatters
  publisher.py         # PR-based data publisher (branch, PR, merge)
  slack.py             # Slack API client
  config.py            # TOML config loader
  models.py            # Data models (PRData, ClassifiedPR, Config)
  config.example.toml  # Config template
  pr-notify.service    # Systemd service unit
  pr-notify.timer      # Systemd timer unit

docs/pr-dashboard/
  index.html           # Static dashboard (fetches data.json client-side)
  data.json            # PR data (updated daily by the script)
```
