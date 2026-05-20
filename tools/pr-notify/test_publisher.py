"""Unit tests for the GitHub Pages publisher."""

import base64
import json
import unittest
from unittest.mock import MagicMock, patch

from models import DashboardConfig
from publisher import publish_dashboard


def _make_config(**overrides) -> DashboardConfig:
    defaults = {
        "repo": "testuser/testrepo",
        "branch": "gh-pages",
        "base_url": "https://testuser.github.io/testrepo",
    }
    defaults.update(overrides)
    return DashboardConfig(**defaults)


class TestPublisher(unittest.TestCase):

    @patch("publisher.subprocess.run")
    def test_publish_returns_url(self, mock_run: MagicMock):
        mock_run.return_value = MagicMock(
            returncode=0, stdout="", stderr=""
        )
        config = _make_config()
        url = publish_dashboard("<html>hello</html>", config)
        self.assertEqual(url, "https://testuser.github.io/testrepo/")

    @patch("publisher.subprocess.run")
    def test_publish_calls_gh_api_put(self, mock_run: MagicMock):
        mock_run.return_value = MagicMock(
            returncode=0, stdout="", stderr=""
        )
        config = _make_config()
        publish_dashboard("<html>test</html>", config)

        put_calls = [
            c for c in mock_run.call_args_list
            if "--method" in str(c) and "PUT" in str(c)
        ]
        self.assertTrue(len(put_calls) >= 1)

    @patch("publisher.subprocess.run")
    def test_publish_base64_encodes_content(self, mock_run: MagicMock):
        mock_run.return_value = MagicMock(
            returncode=0, stdout="", stderr=""
        )
        config = _make_config()
        html = "<html><body>dashboard</body></html>"
        publish_dashboard(html, config)

        put_calls = [
            c for c in mock_run.call_args_list
            if "index.html" in str(c) and "PUT" in str(c)
        ]
        self.assertTrue(len(put_calls) >= 1)
        payload = json.loads(put_calls[-1].kwargs.get("input", "{}"))
        decoded = base64.b64decode(payload["content"]).decode()
        self.assertEqual(decoded, html)

    @patch("publisher.subprocess.run")
    def test_publish_includes_sha_for_updates(self, mock_run: MagicMock):
        def side_effect(*args, **kwargs):
            cmd = args[0] if args else kwargs.get("args", [])
            cmd_str = " ".join(cmd)
            if "contents/index.html" in cmd_str and "--method" not in cmd_str:
                return MagicMock(returncode=0, stdout="abc123sha", stderr="")
            return MagicMock(returncode=0, stdout="", stderr="")

        mock_run.side_effect = side_effect
        config = _make_config()
        publish_dashboard("<html>updated</html>", config)

        put_calls = [
            c for c in mock_run.call_args_list
            if "index.html" in str(c) and "PUT" in str(c)
        ]
        self.assertTrue(len(put_calls) >= 1)
        payload = json.loads(put_calls[-1].kwargs.get("input", "{}"))
        self.assertEqual(payload.get("sha"), "abc123sha")

    @patch("publisher.subprocess.run")
    def test_publish_failure_raises(self, mock_run: MagicMock):
        def side_effect(*args, **kwargs):
            cmd = args[0] if args else kwargs.get("args", [])
            cmd_str = " ".join(cmd)
            if "--method" in cmd_str and "PUT" in cmd_str:
                return MagicMock(
                    returncode=1, stdout="", stderr="Not Found"
                )
            return MagicMock(returncode=0, stdout="", stderr="")

        mock_run.side_effect = side_effect
        config = _make_config()
        with self.assertRaises(SystemExit) as ctx:
            publish_dashboard("<html>fail</html>", config)
        self.assertIn("Failed to publish", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
