---
name: prd-review
description: |
  Review an OSAC PRD against template requirements, OSAC feature dimensions,
  persona coverage, and testability standards. Use when reviewing a PRD PR,
  preparing a PRD for submission, or self-reviewing before /prd:publish.
  Produces structured findings with rubric scores and actionable suggestions.

  Also trigger when user says "review this PRD", "check this PRD",
  "is this PRD ready", "review the requirements doc", or references a PRD
  file or PR.
---

# OSAC PRD Reviewer

## Overview

This skill reviews a Product Requirements Document against the PRD template,
OSAC-specific feature dimensions, and quality standards derived from past
review feedback. It scores the PRD across four dimensions and produces
structured findings that help the author fix issues before human reviewers
spend time on them.

## When to Use

- Self-reviewing a PRD before running `/prd:publish`
- Reviewing a PRD PR on `enhancement-proposals`
- Checking if a PRD is ready for the design phase
- After `/prd:revise` to verify improvements

## Input Detection

Detect what's being reviewed:

1. **PR URL or number** → Fetch the PRD content from the PR diff
2. **Local file path** → Read the PRD from disk (e.g., `enhancement-proposals/enhancements/<slug>/prd.md` or `.artifacts/prd/*/03-prd.md` for pre-publish drafts)
3. **No input** → Ask: "Which PRD should I review? Provide a PR number, file path, or Jira issue key."

### Fetching from PR

```bash
gh pr diff <N> --repo osac-project/enhancement-proposals
gh pr view <N> --repo osac-project/enhancement-proposals --json title,body,author
```

### Reading from artifact

```bash
ls .artifacts/prd/*/03-prd.md
```

## Load Context

Before reviewing, read these files if they exist:

1. `.design/context/osac-dimensions.md` — services, personas, cross-cutting dimensions
2. `.design/context/review-patterns.md` — reviewer feedback themes and anti-patterns
3. `.planning/codebase/ARCHITECTURE.md` — system architecture for technical grounding

## Review Dimensions

Evaluate the PRD across four dimensions. Each dimension is scored 1-5:

| Score | Meaning |
|-------|---------|
| 5 | Excellent — exceeds expectations, no issues |
| 4 | Good — minor suggestions only |
| 3 | Adequate — meets minimum bar, some gaps to address |
| 2 | Needs work — significant gaps that will cause review friction |
| 1 | Insufficient — fundamental problems, not ready for review |

### Dimension 1: Clarity (weight: 30%)

Is the PRD clear, specific, and well-structured?

Check:
- [ ] Problem statement leads with user pain, not solution (3-5 sentences)
- [ ] Problem statement quantifies impact if source material supports it
- [ ] Goals are measurable outcomes, not activities ("Users can deploy X" not "Implement deployment")
- [ ] Non-goals are specific, not vague ("Auto-scaling is out of scope" not "Advanced features")
- [ ] No vague language ("appropriate", "efficient", "standard" without specifics)
- [ ] No scope reduction language ("v2", "simplified", "placeholder", "future enhancement")
- [ ] Terminology is consistent throughout — same concept never called by different names
- [ ] Each section has substantive content or is explicitly omitted per template rules

**Scoring guide:**
- 5: Every goal is measurable, every requirement is specific, no vague language
- 3: Goals are mostly outcomes, some requirements need tightening
- 1: Goals describe activities, requirements are vague, scope is unclear

### Dimension 2: Scope (weight: 25%)

Is the PRD right-sized with clear boundaries?

Check:
- [ ] Target milestone is declared (e.g., 0.1, 0.2)
- [ ] What's NOT covered is explicit — deferred capabilities listed as non-goals
- [ ] No scope creep signals ("and related functionality", "all necessary changes", "full support for")
- [ ] Functional requirements are enumerable (each has a stable FR-N ID)
- [ ] 3-5 goals (more suggests scope is too broad)
- [ ] Non-goals prevent reasonable misinterpretations of scope
- [ ] Dependencies are identified with ordering constraints
- [ ] Risks have owners and mitigations (not generic statements)

**Scoring guide:**
- 5: Crystal clear boundaries, explicit milestone scoping, no creep signals
- 3: Boundaries mostly clear, some non-goals could be more specific
- 1: Scope is unbounded, no milestone declaration, creep signals throughout

### Dimension 3: Coverage (weight: 30%)

Does the PRD address all relevant OSAC dimensions and personas?

Using `.design/context/osac-dimensions.md`, check:

