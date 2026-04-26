# pr-notify

A daily PR status notifier for OSAC repositories. It fetches all open pull requests from configured GitHub repos via GraphQL, classifies each PR by review state (needs review, changes requested, approved, CI failing, draft), formats a summary in Slack mrkdwn, and posts it to a Slack channel. Stale PRs are flagged with age warnings at 3, 7, and 14 days.

## Quick Start

```bash
# Dry run -- prints the formatted message to stdout without posting to Slack
python3 main.py --config config.toml --dry-run
```

## Configuration

The tool reads a TOML config file. All fields are required unless noted.

| Field | Type | Description |
|---|---|---|
| `repos` | list of strings | GitHub repositories to monitor, in `owner/repo` format |
| `slack_channel` | string | Slack channel ID to post to (e.g. `C08ESMFV85Q`) |
| `slack_creds_dir` | string | Directory containing Slack credential files (supports `~` expansion) |

Example config:

```toml
repos = [
    "osac-project/fulfillment-service",
    "osac-project/osac-operator",
]

slack_channel = "C08ESMFV85Q"
slack_creds_dir = "~/.config/slack/"
```

## Slack Credentials

The tool uses xoxc token + browser cookie authentication (the same pattern used by `daily-status`).

**Directory layout:**

```
~/.config/slack/
├── xoxc_token    # Slack xoxc token (starts with "xoxc-...")
└── d_cookie      # Browser "d" cookie value
```

**Automatic extraction (recommended):**

Use [slack-creds-extractor](https://github.com/tzvatot/slack-creds-extractor) — a Chrome extension that extracts the tokens automatically and saves them to `~/.config/slack/` via native messaging. It also auto-refreshes every 6 hours.

**Manual extraction:**

1. Open Slack in your browser and log in to your workspace.
2. Open browser DevTools (F12) > Network tab.
3. Send any message or reload the page.
4. Find a request to `https://edgeapi.slack.com/` or `https://slack.com/api/`.
5. From the request headers:
   - Copy the `token` form parameter -- this is your `xoxc_token`.
   - Copy the `d` value from the `Cookie` header -- this is your `d_cookie`.
6. Save each value (plain text, no trailing newline) to the corresponding file.

**Refreshing tokens:**

Tokens expire periodically. When you see an auth error in the logs (`invalid_auth`, `token_revoked`, or `not_authed`), either rely on the Chrome extension's auto-refresh or repeat the manual steps above.

## systemd Installation

Install as a user service for autonomous daily runs.

**Note:** `pr-notify.service` assumes the repo is cloned at `~/work/src/github/osac-workspace`. If your checkout is elsewhere, edit the `ExecStart`, `WorkingDirectory`, and `--config` paths in the service file before copying.

```bash
# Copy unit files (edit pr-notify.service first if paths differ)
cp pr-notify.service pr-notify.timer ~/.config/systemd/user/

# Reload systemd and enable the timer
systemctl --user daemon-reload
systemctl --user enable --now pr-notify.timer
```

## Verify

```bash
# Check timer is active and shows next trigger time
systemctl --user status pr-notify.timer

# Run the service manually to test
systemctl --user start pr-notify.service

# Check service result
systemctl --user status pr-notify.service
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
