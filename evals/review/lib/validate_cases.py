"""Validates review-eval case directories against the case schema.

See evals/review/docs/case-schema.md for the full field contract this
enforces.
"""

from __future__ import annotations

from pathlib import Path

import yaml

_VALID_VERDICTS = {"PASS", "FAIL"}
_SCORE_MIN, _SCORE_MAX = 0, 2


def validate_case(case_dir: Path, workspace_root: Path) -> tuple[bool, list[str]]:
    """Validate a case directory's structure and annotation schema.

    Checks:
    - input.yaml, reference-review.md, annotations.yaml all exist
    - input.yaml's document_path resolves under workspace_root
    - annotations.yaml has expected_verdict (PASS/FAIL), rubric_version (str)
    - annotations.yaml expected_scores values are ints in 0-2
    - annotations.yaml's optional critical_findings (list[str]) and
      skip_quality (bool) are well-typed if present
    - annotations.yaml's reference_review resolves to an existing file
      inside case_dir (required, no unsafe traversal outside case_dir)

    Returns (True, []) if valid, else (False, [error messages]).
    """
    case_dir = Path(case_dir)
    workspace_root = Path(workspace_root).resolve()
    errors: list[str] = []

    input_path = case_dir / "input.yaml"
    reference_path = case_dir / "reference-review.md"
    annotations_path = case_dir / "annotations.yaml"

    if not input_path.is_file():
        errors.append(f"{case_dir}: missing input.yaml")
    if not reference_path.is_file():
        errors.append(f"{case_dir}: missing reference-review.md")
    if not annotations_path.is_file():
        errors.append(f"{case_dir}: missing annotations.yaml")
    if errors:
        return (False, errors)

    input_data = _load_yaml_mapping(input_path, errors)
    annotations_data = _load_yaml_mapping(annotations_path, errors)
    if errors:
        return (False, errors)

    _validate_document_path(input_data, case_dir, workspace_root, errors)
    _validate_annotations(annotations_data, case_dir, errors)

    return (not errors, errors)


def _load_yaml_mapping(path: Path, errors: list[str]) -> dict:
    try:
        data = yaml.safe_load(path.read_text()) or {}
    except yaml.YAMLError as e:
        errors.append(f"{path}: invalid YAML ({e})")
        return {}
    if not isinstance(data, dict):
        errors.append(f"{path}: expected a YAML mapping, got {type(data).__name__}")
        return {}
    return data


def _validate_document_path(input_data: dict, case_dir: Path,
                             workspace_root: Path, errors: list[str]) -> None:
    document_path = input_data.get("document_path")
    if not document_path:
        errors.append(f"{case_dir}: input.yaml missing document_path")
        return

    # Pathlib's `/` operator drops the left operand when the right is
    # absolute, so an absolute document_path naturally fails the
    # is_relative_to check below instead of silently escaping the root.
    resolved = (workspace_root / document_path).resolve()
    if not resolved.is_relative_to(workspace_root):
        errors.append(
            f"{case_dir}: document_path '{document_path}' resolves outside workspace_root"
        )
        return
    if not resolved.is_file():
        errors.append(f"{case_dir}: document_path '{document_path}' does not exist")


def _validate_annotations(annotations_data: dict, case_dir: Path, errors: list[str]) -> None:
    verdict = annotations_data.get("expected_verdict")
    if not isinstance(verdict, str) or verdict not in _VALID_VERDICTS:
        errors.append(
            f"annotations.yaml: expected_verdict must be one of "
            f"{sorted(_VALID_VERDICTS)}, got {verdict!r}"
        )

    rubric_version = annotations_data.get("rubric_version")
    if not isinstance(rubric_version, str) or not rubric_version:
        errors.append(
            f"annotations.yaml: rubric_version must be a non-empty string, "
            f"got {rubric_version!r}"
        )

    if "expected_scores" not in annotations_data:
        errors.append("annotations.yaml: missing expected_scores")
    else:
        expected_scores = annotations_data["expected_scores"]
        if not isinstance(expected_scores, dict):
            errors.append(
                f"annotations.yaml: expected_scores must be a mapping, "
                f"got {type(expected_scores).__name__}"
            )
        else:
            for key, value in expected_scores.items():
                is_int = isinstance(value, int) and not isinstance(value, bool)
                if not is_int or not (_SCORE_MIN <= value <= _SCORE_MAX):
                    errors.append(
                        f"annotations.yaml: expected_scores['{key}'] must be an int "
                        f"in {_SCORE_MIN}-{_SCORE_MAX}, got {value!r}"
                    )

    _validate_optional_fields(annotations_data, case_dir, errors)


def _validate_optional_fields(annotations_data: dict, case_dir: Path, errors: list[str]) -> None:
    if "critical_findings" in annotations_data:
        critical_findings = annotations_data["critical_findings"]
        is_list_of_str = (isinstance(critical_findings, list)
                           and all(isinstance(cf, str) for cf in critical_findings))
        if not is_list_of_str:
            errors.append(
                f"annotations.yaml: critical_findings must be a list of strings, "
                f"got {critical_findings!r}"
            )

    if "skip_quality" in annotations_data:
        skip_quality = annotations_data["skip_quality"]
        if not isinstance(skip_quality, bool):
            errors.append(
                f"annotations.yaml: skip_quality must be a bool, got {skip_quality!r}"
            )

    # The harness only resolves outputs.annotation_reference_review_content
    # for keys literally present in annotations.yaml (no filename-based
    # fallback to reference-review.md), so a missing or unresolvable
    # reference_review silently scores the qualitative_finding_quality
    # judge against a blank reference instead of erroring.
    reference_review = annotations_data.get("reference_review")
    if reference_review is None:
        errors.append(
            "annotations.yaml: missing reference_review (required for the "
            "qualitative_finding_quality judge to read the reference review)"
        )
    elif not isinstance(reference_review, str):
        errors.append(
            f"annotations.yaml: reference_review must be a string, got {reference_review!r}"
        )
    else:
        # Same containment pattern as _validate_document_path: resolve
        # relative to case_dir and require the result stay inside it, so an
        # absolute path or `..` traversal is rejected explicitly rather than
        # silently resolving outside the case directory.
        resolved = (case_dir / reference_review).resolve()
        if not resolved.is_relative_to(case_dir.resolve()):
            errors.append(
                f"annotations.yaml: reference_review {reference_review!r} "
                f"resolves outside {case_dir}"
            )
        elif not resolved.is_file():
            errors.append(
                f"annotations.yaml: reference_review {reference_review!r} does not "
                f"resolve to a file in {case_dir}"
            )
