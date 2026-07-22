"""Shared scoring logic for the `rubric_scoring` and `critical_findings_recall`
judges in `eval-prd-review.yaml` and `eval-design-review.yaml`.

Referenced from both eval YAMLs via the harness's `module`/`function` judge
type (`module: evals.review.lib.judges`, `function: <name>`) instead of
duplicating this logic as inline `check:` Python snippets in each file —
see the "Judge layout reference" note in `evals/review/docs/case-schema.md`.

The harness's `module`/`function` judge type calls each function as
`fn(outputs=<case record dict>)` and expects a `(passed, rationale)`
tuple return.
"""

import re

_ARTIFACT_KEY = "artifacts/review-output.md"

# Grammatical stopwords only (no domain nouns) - excluding them keeps
# overlap from being satisfied by near-universal function words alone.
_STOPWORDS = {
    "a", "an", "the", "in", "on", "of", "to", "is", "are", "was",
    "were", "be", "been", "for", "with", "and", "or", "but", "not",
    "this", "that", "these", "those", "it", "its", "as", "at", "by",
    "from", "into", "over", "under", "up", "down", "out", "off",
}


def _tokens(s):
    return {t for t in re.findall(r"[a-z0-9]+", s.lower()) if t not in _STOPWORDS}


def rubric_scoring(outputs=None, **kwargs):
    """Exact verdict + per-dimension score match against annotations.yaml.

    No ±1 tolerance: every dimension in `expected_scores` must match the
    review output's rubric table exactly, and the verdict must match too.
    """
    outputs = outputs or {}
    annotations = outputs.get("annotations", {})
    content = outputs.get("files", {}).get(_ARTIFACT_KEY, "")
    if not content:
        return (False, f"No {_ARTIFACT_KEY} in case output")

    verdict_m = re.search(r"### Verdict:\s*(PASS|FAIL)", content)
    actual_verdict = verdict_m.group(1) if verdict_m else None

    rows = re.findall(
        r"^\|\s*\*{0,2}([^|*]+?)\*{0,2}\s*\|\s*\*{0,2}(\d+)/\d+\*{0,2}\s*\|",
        content, re.MULTILINE,
    )
    actual_scores = {
        name.strip(): int(score) for name, score in rows
        if name.strip().lower() != "total"
    }

    expected_verdict = annotations.get("expected_verdict")
    expected_scores = annotations.get("expected_scores") or {}

    if not expected_scores:
        return (True, "No expected_scores in annotations.yaml (smoke fixture) - skipped")

    if actual_verdict != expected_verdict:
        return (False, f"Verdict mismatch: expected {expected_verdict}, got {actual_verdict}")

    mismatches = {
        k: {"expected": v, "actual": actual_scores.get(k)}
        for k, v in expected_scores.items()
        if actual_scores.get(k) != v
    }
    if mismatches:
        return (False, f"Score mismatches: {mismatches}")

    return (True, f"Verdict and all {len(expected_scores)} criteria matched exactly")


def critical_findings_recall(outputs=None, **kwargs):
    """Stopword-filtered token-overlap match of annotations.yaml critical findings.

    A finding counts as recalled if >=60% of its substantive (non-stopword)
    tokens appear in the review output.
    """
    outputs = outputs or {}
    annotations = outputs.get("annotations", {})
    content = outputs.get("files", {}).get(_ARTIFACT_KEY, "")
    content_tokens = _tokens(content)
    missing = []
    for cf in annotations.get("critical_findings", []):
        cf_tokens = _tokens(cf)
        if not cf_tokens:
            continue
        overlap = len(cf_tokens & content_tokens) / len(cf_tokens)
        if overlap < 0.6:
            missing.append(cf)
    if missing:
        return (False, f"Missing critical findings (<60% token overlap): {missing}")
    return (True, "All critical findings recalled (>=60% token overlap)")