- [ ] **Services declared**: Which services (BMaaS, CaaS, VMaaS, MaaS, Enclave) are in scope?
- [ ] **All four personas considered**: Cloud Provider Admin, Cloud Infrastructure Admin, Tenant Admin, Tenant User — for each in-scope service, what does each persona do?
- [ ] **Tenant onboarding**: RBAC, IDP, auto-provisioned resources addressed (or explicitly out of scope)
- [ ] **Inventory**: Backend(s) identified, API integration vs. direct access clarified
- [ ] **Provisioning**: Mechanism identified, lifecycle stages specified
- [ ] **Networking**: Backend(s) identified, API-integrated vs. side-channel clarified
- [ ] **Storage**: Prerequisites, automation, per-tenant provisioning addressed
- [ ] **Installation**: Helm/kustomize changes, CI implications, osac-installer updates
- [ ] **API resources**: For each in-scope service, affected API resources listed

Not every dimension applies to every feature. Score based on whether the PRD
*addresses* each relevant dimension (even if just to say "not affected"), not
whether every dimension is in scope.

**Scoring guide:**
- 5: All relevant dimensions addressed, all personas covered for in-scope services
- 3: Most dimensions covered, some personas missing, some dimensions not mentioned
- 1: Only one persona considered, most dimensions ignored

### Dimension 4: Testability (weight: 15%)

Can the requirements be verified?

Check:
- [ ] Each functional requirement (FR-N) is testable — you can describe how to verify it
- [ ] Acceptance criteria are concrete, verifiable conditions (checkboxes)
- [ ] Acceptance criteria cover the primary use cases (edge cases belong in test plan)
- [ ] Non-functional requirements are measurable ("API response under 200ms at p95" not "fast")
- [ ] Success metrics have targets and baselines (when included)

**Scoring guide:**
- 5: Every requirement is testable, acceptance criteria are concrete assertions
- 3: Most requirements testable, some acceptance criteria are vague
- 1: Requirements describe activities, acceptance criteria are untestable

## Output Format

Present findings as a structured review:

```markdown
## PRD Review: {title}

### Rubric Scores

| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Clarity | X/5 | 30% | X.X |
| Scope | X/5 | 25% | X.X |
| Coverage | X/5 | 30% | X.X |
| Testability | X/5 | 15% | X.X |
| **Overall** | | | **X.X/5** |

### Verdict: {PASS / NEEDS WORK / SIGNIFICANT GAPS}

{1-2 sentence assessment}

### Findings

#### Critical (must fix before publish)
1. {finding with specific section reference and suggestion}

#### Important (should fix)
1. {finding with specific section reference and suggestion}

#### Suggestions (nice to have)
1. {finding}

### Dimension Details

#### Clarity
{What's good, what needs improvement, specific examples}

#### Scope
{What's good, what needs improvement, specific examples}

#### Coverage
{Which dimensions are addressed, which are missing, persona gaps}

#### Testability
{Which requirements are testable, which need tightening}

### Checklist Summary
- [x] Problem statement present and compelling
- [ ] All four personas considered
- [x] Milestone boundaries declared
...
```

## Verdict Thresholds

| Overall Score | Verdict |
|---------------|---------|
| 4.0+ | **PASS** — Ready for `/prd:publish` |
| 3.0-3.9 | **NEEDS WORK** — Address Important findings before publishing |
| Below 3.0 | **SIGNIFICANT GAPS** — Address Critical findings, consider `/prd:clarify` |

## Severity Classification

- **Critical**: Missing required sections, no personas identified, scope unbounded, requirements untestable, OSAC dimensions completely ignored
- **Important**: Vague non-goals, missing personas, some dimensions not addressed, weak acceptance criteria, scope creep signals
- **Suggestion**: Style improvements, additional non-goals, deeper risk analysis, more specific metrics

## Notes

- Score based on what's in the PRD, not what you think should be there — if information is genuinely unavailable, "TBD" markers are acceptable
- The coverage dimension uses `osac-dimensions.md` as a checklist, not a requirement — features that don't touch networking shouldn't be penalized for not addressing networking
- Compare against the PRD template at `.ai-workflows/prd/templates/prd.md` for structural compliance (this path is available after `bootstrap.sh` installs [ai-workflows](https://github.com/flightctl/ai-workflows))
- If the PRD was produced by `/prd:draft`, check that clarification locked decisions are reflected

$ARGUMENTS
