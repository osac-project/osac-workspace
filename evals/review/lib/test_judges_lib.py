"""Direct unit tests for judges.py — no harness bootstrap required.

Complements test_judges.py, which exercises the same logic through the
pinned harness's real EvalConfig/load_judges path (and skips gracefully if
the harness isn't cloned locally). This file calls rubric_scoring()/
critical_findings_recall() directly, so these two judges have a coverage
floor even before evals/review/setup-harness.sh has ever been run.
"""

from evals.review.lib.judges import critical_findings_recall, rubric_scoring

_REVIEW_OUTPUT = """\
## Review

### Rubric Scores

| Criterion | Score | Notes |
|-----------|-------|-------|
| WHAT (clear need) | 2/2 | ok |

### Verdict: {verdict}

### Findings

#### Important (should fix)
1. {findings}
"""


def _outputs(verdict="PASS", findings="No significant findings.", annotations=None):
    content = _REVIEW_OUTPUT.format(verdict=verdict, findings=findings)
    return {"files": {"artifacts/review-output.md": content},
            "annotations": annotations or {}}


class TestRubricScoring:
    def test_exact_match_passes(self):
        outputs = _outputs(annotations={
            "expected_verdict": "PASS",
            "expected_scores": {"WHAT (clear need)": 2},
        })

        passed, rationale = rubric_scoring(outputs=outputs)

        assert passed is True, rationale

    def test_score_mismatch_fails(self):
        outputs = _outputs(annotations={
            "expected_verdict": "PASS",
            "expected_scores": {"WHAT (clear need)": 1},
        })

        passed, rationale = rubric_scoring(outputs=outputs)

        assert passed is False
        assert "mismatch" in rationale.lower()

    def test_verdict_mismatch_fails(self):
        outputs = _outputs(annotations={
            "expected_verdict": "FAIL",
            "expected_scores": {"WHAT (clear need)": 2},
        })

        passed, rationale = rubric_scoring(outputs=outputs)

        assert passed is False
        assert "verdict" in rationale.lower()

    def test_missing_artifact_fails(self):
        outputs = {"files": {}, "annotations": {}}

        passed, rationale = rubric_scoring(outputs=outputs)

        assert passed is False
        assert "review-output.md" in rationale

    def test_empty_expected_scores_skips_instead_of_failing(self):
        outputs = _outputs(annotations={"expected_verdict": "PASS", "expected_scores": {}})

        passed, rationale = rubric_scoring(outputs=outputs)

        assert passed is True, rationale

    def test_missing_expected_scores_key_fails(self):
        """A missing `expected_scores` key (case's annotations.yaml is
        incomplete/malformed) must fail loudly, unlike an explicit empty
        mapping (the documented smoke-fixture marker, tested above) which
        skips. Otherwise a broken case could silently pass rubric_scoring
        with no rubric check ever having run.
        """
        outputs = _outputs(annotations={"expected_verdict": "PASS"})

        passed, rationale = rubric_scoring(outputs=outputs)

        assert passed is False
        assert "expected_scores" in rationale

    def test_null_expected_scores_fails_instead_of_skipping(self):
        """`expected_scores: null` must fail, not silently skip like the
        documented `{}` marker — otherwise it would disagree with
        validate_cases.py, which already rejects None via its
        `isinstance(expected_scores, dict)` check.
        """
        outputs = _outputs(annotations={"expected_verdict": "PASS", "expected_scores": None})

        passed, rationale = rubric_scoring(outputs=outputs)

        assert passed is False
        assert "mapping" in rationale.lower()

    def test_non_mapping_expected_scores_fails_gracefully(self):
        """A malformed `expected_scores` (e.g. a YAML list instead of a
        mapping) must be reported as a validation failure, not crash with
        an AttributeError — a crash is silently excluded from the harness's
        pass_rate denominator (score.py drops any case whose judge raised),
        which would let a malformed case escape AC-2's strict enforcement
        entirely instead of failing loudly.
        """
        outputs = _outputs(annotations={
            "expected_verdict": "PASS",
            "expected_scores": ["not", "a", "mapping"],
        })

        passed, rationale = rubric_scoring(outputs=outputs)

        assert passed is False
        assert "mapping" in rationale.lower()


