import os
import tomllib

from models import Config, DashboardConfig


def load_config(path: str) -> Config:
    """Load and validate a TOML configuration file.

    Args:
        path: Path to the TOML config file.

    Returns:
        A Config dataclass with validated fields.

    Raises:
        SystemExit: On missing file, missing required fields, or parse errors.
    """
    if not os.path.isfile(path):
        raise SystemExit(f"Config file not found: {path}")

    try:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        raise SystemExit(f"Failed to parse TOML config '{path}': {e}")

    required_fields = ["repos", "slack_channel", "slack_creds_dir"]
    for field_name in required_fields:
        if field_name not in data:
            raise SystemExit(
                f"Missing required field '{field_name}' in config '{path}'"
            )

    slack_creds_dir = os.path.expanduser(data["slack_creds_dir"])

    dashboard = None
    if "dashboard" in data:
        d = data["dashboard"]
        if not isinstance(d, dict):
            raise SystemExit(
                f"Field 'dashboard' must be a table in config '{path}'"
            )
        for f in ("repo", "branch", "base_url"):
            if f not in d:
                raise SystemExit(
                    f"Missing required field 'dashboard.{f}' in config '{path}'"
                )
        dashboard = DashboardConfig(
            repo=d["repo"],
            branch=d["branch"],
            base_url=d["base_url"],
        )

    return Config(
        repos=data["repos"],
        slack_channel=data["slack_channel"],
        slack_creds_dir=slack_creds_dir,
        dashboard=dashboard,
    )
