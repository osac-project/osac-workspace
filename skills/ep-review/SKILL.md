---
name: ep-review
description: |
  Review an OSAC enhancement proposal against template requirements, architectural patterns,
  and historical reviewer expectations. Use when reviewing an EP PR, preparing an EP for
  submission, or self-reviewing a draft before requesting feedback. Produces rubric scores
  and structured findings with severity levels and actionable suggestions.

  Also trigger when user says "review this EP", "check this enhancement proposal",
  "is this EP ready", "review PR on enhancement-proposals", or references a PR
  on osac-project/enhancement-proposals.
---

# OSAC Enhancement Proposal Reviewer

## Overview

This skill reviews an enhancement proposal against the [OSAC EP template](https://github.com/osac-project/enhancement-proposals/blob/main/guidelines/enhancement_template.md), architectural conventions, and patterns learned from past reviewer feedback. It scores the EP across four dimensions and produces structured findings that help the author fix issues before human reviewers spend time on them.

## When to Use

- Reviewing a PR on `osac-project/enhancement-proposals`
- Self-reviewing a draft EP before submitting
- Preparing a revision in response to reviewer feedback
- Checking if an EP is ready for merge
- After `/design:revise` to verify improvements

## Input Detection

Detect what's being reviewed:

1. **PR URL or number** → Fetch the EP content from the PR diff
2. **Local file path** → Read the EP from disk (e.g., `enhancement-proposals/enhancements/<slug>/README.md`)
3. **No input** → Ask: "Which EP should I review? Provide a PR number, URL, or file path."

### Fetching from PR

```bash
gh pr diff <N> --repo osac-project/enhancement-proposals
gh pr view <N> --repo osac-project/enhancement-proposals --json title,body,author
```

## Load Context

Before reviewing, read these files if they exist:

1. `.design/context/osac-dimensions.md` — services, personas, cross-cutting dimensions
2. `.design/context/review-patterns.md` — reviewer feedback themes, anti-patterns, EP reference library
3. `.planning/codebase/ARCHITECTURE.md` — system architecture for technical grounding
4. `osac-docs/personas.md` — canonical OSAC persona definitions (bootstrapped from `osac-project/docs`)

Before scoring Completeness, read every `###` section under **Cross-Cutting Dimensions**
in the loaded `osac-dimensions.md`. For each section **relevant** to this EP, the EP must
**address** it in Proposal/Test Plan/Non-Goals or **explicitly defer** (e.g., "API/CLI-only",
"documentation deferred to Graduation Criteria"). Flag **Important** if relevant but silent.
Irrelevant sections → N/A (do not penalize).

## Review Dimensions

Evaluate the EP across four dimensions. Each dimension is scored 1-5:

| Score | Meaning |
|-------|---------|
| 5 | Excellent — exceeds expectations, no issues |
| 4 | Good — minor suggestions only |
| 3 | Adequate — meets minimum bar, some gaps to address |
| 2 | Needs work — significant gaps that will cause review friction |
| 1 | Insufficient — fundamental problems, not ready for review |

### Dimension 1: Architecture (weight: 30%)

Are the technical decisions sound and consistent with OSAC patterns?

Check:
- [ ] Resource hierarchy uses owner reference annotations (`osac.openshift.io/owner-reference`), not separate fields
- [ ] Tenant isolation includes `osac.openshift.io/tenant` annotation on all new resources
- [ ] API conventions followed: gRPC + REST gateway, proto naming (PascalCase messages, snake_case fields, SCREAMING_SNAKE_CASE enums)
- [ ] Controller patterns follow: finalizer → status update → provisioning lifecycle
- [ ] State enums use Pending/Ready/Failed pattern (not terminal "Rejected" states)
- [ ] Maps avoided in CRDs — prefer lists of named subobjects
- [ ] Write-only fields (secrets/credentials) are redacted in GET responses
- [ ] Dependencies between components are identified and ordering is clear
- [ ] Integration with existing services (fulfillment-service, osac-operator, osac-aap) is described
- [ ] Pluggable architectures preferred over hardcoded implementations (e.g., NetworkClass pattern)
- [ ] Cross-repo impacts enumerated (which components need changes?)
- [ ] Breaking changes called out with migration strategies

**Scoring guide:**
- 5: All OSAC patterns followed, dependencies clear, integration well-described
- 3: Core patterns followed, some integration gaps, minor convention misses
- 1: Fundamental architectural misalignment, missing tenant isolation, no dependency analysis

### Dimension 2: Feasibility (weight: 25%)

Is the implementation realistic and proportional to the scope?

Check:
- [ ] Implementation details are specific — names data structures, specifies error codes, defines validation rules
- [ ] Proto schemas included for new resources (at least key fields, types, constraints)
- [ ] No hand-waving on hard parts ("handle edge cases appropriately", "implement as needed")
- [ ] Effort is proportional to scope — a "small" EP shouldn't require changes in 5 repos
- [ ] Workflow covers all lifecycle operations (create, get, list, update, delete), not just happy path
- [ ] Error handling and failure modes described
- [ ] Risks are specific technical risks with concrete mitigations, not generic statements
- [ ] Drawbacks section steel-mans the argument against the proposal

**Scoring guide:**
- 5: Deep technical detail, proto schemas present, risks with concrete mitigations
- 3: Reasonable detail, some sections thin, risks somewhat generic
- 1: Vague implementation, no proto schemas, risks are platitudes

### Dimension 3: Scope (weight: 20%)

Is the EP right-sized with clear boundaries?

Check:
- [ ] Summary is 3-5 sentences answering: what's added, why it's valuable, key capabilities
- [ ] Goals are 3-7 bullet points describing user-visible outcomes, not implementation tasks
- [ ] Non-goals are specific about what's explicitly out of scope and why
- [ ] No scope creep signals ("and related functionality", "all necessary changes", "full support for")
- [ ] Target milestone declared (from `osac-dimensions.md` milestone scoping)
- [ ] Alternatives section includes at least one real alternative with explanation of why it was rejected
- [ ] Related EPs referenced in see-also frontmatter field
- [ ] User stories cover all relevant OSAC personas (Cloud Provider Admin, Cloud Infrastructure Admin, Tenant Admin, Tenant User)
- [ ] User stories follow the formula: "As a [role], I want to [action] so that I can [goal]"
- [ ] User stories describe user goals, not implementation details

**Scoring guide:**
- 5: Clear boundaries, all personas covered, specific non-goals, real alternatives
- 3: Boundaries mostly clear, some personas missing, non-goals could be more specific
- 1: Scope unbounded, only one persona, vague non-goals, no alternatives

### Dimension 4: Completeness (weight: 25%)

Are all template sections present and substantive?

Check against the [EP template](https://github.com/osac-project/enhancement-proposals/blob/main/guidelines/enhancement_template.md):

- [ ] YAML frontmatter complete (title, authors, creation-date, last-updated, tracking-link, see-also)
- [ ] Tracking link is a full URL (https://redhat.atlassian.net/browse/OSAC-XXXXX)
- [ ] Date format is YYYY-MM-DD
- [ ] All required sections present: Summary, Motivation (User Stories, Goals, Non-Goals), Proposal (Workflow Description, API Extensions, Implementation Details, Risks and Mitigations, Drawbacks), Alternatives, Test Plan, Graduation Criteria, Upgrade/Downgrade Strategy, Version Skew Strategy, Support Procedures, Infrastructure Needed
- [ ] No sections removed — sections that don't apply explain why
- [ ] No placeholder-only sections — every section has substantive content or explains N/A
- [ ] Terminology defined upfront and used consistently throughout
- [ ] Test plan describes strategy (unit, integration, e2e) even if details are TBD
- [ ] **Cross-cutting dimensions:** For each relevant `###` section in the loaded `osac-dimensions.md` (including UI, Documentation, E2E Testing when present), EP addresses or explicitly defers — not silent
- [ ] Length is in the 300-800 line range (under 200 suggests insufficient depth)

**Scoring guide:**
- 5: All sections substantive, terminology consistent, dimensions addressed, 400+ lines
- 3: All sections present, some thin, terminology mostly consistent
- 1: Missing required sections, placeholder text, under 200 lines

## Output Format

Present findings as a structured review:

```markdown
## EP Review: {title}

### Rubric Scores

| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Architecture | X/5 | 30% | X.X |
| Feasibility | X/5 | 25% | X.X |
| Scope | X/5 | 20% | X.X |
| Completeness | X/5 | 25% | X.X |
| **Overall** | | | **X.X/5** |

### Verdict: {PASS / NEEDS WORK / SIGNIFICANT GAPS}

{1-2 sentence assessment}

### Findings

#### Critical (must fix before merge)
1. {finding with specific section reference and suggestion}

#### Important (should fix)
1. {finding with specific section reference and suggestion}

#### Suggestions (nice to have)
1. {finding}

### Dimension Details

#### Architecture
{What's good, what needs improvement, specific pattern violations}

#### Feasibility
{Implementation depth assessment, missing details, risk quality}

#### Scope
{Boundary clarity, persona coverage, alternatives quality}

#### Completeness
{Section coverage, dimension coverage, length assessment}

#### Cross-cutting dimensions (from osac-dimensions.md)

| Dimension | Relevant? | EP status |
|-----------|-----------|-----------|
| {name} | Yes / No / N/A | Addressed / Deferred / Gap / N/A |

### Comparison with Similar EPs
{Reference 1-2 merged EPs from the EP reference library in review-patterns.md
that cover similar scope. Note what this EP does well or could learn from them.}

### Checklist Summary
- [x] Template sections complete
- [ ] All personas covered
- [x] Proto schemas included
...
```

## Verdict Thresholds

| Overall Score | Verdict |
|---------------|---------|
| 4.0+ | **PASS** — Ready for merge (pending human review) |
| 3.0-3.9 | **NEEDS WORK** — Address Important findings before requesting review |
| Below 3.0 | **SIGNIFICANT GAPS** — Address Critical findings, consider returning to `/design:draft` |

## Severity Classification

- **Critical**: Missing required sections, fundamental architectural misalignment, breaking changes without migration path, security gaps, no tenant isolation on new resources
- **Important**: Incomplete sections, terminology inconsistencies, missing personas, unclear workflow, vague non-goals, generic risks, thin implementation details; **relevant cross-cutting dimension from `osac-dimensions.md` neither addressed nor explicitly deferred**
- **Suggestion**: Style improvements, additional user stories, deeper alternatives discussion, more specific test plan, documentation polish

## Notes

- Score based on what's in the EP, not what you think should be there
- Use `osac-dimensions.md` to decide **relevance** per section (e.g., skip Networking for a storage-only EP). When a section **is** relevant, require address-or-defer — silence is a gap, not N/A
- Reference merged EPs in `enhancement-proposals/enhancements/` for calibration on depth and style
- Push for specificity: "handle errors" is not a mitigation; "retry with exponential backoff, circuit-break after 3 failures" is
- The review process requires consensus from all stakeholders — flag sections that would likely trigger stakeholder questions

$ARGUMENTS
