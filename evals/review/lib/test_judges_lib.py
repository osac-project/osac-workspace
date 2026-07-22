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