class TestCriticalFindingsRecall:
    def test_paraphrased_finding_recalled(self):
        outputs = _outputs(
            findings="The user stories section lacks any mention of tenant isolation requirements.",
            annotations={"critical_findings": ["Missing tenant isolation in user stories"]},
        )

        passed, rationale = critical_findings_recall(outputs=outputs)

        assert passed is True, rationale

    def test_absent_finding_fails(self):
        outputs = _outputs(
            annotations={"critical_findings": ["Something totally unrelated to the output"]},
        )

        passed, rationale = critical_findings_recall(outputs=outputs)

        assert passed is False

    def test_stopwords_alone_do_not_satisfy_recall(self):
        """A finding's only substantive word ("section") must appear in the
        output — incidental grammatical-word matches must not be enough to
        hit 60% overlap on their own.
        """
        outputs = _outputs(
            findings="This document is comprehensive and does not omit anything "
                     "relevant in it whatsoever.",
            annotations={"critical_findings": ["It is not in this section"]},
        )

        passed, rationale = critical_findings_recall(outputs=outputs)

        assert passed is False, rationale

    def test_stopword_only_finding_is_vacuously_ignored(self):
        """A critical_findings entry that tokenizes to zero substantive
        (non-stopword) words has nothing to overlap against, so it must be
        skipped rather than counted as an unrecalled finding.
        """
        outputs = _outputs(annotations={"critical_findings": ["it is not"]})

        passed, rationale = critical_findings_recall(outputs=outputs)

        assert passed is True, rationale

    def test_accented_finding_recalled(self):
        """Non-ASCII tokens (accented Latin here) must not silently reduce
        to zero tokens and get skipped — \\w+ is Unicode-aware, unlike the
        original [a-z0-9]+ tokenizer.
        """
        outputs = _outputs(
            findings="The migration plan omits a rollback strategy for the "
                     "café deployment scenario.",
            annotations={"critical_findings": ["Missing rollback for café deployment"]},
        )

        passed, rationale = critical_findings_recall(outputs=outputs)

        assert passed is True, rationale

    def test_decomposed_and_precomposed_accents_tokenize_the_same(self):
        """Canonically-equivalent Unicode forms must tokenize identically —
        precomposed "café" (U+00E9) in the finding vs. decomposed
        "cafe\\u0301" (e + combining acute accent, U+0065 U+0301) in the
        review output, or vice versa, must still overlap. NFC-normalizing
        in `_tokens()` before tokenizing is what makes this hold; without
        it the two forms produce different token strings despite being the
        same text.
        """
        outputs = _outputs(
            findings="The migration plan omits a rollback strategy for the "
                     "cafe\u0301 deployment scenario.",  # decomposed
            annotations={"critical_findings": ["Missing rollback for café deployment"]},  # precomposed
        )

        passed, rationale = critical_findings_recall(outputs=outputs)

        assert passed is True, rationale

    def test_bare_string_critical_findings_fails_gracefully(self):
        """A bare string (e.g. a case author forgetting the YAML list
        brackets) is truthy, so it passes the eval YAML's `if:` gate — but
        Python iterates a string character-by-character, which would
        otherwise silently produce a nonsensical per-character rationale
        instead of a clear "wrong type" error.
        """
        outputs = _outputs(annotations={"critical_findings": "Missing tenant isolation"})

        passed, rationale = critical_findings_recall(outputs=outputs)

        assert passed is False
        assert "list of strings" in rationale

    def test_non_iterable_critical_findings_fails_gracefully(self):
        """A non-iterable `critical_findings` (e.g. an int) must be reported
        as a validation failure, not crash with a TypeError — a crash is
        silently excluded from the harness's pass_rate denominator, letting
        a malformed case escape enforcement entirely instead of failing.
        """
        outputs = _outputs(annotations={"critical_findings": 5})

        passed, rationale = critical_findings_recall(outputs=outputs)

        assert passed is False
        assert "list of strings" in rationale
