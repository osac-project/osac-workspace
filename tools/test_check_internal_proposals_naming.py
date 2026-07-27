import io
import os
import unittest
from contextlib import redirect_stderr
from unittest.mock import patch

import check_internal_proposals_naming as cin


class TopLevelProposalDirTests(unittest.TestCase):
    def test_nested_path_returns_first_segment(self):
        self.assertEqual(
            cin.top_level_proposal_dir(
                "internal-proposals/OSAC-42-foo/design.md"
            ),
            "OSAC-42-foo",
        )

    def test_path_outside_internal_proposals_returns_none(self):
        self.assertIsNone(cin.top_level_proposal_dir("README.md"))
        self.assertIsNone(
            cin.top_level_proposal_dir("enhancement-proposals/README.md")
        )

    def test_bare_file_in_internal_proposals_returns_none(self):
        self.assertIsNone(
            cin.top_level_proposal_dir("internal-proposals/stray-file.md")
        )


class ValidatePathsTests(unittest.TestCase):
    def _validate(
        self,
        paths,
        base_sha,
        existing_at_base,
        base_ref_exists=True,
        live_base_ref=None,
        live_base_ref_exists=True,
        existing_at_live_base=frozenset(),
    ):
        def fake_ref_exists(ref):
            if ref == base_sha:
                return base_ref_exists
            if ref == live_base_ref:
                return live_base_ref_exists
            return False

        def fake_path_exists_at_ref(ref, path):
            if ref == live_base_ref:
                return path in existing_at_live_base
            return path in existing_at_base

        with patch.object(cin, "ref_exists", side_effect=fake_ref_exists), \
                patch.object(
                    cin, "path_exists_at_ref", side_effect=fake_path_exists_at_ref,
                ):
            return cin.validate_paths(paths, base_sha, live_base_ref)

    def test_grandfathered_directory_is_not_flagged(self):
        violations = self._validate(
            paths=["internal-proposals/agentic-sdlc-notes/design.md"],
            base_sha="abc123",
            existing_at_base={"internal-proposals/agentic-sdlc-notes"},
        )
        self.assertEqual(violations, [])

    def test_new_directory_with_bad_name_is_flagged(self):
        violations = self._validate(
            paths=["internal-proposals/sdlc-metrics/prd.md"],
            base_sha="abc123",
            existing_at_base=set(),
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("sdlc-metrics", violations[0])

    def test_bad_name_violation_includes_example_and_doc_pointer(self):
        # The message must give a concrete example (not just the abstract
        # <jira-key>-<slug> placeholder) and point to internal-proposals/
        # README.md, since this same generic template previously fired
        # identically for unrelated failure reasons (missing prefix,
        # missing slug, zero-padding, bad dashes) with no way to tell them
        # apart.
        violations = self._validate(
            paths=["internal-proposals/sdlc-metrics/prd.md"],
            base_sha="abc123",
            existing_at_base=set(),
        )
        self.assertIn("OSAC-1110-example-proposal", violations[0])
        self.assertIn("internal-proposals/README.md", violations[0])

    def test_new_directory_with_zero_padded_key_is_flagged(self):
        violations = self._validate(
            paths=["internal-proposals/OSAC-000959-test-feature/prd.md"],
            base_sha="abc123",
            existing_at_base=set(),
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("OSAC-000959-test-feature", violations[0])

    def test_new_directory_with_compliant_name_is_not_flagged(self):
        violations = self._validate(
            paths=["internal-proposals/OSAC-959-agentic-sdlc-measurement/design.md"],
            base_sha="abc123",
            existing_at_base=set(),
        )
        self.assertEqual(violations, [])

    def test_new_directory_with_unrecognized_prefix_is_still_flagged(self):
        violations = self._validate(
            paths=["internal-proposals/JIRA-123-example-feature/prd.md"],
            base_sha="abc123",
            existing_at_base=set(),
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("JIRA-123-example-feature", violations[0])

    def test_new_file_with_wrong_case_is_flagged(self):
        for bad_name in ("PRD.md", "Design.md", "DESIGN.md"):
            with self.subTest(bad_name=bad_name):
                violations = self._validate(
                    paths=[
                        f"internal-proposals/OSAC-959-agentic-sdlc-measurement/{bad_name}"
                    ],
                    base_sha="abc123",
                    existing_at_base=set(),
                )
                self.assertEqual(len(violations), 1)
                self.assertIn(bad_name, violations[0])

    def test_new_file_with_correct_case_is_not_flagged(self):
        for good_name in ("prd.md", "design.md"):
            with self.subTest(good_name=good_name):
                violations = self._validate(
                    paths=[
                        f"internal-proposals/OSAC-959-agentic-sdlc-measurement/{good_name}"
                    ],
                    base_sha="abc123",
                    existing_at_base=set(),
                )
                self.assertEqual(violations, [])

    def test_edited_pre_existing_file_with_wrong_case_is_not_reflagged(self):
        path = "internal-proposals/agentic-sdlc-notes/DESIGN.md"
        violations = self._validate(
            paths=[path],
            base_sha="abc123",
            existing_at_base={"internal-proposals/agentic-sdlc-notes", path},
        )
        self.assertEqual(violations, [])

    def test_new_file_in_grandfathered_directory_is_still_checked_for_casing(self):
        violations = self._validate(
            paths=["internal-proposals/agentic-sdlc-notes/PRD.md"],
            base_sha="abc123",
            existing_at_base={"internal-proposals/agentic-sdlc-notes"},
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("PRD.md", violations[0])

    def test_no_base_sha_is_advisory_only_and_flags_nothing(self):
        with redirect_stderr(io.StringIO()) as captured:
            violations = cin.validate_paths(
                ["internal-proposals/agentic-sdlc-notes/design.md"], None,
            )
        self.assertEqual(violations, [])
        self.assertIn("no pr base sha available", captured.getvalue().lower())

    def test_no_base_sha_does_not_catch_new_bad_name_either(self):
        # Documents the accepted tradeoff: without a base SHA, local runs
        # can't distinguish new from pre-existing, so enforcement is
        # skipped entirely — even for a genuinely new, badly-named
        # directory. CI (which always sets the base SHA) is the real gate.
        with redirect_stderr(io.StringIO()):
            violations = cin.validate_paths(
                ["internal-proposals/sdlc-metrics/prd.md"], None,
            )
        self.assertEqual(violations, [])

    def test_unresolvable_base_sha_falls_back_to_no_grandfathering(self):
        # path_exists_at_ref returns True here (i.e. the directory would be
        # grandfathered if base_sha were trusted) — this only passes if the
        # unresolvable ref actually resets base_sha to None internally,
        # rather than merely printing a warning while still grandfathering.
        with patch.object(cin, "ref_exists", return_value=False), \
                patch.object(cin, "path_exists_at_ref", return_value=True), \
                redirect_stderr(io.StringIO()) as captured:
            violations = cin.validate_paths(
                ["internal-proposals/agentic-sdlc-notes/design.md"], "deadbeef",
            )
        self.assertEqual(len(violations), 1)
        self.assertIn("agentic-sdlc-notes", violations[0])
        message = captured.getvalue().lower()
        self.assertIn("deadbeef", message)
        self.assertIn("fetch-depth", message)

    def test_pre_existing_on_live_main_but_absent_at_stale_base_sha_is_not_flagged(self):
        # Reproduces the false-positive class seen on enhancement-proposals
        # PR #121 (see check_ep_naming.py): a directory merged by an
        # unrelated PR after this PR's base SHA was last captured is absent
        # at the stale base_sha but present on the live tip of main — it
        # must still be recognized as grandfathered, not flagged as "new"
        # just because this PR's own history predates it.
        violations = self._validate(
            paths=["internal-proposals/OSAC-2872-example/prd.md"],
            base_sha="stale123",
            existing_at_base=set(),
            live_base_ref="origin/main",
            existing_at_live_base={"internal-proposals/OSAC-2872-example"},
        )
        self.assertEqual(violations, [])

    def test_new_directory_absent_from_both_refs_is_still_flagged(self):
        # The live-ref check is supplementary, not a blanket exemption — a
        # genuinely new, badly-named directory (absent from the stale base
        # SHA *and* from the live tip of main) must still be flagged.
        violations = self._validate(
            paths=["internal-proposals/sdlc-metrics/prd.md"],
            base_sha="stale123",
            existing_at_base=set(),
            live_base_ref="origin/main",
            existing_at_live_base=set(),
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("sdlc-metrics", violations[0])

    def test_live_base_ref_unresolvable_falls_back_to_base_sha_only(self):
        # If the live ref was never fetched (e.g. an older CI run before
        # this env var existed, or a checkout quirk), grandfathering falls
        # back to base-SHA-only behavior rather than erroring.
        violations = self._validate(
            paths=["internal-proposals/agentic-sdlc-notes/design.md"],
            base_sha="abc123",
            existing_at_base={"internal-proposals/agentic-sdlc-notes"},
            live_base_ref="origin/main",
            live_base_ref_exists=False,
        )
        self.assertEqual(violations, [])

    def test_pre_existing_on_live_main_but_absent_at_stale_base_sha_file_casing_is_not_reflagged(self):
        # Same false-positive class as the directory-grandfathering case
        # above, but for the filename-casing check specifically — it's a
        # separate code path (file_is_grandfathered) using the same
        # is_grandfathered() helper, so it needs its own coverage.
        path = "internal-proposals/OSAC-959-agentic-sdlc-measurement/DESIGN.md"
        violations = self._validate(
            paths=[path],
            base_sha="stale123",
            existing_at_base=set(),
            live_base_ref="origin/main",
            existing_at_live_base={
                "internal-proposals/OSAC-959-agentic-sdlc-measurement",
                path,
            },
        )
        self.assertEqual(violations, [])

    def test_unresolvable_base_sha_disables_live_ref_grandfathering_too(self):
        # The fail-closed guarantee ("grandfathering disabled, every path
        # validated as new") must hold in full: an unresolvable base SHA
        # can't partially fail closed by still trusting the live ref. Here
        # the live ref alone would grandfather the path if it were
        # consulted — it must not be.
        violations = self._validate(
            paths=["internal-proposals/agentic-sdlc-notes/design.md"],
            base_sha="deadbeef",
            base_ref_exists=False,
            existing_at_base=set(),
            live_base_ref="origin/main",
            live_base_ref_exists=True,
            existing_at_live_base={"internal-proposals/agentic-sdlc-notes"},
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("agentic-sdlc-notes", violations[0])

    def test_new_directory_with_consecutive_dashes_is_flagged(self):
        violations = self._validate(
            paths=["internal-proposals/OSAC-1--foo/prd.md"],
            base_sha="abc123",
            existing_at_base=set(),
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("OSAC-1--foo", violations[0])

    def test_new_directory_with_trailing_dash_is_flagged(self):
        violations = self._validate(
            paths=["internal-proposals/OSAC-1-foo-/prd.md"],
            base_sha="abc123",
            existing_at_base=set(),
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("OSAC-1-foo-", violations[0])

    def test_path_outside_internal_proposals_is_ignored(self):
        violations = self._validate(
            paths=["README.md", "enhancement-proposals/README.md"],
            base_sha="abc123",
            existing_at_base=set(),
        )
        self.assertEqual(violations, [])


class MainTests(unittest.TestCase):
    def test_clean_input_returns_zero(self):
        env = {cin.BASE_SHA_ENV_VAR: "abc123"}
        with patch.dict(os.environ, env), \
                patch.object(cin, "ref_exists", return_value=True), \
                patch.object(cin, "path_exists_at_ref", return_value=True), \
                redirect_stderr(io.StringIO()):
            exit_code = cin.main(
                ["internal-proposals/agentic-sdlc-notes/design.md"]
            )
        self.assertEqual(exit_code, 0)

    def test_violation_returns_one_and_prints_message(self):
        env = {cin.BASE_SHA_ENV_VAR: "abc123"}
        with patch.dict(os.environ, env), \
                patch.object(cin, "ref_exists", return_value=True), \
                patch.object(cin, "path_exists_at_ref", return_value=False), \
                redirect_stderr(io.StringIO()) as captured:
            exit_code = cin.main(["internal-proposals/sdlc-metrics/prd.md"])
        self.assertEqual(exit_code, 1)
        self.assertIn("sdlc-metrics", captured.getvalue())

    def test_missing_base_sha_env_var_is_advisory_only(self):
        with patch.dict(os.environ, {}, clear=True), \
                redirect_stderr(io.StringIO()) as captured:
            exit_code = cin.main(["internal-proposals/sdlc-metrics/PRD.md"])
        self.assertEqual(exit_code, 0)
        self.assertIn("no pr base sha available", captured.getvalue().lower())


if __name__ == "__main__":
    unittest.main()
