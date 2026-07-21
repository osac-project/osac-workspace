# Qualitative Finding Quality

Compare the agent's review output against the human-validated reference
review for the same document. Assess how well the agent's findings match
the reference in substance and nuance — not exact wording. The strict
`rubric_scoring` and `critical_findings_recall` judges already enforce exact
score and verdict match; this judge is only about the *quality* of the
prose findings and criterion explanations.

Score 1-5:
- 5: Findings are as thorough and well-reasoned as the reference — same
  substantive points, comparable specificity and evidence.
- 4: Findings cover all the reference's major points with only minor gaps
  in specificity or supporting evidence.
- 3: Findings cover the reference's major points but miss nuance, evidence,
  or some secondary observations.
- 2: Findings address the general area but are noticeably shallower or
  vaguer than the reference.
- 1: Findings miss most of the reference's substantive points or
  misread the document.

## Agent Review Output

{{ outputs.files['artifacts/review-output.md'] }}

## Human Reference Review

{{ outputs.annotation_reference_review_content }}
