---
name: ep-review
description: |
  Review an OSAC enhancement proposal against template requirements, architectural patterns,
  and historical reviewer expectations. Use when reviewing an EP PR, preparing an EP for
  submission, or self-reviewing a draft before requesting feedback. Produces structured
  findings with severity levels and actionable suggestions.

  Also trigger when user says "review this EP", "check this enhancement proposal",
  "is this EP ready", "review PR on enhancement-proposals", or references a PR
  on osac-project/enhancement-proposals.
---

# OSAC Enhancement Proposal Reviewer

## Overview

This skill reviews an enhancement proposal against the [OSAC EP template](https://github.com/osac-project/enhancement-proposals/blob/main/guidelines/enhancement_template.md), architectural conventions, and patterns learned from past reviewer feedback across merged and open EPs. It acts as a first-pass reviewer catching issues before human reviewers spend time on them.

## When to Use

- Reviewing a PR on `osac-project/enhancement-proposals`
- Self-reviewing a draft EP before submitting
- Preparing a revision in response to reviewer feedback
- Checking if an EP is ready for merge

## Input Detection

Detect what's being reviewed:

1. **PR URL or number** → Fetch the EP content from the PR diff
2. **Local file path** → Read the EP from disk (e.g., `enhancement-proposals/enhancements/<slug>/README.md`)
3. **No input** → Ask: "Which EP should I review? Provide a PR number, URL, or file path."

### Fetching from PR

```bash
# Get the EP file from a PR
gh pr diff <N> --repo osac-project/enhancement-proposals
# Get PR metadata
gh pr view <N> --repo osac-project/enhancement-proposals --json title,body,author
```

### Reading from disk

```bash
cat enhancement-proposals/enhancements/<feature-slug>/README.md
```

## Review Dimensions

Evaluate the EP across these dimensions, ordered by importance:

### 1. Template Compliance (Required)

All sections from the [template](https://github.com/osac-project/enhancement-proposals/blob/main/guidelines/enhancement_template.md) must be present. If a section doesn't apply, it must explain why — not be removed.

Check:
- [ ] YAML frontmatter complete (title, authors, creation-date, last-updated, tracking-link, see-also)
- [ ] All required sections present: Summary, Motivation (User Stories, Goals, Non-Goals), Proposal (Workflow Description, API Extensions, Implementation Details, Risks and Mitigations, Drawbacks), Alternatives, Test Plan, Graduation Criteria, Upgrade/Downgrade Strategy, Version Skew Strategy, Support Procedures, Infrastructure Needed
- [ ] No placeholder-only sections (every section has substantive content or explains N/A)
- [ ] Date format is YYYY-MM-DD
- [ ] Tracking link is a full URL (https://issues.redhat.com/browse/MGMT-XXXXX)

### 2. Clarity and Structure

Reviewers consistently flag these patterns:

- **Summary too long or contains implementation details** → Should be 3-5 sentences answering: what's added, why it's valuable, key capabilities
- **User Stories missing the formula** → Must use "As a [role], I want to [action] so that I can [goal]"
- **User Stories focused on implementation, not user goals** → "As a tenant, I want the system to create a CRD" is wrong; "As a tenant, I want to provision a VM so I can run my workload" is right
- **Goals describe implementation, not outcomes** → Goals should be measurable outcomes, not task lists
- **Non-Goals are vague** → Must be specific about what's explicitly out of scope and why
- **Terminology undefined or inconsistent** → Key terms should be defined upfront and used consistently throughout
- **Proposal section unclear** → Should have 1-2 paragraphs per resource explaining relationships

### 3. Architectural Alignment

Check against OSAC patterns:

- **Resource hierarchy** → Parent-child relationships use owner reference annotations (`osac.io/owner-reference`), not separate fields
- **Tenant isolation** → Resources include `osac.openshift.io/tenant` annotation
- **API conventions** → gRPC with REST gateway, proto schemas with proper naming (PascalCase messages, snake_case fields, SCREAMING_SNAKE_CASE enums)
- **Controller patterns** → Finalizer → status update → provisioning lifecycle
- **Maps as anti-pattern** → In Kubernetes CRDs, prefer lists of named subobjects over maps
- **State enums** → Use Pending/Ready/Failed pattern, avoid terminal "Rejected" states (use Conditions instead)
- **Write-only fields** → Secrets/credentials should be write-only, redacted in GET responses

### 4. Cross-Cutting Concerns

Reviewers frequently ask about these — flag if missing:

- **Breaking changes** → Are there any? If so, are migration strategies documented?
- **Backward compatibility** → Protobuf wire compatibility for enum renames, field additions
- **Multi-tenancy** → Does every new resource have proper tenant scoping?
- **Related EPs** → Are related proposals referenced in see-also?
- **Overlapping functionality** → Does this duplicate or conflict with existing capabilities?

### 5. Completeness Signals

Based on patterns from merged EPs:

- **Length** → Successful EPs range from 300-800 lines. Under 200 suggests insufficient depth.
- **Proto schemas** → Implementation Details should include proto message definitions for new resources
- **Workflow** → All lifecycle operations covered (create, get, list, update, delete), not just happy path
- **Risks** → Specific technical risks with concrete mitigations, not generic statements
- **Alternatives** → At least one alternative approach with explanation of why it was rejected
- **Test Plan** → Describes strategy (unit, integration, e2e) even if details are TBD

### 6. Common Reviewer Feedback Patterns

Flag these if detected — they come up repeatedly in EP reviews:

| Pattern | What reviewers say |
|---------|-------------------|
| Scope creep | "I think we will benefit from staying focused on creating a working solution at a smaller scale first" |
| Missing personas | EP only covers one persona (e.g., tenant) but the feature affects providers/admins too |
| Framing as implementation | Proposal reads as a design doc, not a user-facing enhancement |
| Unclear motivation | "I'm finding this a bit hard to follow" — motivation should argue for the feature, not against status quo |
| TBD overuse | Some TBD is fine (matching existing EPs), but core sections need substance |
| Inconsistent naming | Field names or resource names differ between sections |
| Missing security model | No discussion of authentication, authorization, or credential handling |
| Hardcoded assumptions | Design assumes specific deployment topology or infrastructure |

## Output Format

Present findings as a structured review:

```text
## EP Review: <title>

### Summary
<1-2 sentence assessment: ready for review / needs work / significant gaps>

### Findings

#### Critical (must fix before merge)
1. <finding with specific location and suggestion>

#### Important (should fix)
1. <finding with specific location and suggestion>

#### Suggestions (nice to have)
1. <finding>

### Checklist
- [x] Template sections complete
- [ ] User stories follow formula
- [ ] Proto schemas included
...

### Comparison with Similar EPs
<reference 1-2 merged EPs that cover similar scope, note what this EP does well or could learn from them>
```

## Severity Classification

- **Critical**: Missing required sections, fundamental architectural misalignment, breaking changes without migration path, security gaps
- **Important**: Incomplete sections, terminology inconsistencies, missing personas, unclear workflow, vague non-goals
- **Suggestion**: Style improvements, additional user stories, deeper alternatives discussion, documentation polish

## Notes

- Review against the template at https://github.com/osac-project/enhancement-proposals/blob/main/guidelines/enhancement_template.md
- Reference merged EPs in `enhancement-proposals/enhancements/` for calibration on depth and style
- The review process requires consensus from all stakeholders — flag any sections that would likely trigger stakeholder questions
- Push for specificity: "handle errors" is not a mitigation; "retry with exponential backoff, circuit-break after 3 failures" is
