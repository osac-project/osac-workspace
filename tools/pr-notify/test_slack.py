"""Unit tests for slack.py."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from slack import post_message


class TestPostMessage(unittest.TestCase):
    """Tests for the post_message function."""

    def _make_creds_dir(self, tmp: str, token: str = "xoxc-tok", cookie: str = "d-cookie") -> str:
        """Write token and cookie files into a temp directory."""
        Path(tmp, "xoxc_token").write_text(token + "\n")
        Path(tmp, "d_cookie").write_text(cookie + "\n")
        return tmp

    def test_missing_token_file_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "d_cookie").write_text("c")
            with self.assertRaises(SystemExit) as ctx:
                post_message("C123", "hi", tmp)
            self.assertIn("xoxc_token", str(ctx.exception))

    def test_missing_cookie_file_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "xoxc_token").write_text("t")
            with self.assertRaises(SystemExit) as ctx:
                post_message("C123", "hi", tmp)
            self.assertIn("d_cookie", str(ctx.exception))

    @patch("slack.urllib.request.urlopen")
    def test_successful_post(self, mock_urlopen: MagicMock) -> None:
        resp_body = json.dumps({"ok": True, "ts": "1234.5678"}).encode()
        mock_resp = MagicMock()
        mock_resp.read.return_value = resp_body
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        with tempfile.TemporaryDirectory() as tmp:
            self._make_creds_dir(tmp)
            post_message("C123", "hello", tmp)

        mock_urlopen.assert_called_once()
        req = mock_urlopen.call_args[0][0]
        self.assertIn(b"token=xoxc-tok", req.data)
        self.assertIn(b"channel=C123", req.data)
        self.assertIn(b"unfurl_links=false", req.data)
        self.assertEqual(req.get_header("Cookie"), "d=d-cookie")

    @patch("slack.urllib.request.urlopen")
    def test_auth_error_raises_system_exit(self, mock_urlopen: MagicMock) -> None:
        resp_body = json.dumps({"ok": False, "error": "invalid_auth"}).encode()
        mock_resp = MagicMock()
        mock_resp.read.return_value = resp_body
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        with tempfile.TemporaryDirectory() as tmp:
            self._make_creds_dir(tmp)
            with self.assertRaises(SystemExit) as ctx:
                post_message("C123", "hello", tmp)
            self.assertIn("expired", str(ctx.exception))

    @patch("slack.urllib.request.urlopen")
    def test_api_error_raises_system_exit(self, mock_urlopen: MagicMock) -> None:
        resp_body = json.dumps({"ok": False, "error": "channel_not_found"}).encode()
        mock_resp = MagicMock()
        mock_resp.read.return_value = resp_body
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        with tempfile.TemporaryDirectory() as tmp:
            self._make_creds_dir(tmp)
            with self.assertRaises(SystemExit) as ctx:
                post_message("C123", "hello", tmp)
            self.assertIn("channel_not_found", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
