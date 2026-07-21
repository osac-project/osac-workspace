"""Tests for validate_case() — see docs/case-schema.md for the field contract."""

from pathlib import Path

import pytest

from validate_cases import validate_case


def _write_case(case_dir: Path, *, input_yaml: str, annotations_yaml: str,
                 reference_review: str = "Reference review body.\n"):
    case_dir.mkdir(parents=True, exist_ok=True)
    (case_dir / "input.yaml").write_text(input_yaml)
    (case_dir / "annotations.yaml").write_text(annotations_yaml)
    (case_dir / "reference-review.md").write_text(reference_review)


VALID_INPUT = """\
document_path: doc.md
skill: prd-review
case_id: example
"""

VALID_ANNOTATIONS = """\
expected_verdict: PASS
rubric_version: "2026-07"
expected_scores:
  "WHAT (clear need)": 2
  "Right-Sized": 1
reference_review: reference-review.md
"""


@pytest.fixture
def workspace_root(tmp_path: Path) -> Path:
    (tmp_path / "doc.md").write_text("# Doc\n")
    return tmp_path


def test_valid_case_returns_no_errors(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=VALID_ANNOTATIONS)

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is True
    assert errors == []


def test_valid_case_with_empty_expected_scores(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "_harness-smoke"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\nexpected_scores: {}\n"
        "reference_review: reference-review.md\nskip_quality: true\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is True
    assert errors == []


def test_missing_input_yaml(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    case_dir.mkdir(parents=True)
    (case_dir / "annotations.yaml").write_text(VALID_ANNOTATIONS)
    (case_dir / "reference-review.md").write_text("body")

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("input.yaml" in e for e in errors)


def test_missing_reference_review(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    case_dir.mkdir(parents=True)
    (case_dir / "input.yaml").write_text(VALID_INPUT)
    (case_dir / "annotations.yaml").write_text(VALID_ANNOTATIONS)

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("reference-review.md" in e for e in errors)


def test_missing_annotations_yaml(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    case_dir.mkdir(parents=True)
    (case_dir / "input.yaml").write_text(VALID_INPUT)
    (case_dir / "reference-review.md").write_text("body")

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("annotations.yaml" in e for e in errors)


def test_document_path_outside_workspace_root(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml="document_path: ../outside.md\nskill: prd-review\ncase_id: example\n",
                annotations_yaml=VALID_ANNOTATIONS)

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("outside workspace_root" in e for e in errors)


def test_document_path_absolute_escapes_workspace_root(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml="document_path: /etc/passwd\nskill: prd-review\ncase_id: example\n",
                annotations_yaml=VALID_ANNOTATIONS)

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("outside workspace_root" in e for e in errors)


def test_document_path_does_not_exist(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml="document_path: missing.md\nskill: prd-review\ncase_id: example\n",
                annotations_yaml=VALID_ANNOTATIONS)

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("does not exist" in e for e in errors)


def test_missing_document_path_field(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml="skill: prd-review\ncase_id: example\n",
                annotations_yaml=VALID_ANNOTATIONS)

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("document_path" in e for e in errors)


def test_expected_scores_value_above_range(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\n"
        "expected_scores:\n  Criterion: 3\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("Criterion" in e and "0-2" in e for e in errors)


def test_expected_scores_value_below_range(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\n"
        "expected_scores:\n  Criterion: -1\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("Criterion" in e and "0-2" in e for e in errors)


def test_expected_scores_non_integer_value(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\n"
        "expected_scores:\n  Criterion: \"good\"\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("Criterion" in e for e in errors)


def test_missing_rubric_version(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nexpected_scores: {}\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("rubric_version" in e for e in errors)


def test_missing_expected_verdict(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "rubric_version: \"2026-07\"\nexpected_scores: {}\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("expected_verdict" in e for e in errors)


def test_invalid_expected_verdict_value(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: MAYBE\nrubric_version: \"2026-07\"\nexpected_scores: {}\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("expected_verdict" in e for e in errors)


def test_missing_expected_scores_field(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("expected_scores" in e for e in errors)


def test_missing_reference_review_field(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\nexpected_scores: {}\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("reference_review" in e for e in errors)


def test_reference_review_points_to_nonexistent_file(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\nexpected_scores: {}\n"
        "reference_review: does-not-exist.md\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("reference_review" in e and "does-not-exist.md" in e for e in errors)


def test_reference_review_absolute_path_escapes_case_dir(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    (tmp_path / "etc-hosts.md").write_text("not the real reference review")
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\nexpected_scores: {}\n"
        f"reference_review: {tmp_path / 'etc-hosts.md'}\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("reference_review" in e and "outside" in e for e in errors)


def test_reference_review_traversal_escapes_case_dir(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\nexpected_scores: {}\n"
        "reference_review: ../outside.md\n"
    ))
    (tmp_path / "cases" / "outside.md").write_text("not the real reference review")

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("reference_review" in e and "outside" in e for e in errors)


def test_critical_findings_must_be_list_of_strings(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\nexpected_scores: {}\n"
        "reference_review: reference-review.md\ncritical_findings: not-a-list\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("critical_findings" in e for e in errors)


def test_critical_findings_list_of_strings_is_valid(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\nexpected_scores: {}\n"
        "reference_review: reference-review.md\n"
        "critical_findings:\n  - Missing tenant isolation\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is True
    assert errors == []


def test_skip_quality_must_be_bool(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    _write_case(case_dir, input_yaml=VALID_INPUT, annotations_yaml=(
        "expected_verdict: PASS\nrubric_version: \"2026-07\"\nexpected_scores: {}\n"
        "reference_review: reference-review.md\nskip_quality: \"yes\"\n"
    ))

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert any("skip_quality" in e for e in errors)


def test_malformed_yaml_reports_error_without_raising(tmp_path: Path, workspace_root: Path):
    case_dir = tmp_path / "cases" / "example"
    case_dir.mkdir(parents=True)
    (case_dir / "input.yaml").write_text("document_path: [unterminated\n")
    (case_dir / "annotations.yaml").write_text(VALID_ANNOTATIONS)
    (case_dir / "reference-review.md").write_text("body")

    valid, errors = validate_case(case_dir, workspace_root)

    assert valid is False
    assert errors
