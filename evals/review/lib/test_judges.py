"""Synthetic-output tests for the eval-*.yaml module/function judges.

Loads eval-prd-review.yaml and eval-design-review.yaml through the pinned
agent-eval-harness's own EvalConfig/load_judges, then feeds each judge
synthetic `outputs` dicts directly (no case files on disk, no LLM calls) —
this exercises the actual judge-loading and code-judge-execution path the
harness uses at eval time (importlib.import_module against
evals/review/lib/judges.py), confirming both eval YAMLs are wired to the
real functions correctly. See test_judges_lib.py for direct,
harness-independent tests of judges.py itself.

Skips gracefully if the pinned harness hasn't been bootstrapped locally
(run evals/review/setup-harness.sh first).
"""

import sys
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[3]
_HARNESS_ROOT = _REPO_ROOT / "evals" / "review" / ".harness" / "agent-eval-harness"
_HARNESS_SCRIPTS = _HARNESS_ROOT / "skills" / "eval-run" / "scripts"

pytestmark = pytest.mark.skipif(
    not _HARNESS_SCRIPTS.is_dir(),
    reason="agent-eval-harness not bootstrapped locally — run evals/review/setup-harness.sh",
)

if _HARNESS_SCRIPTS.is_dir():
    sys.path.insert(0, str(_HARNESS_ROOT))
    sys.path.insert(0, str(_HARNESS_SCRIPTS))
    from agent_eval.config import EvalConfig
    from score import load_judges

_CONFIGS = [
    str(_REPO_ROOT / "evals" / "review" / "eval-prd-review.yaml"),
    str(_REPO_ROOT / "evals" / "review" / "eval-design-review.yaml"),
]

@pytest.fixture(autouse=True)
def _dummy_llm_api_key(monkeypatch):
    """load_judges() eagerly constructs every judge in the config, including
    the LLM qualitative_finding_quality judge, which raises RuntimeError at
    load time unless an API key env var is present — even though this test
    module never calls that judge's scorer. A placeholder key satisfies the
    loader without making any network call.
    """
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-placeholder-not-used")


_REVIEW_OUTPUT_TEMPLATE = """\
## Review

### Rubric Scores

| Criterion | Score | Notes |
|-----------|-------|-------|
{rows}
| **Total** | **{total}/10** | |

### Verdict: {verdict}

### Findings

#### Important (should fix)
1. {findings}
"""


def _build_review_output(scores: dict, verdict: str,
                          findings: str = "No significant findings.") -> str:
    rows = "\n".join(f"| {name} | {score}/2 | ok |" for name, score in scores.items())
    return _REVIEW_OUTPUT_TEMPLATE.format(
        rows=rows, total=sum(scores.values()), verdict=verdict, findings=findings,
    )


def _run_judge(config_path: str, judge_name: str, annotations: dict, review_output: str):
    """Run one named judge from a config against synthetic outputs.

    Returns the judge's (passed, rationale) result, or None if the judge's
    own `if:` condition skipped it.
    """
    config = EvalConfig.from_yaml(config_path)
    judges = {name: (scorer, condition) for name, scorer, condition, _, _ in
              load_judges(config, project_root=_REPO_ROOT)}
    scorer, condition = judges[judge_name]
    outputs = {"files": {"artifacts/review-output.md": review_output},
               "annotations": annotations}
    if condition and not eval(condition, {"__builtins__": {}},
                              {"annotations": annotations, "outputs": outputs}):
        return None
    return scorer(outputs=outputs)


@pytest.mark.parametrize("config_path", _CONFIGS)
class TestRubricScoring:
    def test_exact_match_passes(self, config_path):
        scores = {"WHAT (clear need)": 2, "WHY (justification)": 2}
        review_output = _build_review_output(scores, "PASS")
        annotations = {"expected_verdict": "PASS", "expected_scores": scores}

        passed, rationale = _run_judge(config_path, "rubric_scoring", annotations, review_output)

        assert passed is True, rationale

    def test_score_mismatch_fails(self, config_path):
        review_output = _build_review_output({"WHAT (clear need)": 2}, "PASS")
        annotations = {"expected_verdict": "PASS",
                        "expected_scores": {"WHAT (clear need)": 1}}

        passed, rationale = _run_judge(config_path, "rubric_scoring", annotations, review_output)

        assert passed is False
        assert "mismatch" in rationale.lower()

    def test_verdict_mismatch_fails(self, config_path):
        review_output = _build_review_output({"WHAT (clear need)": 2}, "PASS")
        annotations = {"expected_verdict": "FAIL",
                        "expected_scores": {"WHAT (clear need)": 2}}

        passed, rationale = _run_judge(config_path, "rubric_scoring", annotations, review_output)

        assert passed is False
        assert "verdict" in rationale.lower()

    def test_missing_criterion_fails(self, config_path):
        review_output = _build_review_output({"WHAT (clear need)": 2}, "PASS")
        annotations = {"expected_verdict": "PASS",
                        "expected_scores": {"WHAT (clear need)": 2, "Testability": 2}}

        passed, rationale = _run_judge(config_path, "rubric_scoring", annotations, review_output)

        assert passed is False
        assert "Testability" in rationale

    def test_empty_expected_scores_skips_instead_of_failing(self, config_path):
        review_output = _build_review_output({"WHAT (clear need)": 2}, "PASS")
        annotations = {"expected_verdict": "PASS", "expected_scores": {}}

        passed, rationale = _run_judge(config_path, "rubric_scoring", annotations, review_output)

        assert passed is True, rationale


@pytest.mark.parametrize("config_path", _CONFIGS)
class TestCriticalFindingsRecall:
    def test_paraphrased_finding_recalled(self, config_path):
        review_output = _build_review_output(
            {"WHAT (clear need)": 2}, "PASS",
            findings="The user stories section lacks any mention of tenant isolation requirements.",
        )
        annotations = {"critical_findings": ["Missing tenant isolation in user stories"]}

        passed, rationale = _run_judge(
            config_path, "critical_findings_recall", annotations, review_output)

        assert passed is True, rationale

    def test_absent_finding_fails(self, config_path):
        review_output = _build_review_output({"WHAT (clear need)": 2}, "PASS")
        annotations = {"critical_findings": ["Something totally unrelated to the output"]}

        passed, rationale = _run_judge(
            config_path, "critical_findings_recall", annotations, review_output)

        assert passed is False

    def test_no_critical_findings_condition_skips(self, config_path):
        review_output = _build_review_output({"WHAT (clear need)": 2}, "PASS")
        annotations = {}

        result = _run_judge(config_path, "critical_findings_recall", annotations, review_output)

        assert result is None

    def test_stopwords_alone_do_not_satisfy_recall(self, config_path):
        """A finding's only substantive word ("section") must appear in the
        output — five incidental grammatical-word matches ("it", "is",
        "not", "in", "this") must not be enough to hit 60% overlap on their
        own, or the judge would recall findings the review never actually
        made.
        """
        review_output = _build_review_output(
            {"WHAT (clear need)": 2}, "PASS",
            findings="This document is comprehensive and does not omit anything "
                     "relevant in it whatsoever.",
        )
        annotations = {"critical_findings": ["It is not in this section"]}

        passed, rationale = _run_judge(
            config_path, "critical_findings_recall", annotations, review_output)

        assert passed is False, rationale
