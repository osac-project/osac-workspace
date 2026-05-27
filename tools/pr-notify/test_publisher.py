"""Unit tests for the PR-based dashboard publisher."""

import base64
import json
import unittest
from unittest.mock import MagicMock, call, patch

from models import DashboardConfig
from publisher import publish_data


def _make_config(**overrides) -> DashboardConfig:
    defaults = {
        "repo": "testorg/testrepo",
        "branch": "main",
        "base_url": "https://testorg.github.io/testrepo/pr-dashboard",
        "data_path": "docs/pr-dashboard/data.json",
    }
    defaults.update(overrides)
    return DashboardConfig(**defaults)


def _mock_run_success(*args, **kwargs):
    cmd = args[0] if args else kwargs.get("args", [])
    cmd_str = " ".join(cmd)

    if "git/ref/heads/main" in cmd_str:
        return MagicMock(returncode=0, stdout="abc123mainsha", stderr="")
    if "git/refs/heads/dashboard-data" in cmd_str and "--method" not in cmd_str:
        return MagicMock(returncode=1, stdout="", stderr="Not Found")
    if "contents/docs/pr-dashboard/data.json" in cmd_str and "--method" not in cmd_str:
        return MagicMock(returncode=1, stdout="", stderr="Not Found")
    if "pr" in cmd_str and "list" in cmd_str:
        return MagicMock(returncode=0, stdout="", stderr="")
    if "pr" in cmd_str and "create" in cmd_str:
        return MagicMock(returncode=0, stdout="https://github.com/testorg/testrepo/pull/42", stderr="")
    if "pr" in cmd_str and "merge" in cmd_str:
        return MagicMock(returncode=0, stdout="", stderr="")
    return MagicMock(returncode=0, stdout="", stderr="")


class TestPublisher(unittest.TestCase):

    @patch("publisher.subprocess.run", side_effect=_mock_run_success)
    def test_publish_returns_url(self, mock_run: MagicMock):
        config = _make_config()
        url = publish_data('{"test": true}', config)
        self.assertEqual(url, "https://testorg.github.io/testrepo/pr-dashboard/")

    @patch("publisher.subprocess.run", side_effect=_mock_run_success)
    def test_creates_branch(self, mock_run: MagicMock):
        config = _make_config()
        publish_data('{"test": true}', config)

        ref_create_calls = [
            c for c in mock_run.call_args_list
            if "git/refs" in str(c) and "POST" in str(c)
        ]
        self.assertTrue(len(ref_create_calls) >= 1)

    @patch("publisher.subprocess.run", side_effect=_mock_run_success)
    def test_uploads_data_file(self, mock_run: MagicMock):
        config = _make_config()
        data = '{"summary": {}}'
        publish_data(data, config)

        put_calls = [
            c for c in mock_run.call_args_list
            if "data.json" in str(c) and "PUT" in str(c)
        ]
        self.assertTrue(len(put_calls) >= 1)
        payload = json.loads(put_calls[-1].kwargs.get("input_data", None) or put_calls[-1][1].get("input", "{}") if len(put_calls[-1]) > 1 else "{}")

    @patch("publisher.subprocess.run", side_effect=_mock_run_success)
    def test_creates_pr(self, mock_run: MagicMock):
        config = _make_config()
        publish_data('{"test": true}', config)

        pr_create_calls = [
            c for c in mock_run.call_args_list
            if "pr" in str(c) and "create" in str(c)
        ]
        self.assertTrue(len(pr_create_calls) >= 1)

    @patch("publisher.subprocess.run", side_effect=_mock_run_success)
    def test_merges_pr(self, mock_run: MagicMock):
        config = _make_config()
        publish_data('{"test": true}', config)

        merge_calls = [
            c for c in mock_run.call_args_list
            if "pr" in str(c) and "merge" in str(c)
        ]
        self.assertTrue(len(merge_calls) >= 1)
        merge_cmd = merge_calls[-1][0][0] if merge_calls[-1][0] else []
        self.assertIn("--admin", merge_cmd)

    @patch("publisher.subprocess.run")
    def test_reuses_existing_pr(self, mock_run: MagicMock):
        def side_effect(*args, **kwargs):
            cmd = args[0] if args else kwargs.get("args", [])
            cmd_str = " ".join(cmd)
            if "git/ref/heads/main" in cmd_str:
                return MagicMock(returncode=0, stdout="sha123", stderr="")
            if "git/refs/heads/dashboard-data" in cmd_str:
                return MagicMock(returncode=1, stdout="", stderr="")
            if "contents/" in cmd_str and "--method" not in cmd_str:
                return MagicMock(returncode=1, stdout="", stderr="")
            if "pr" in cmd_str and "list" in cmd_str:
                return MagicMock(returncode=0, stdout="99", stderr="")
            if "pr" in cmd_str and "merge" in cmd_str:
                return MagicMock(returncode=0, stdout="", stderr="")
            return MagicMock(returncode=0, stdout="", stderr="")

        mock_run.side_effect = side_effect
        config = _make_config()
        publish_data('{}', config)

        pr_create_calls = [
            c for c in mock_run.call_args_list
            if "pr" in str(c) and "create" in str(c)
        ]
        self.assertEqual(len(pr_create_calls), 0)

        merge_calls = [
            c for c in mock_run.call_args_list
            if "pr" in str(c) and "merge" in str(c)
        ]
        self.assertTrue(len(merge_calls) >= 1)

    @patch("publisher.subprocess.run")
    def test_merge_failure_raises(self, mock_run: MagicMock):
        def side_effect(*args, **kwargs):
            cmd = args[0] if args else kwargs.get("args", [])
            cmd_str = " ".join(cmd)
            if "git/ref/heads/main" in cmd_str:
                return MagicMock(returncode=0, stdout="sha123", stderr="")
            if "git/refs/heads/dashboard-data" in cmd_str:
                return MagicMock(returncode=1, stdout="", stderr="")
            if "contents/" in cmd_str and "--method" not in cmd_str:
                return MagicMock(returncode=1, stdout="", stderr="")
            if "pr" in cmd_str and "list" in cmd_str:
                return MagicMock(returncode=0, stdout="", stderr="")
            if "pr" in cmd_str and "create" in cmd_str:
                return MagicMock(returncode=0, stdout="https://github.com/t/r/pull/1", stderr="")
            if "pr" in cmd_str and "merge" in cmd_str:
                return MagicMock(returncode=1, stdout="", stderr="merge conflict")
            return MagicMock(returncode=0, stdout="", stderr="")

        mock_run.side_effect = side_effect
        config = _make_config()
        with self.assertRaises(SystemExit) as ctx:
            publish_data('{}', config)
        self.assertIn("Failed to merge", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
