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
import unicodedata

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
    # NFC-normalize first so canonically-equivalent Unicode forms tokenize
    # identically — e.g. precomposed "café" (U+00E9) and decomposed
    # "cafe\u0301" (e + combining acute accent) both become the former,
    # instead of comparing unequal despite being the same text.
    # \w is then Unicode-aware by default for str patterns in Python 3
    # (matches letters/digits in any script, not just ASCII a-z0-9), so
    # accented and non-Latin findings still produce tokens instead of
    # silently reducing to an empty set and being skipped by the
    # `if not cf_tokens` guard below.
    s = unicodedata.normalize("NFC", s)
    return {t for t in re.findall(r"\w+", s.lower()) if t not in _STOPWORDS}


def rubric_scoring(outputs=None, **kwargs):
    """Exact verdict + per-dimension score match against annotations.yaml.

    No ±1 tolerance: every dimension in `expected_scores` must match the
    review output's rubric table exactly, and the verdict must match too.

    `expected_scores: {}` (explicit empty mapping) skips scoring — the
    documented marker for a wiring-only smoke fixture. A missing
    `expected_scores` key entirely is treated as an incomplete/malformed
    case and fails instead of skipping. A present-but-non-mapping
    `expected_scores` (including an explicit `null`) also fails, matching
    `validate_cases.py`'s type check.
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

    # An explicit empty mapping (expected_scores: {}) is the documented way
    # to mark a wiring-only smoke fixture with no real rubric baseline yet —
    # skip in that case. A missing key, a null value, or any non-mapping
    # value is different: it means the case's annotations.yaml is
    # incomplete or malformed rather than intentionally smoke-only, so it
    # must fail loudly instead of silently passing — otherwise a broken
    # case could pass CI with no rubric check ever having run against it.
    # (Matches validate_cases.py's `isinstance(expected_scores, dict)`
    # check, so the two modules agree on every input shape, not just the
    # documented ones.)
    if "expected_scores" not in annotations:
        return (False, "annotations.yaml missing expected_scores (required — "
                        "use an explicit empty mapping {} to mark a "
                        "wiring-only smoke fixture instead of omitting the key)")

    expected_scores = annotations["expected_scores"]
    if not isinstance(expected_scores, dict):
        return (False, f"annotations.yaml expected_scores must be a mapping, "
                        f"got {type(expected_scores).__name__}")
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
    tokens appear in the review output. `critical_findings` must be a list
    of strings; any other type fails rather than iterating unpredictably.

    Known limitation: bag-of-words overlap has no notion of polarity, so a
    review that asserts the *opposite* of a critical finding (e.g. "tenant
    isolation is thoroughly addressed" vs. a finding of "missing tenant
    isolation") can still score above threshold on shared topic words alone
    — see the case-schema.md "Known limitations" note for detail and the
    alternatives considered (AC-2 requires this stay a deterministic check/
    code judge, ruling out an LLM-based fix here). The optional
    qualitative_finding_quality LLM judge is the intended backstop: it
    compares substantive content against reference-review.md and would
    catch a review that gets the substance backwards, whenever
    skip_quality isn't set.
    """
    outputs = outputs or {}
    annotations = outputs.get("annotations", {})

    critical_findings = annotations.get("critical_findings", [])
    is_list_of_str = (isinstance(critical_findings, list)
                       and all(isinstance(cf, str) for cf in critical_findings))
    if not is_list_of_str:
        # Guards against e.g. a bare string (iterates character-by-character
        # instead of raising — silently wrong rather than loudly broken) or
        # a non-iterable value (raises TypeError). Matches
        # validate_cases.py's equivalent check, so both modules agree.
        return (False, f"annotations.yaml critical_findings must be a list "
                        f"of strings, got {critical_findings!r}")

    content = outputs.get("files", {}).get(_ARTIFACT_KEY, "")
    content_tokens = _tokens(content)
    missing = []
    for cf in critical_findings:
        cf_tokens = _tokens(cf)
        if not cf_tokens:
            continue
        overlap = len(cf_tokens & content_tokens) / len(cf_tokens)
        if overlap < 0.6:
            missing.append(cf)
    if missing:
        return (False, f"Missing critical findings (<60% token overlap): {missing}")
    return (True, "All critical findings recalled (>=60% token overlap)")
