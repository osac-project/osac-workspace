---
name: design-review
description: |
  Review an OSAC design document against template requirements, architectural patterns,
  and historical reviewer expectations. Use when reviewing a design PR, preparing a design for
  submission, or self-reviewing a draft before requesting feedback. Produces rubric scores
  and structured findings with severity levels and actionable suggestions.

  Also trigger when user says "review this design", "check this design document",
  "is this design ready", "review PR on enhancement-proposals", or references a PR
  on osac-project/enhancement-proposals.
---

# OSAC Design Document Reviewer

## Overview

This skill reviews a design document against the [OSAC design template](https://github.com/osac-project/enhancement-proposals/blob/main/guidelines/enhancement_template.md),
architectural conventions, and patterns learned from past reviewer feedback.
It uses calibrated 0-2 scoring across 4 dimensions with hard pass/fail
thresholds — matching the Org Pulse dashboard assessment format.

## When to Use

- Reviewing a PR on `osac-project/enhancement-proposals`
- Self-reviewing a draft design before submitting
- Preparing a revision in response to reviewer feedback
- Checking if a design is ready for merge
- After `/design:revise` to verify improvements

## Input Detection

Detect what's being reviewed:

1. **PR URL or number** → Fetch the design content from the PR diff
2. **Local file path** → Read the design from disk (e.g., `enhancement-proposals/enhancements/<slug>/design.md`)
3. **No input** → Ask: "Which design should I review? Provide a PR number, URL, or file path."

### Fetching from PR

```bash
gh pr diff <N> --repo osac-project/enhancement-proposals
gh pr view <N> --repo osac-project/enhancement-proposals --json title,body,author
```

## Load Context

Before reviewing, read these files if they exist:

1. `.design/context/osac-dimensions.md` — services, personas, cross-cutting dimensions
2. `.design/context/review-patterns.md` — reviewer feedback themes, anti-patterns, design reference library
3. `.planning/codebase/ARCHITECTURE.md` — system architecture for technical grounding
4. `docs/personas.md` — canonical OSAC persona definitions

## Scoring Rubric

### Context

A design document describes HOW a feature will be implemented — architecture,
API design, controller logic, provisioning workflows. It builds on a PRD (WHAT/WHY)
and provides enough detail for engineering to estimate, plan, and implement.

### Template Completeness

Before scoring, note any structural issues. These feed into dimension scores
rather than blocking the review — the agent must always produce scores for
all 4 dimensions.

- YAML frontmatter: title, authors, creation-date, last-updated, tracking-link (full URL)
- Required sections: Summary, Motivation (User Stories, Goals, Non-Goals), Proposal (Workflow Description, API Extensions, Implementation Details, Risks and Mitigations, Drawbacks), Alternatives, Test Plan
- Placeholder-only sections (`TBD` with no other content, or a lone `TODO:` line with no other content) count against the relevant dimension score
- Sections that are genuinely N/A must explain why — silence is a gap

### Criteria (0-2 each, /8 total)

Score each criterion independently. For each, first state your reasoning,
then assign the score. Missing or placeholder-only sections that are relevant
to a criterion pull that criterion's score toward 0.

#### 1. Architecture (0-2)

Are the technical decisions sound and consistent with OSAC patterns?

Check:
- [ ] Resource hierarchy uses owner reference annotations (`osac.openshift.io/owner-reference`)
- [ ] Tenant isolation includes `osac.openshift.io/tenant` annotation on all new resources
- [ ] API conventions per `fulfillment-service/docs/API.md`: standard object shape (`id`, `Metadata`, `<Type>Spec`, `<Type>Status`), spec/status ownership, declarative intent-based design (no imperative methods), naming conventions
- [ ] Spec contains only desired state (user-controlled); status contains only observed state (system-controlled)
- [ ] Controller patterns: finalizer → status update → provisioning lifecycle
- [ ] Conditions used for lifecycle state (preferred over phase enums for new resources)
- [ ] Maps avoided in CRDs — prefer lists of named subobjects
- [ ] Dependencies between components identified with ordering
- [ ] Integration with existing services described
- [ ] Pluggable architectures preferred over hardcoded implementations
- [ ] Cross-repo impacts enumerated
- [ ] Breaking changes called out with migration strategies
- [ ] Terminology defined upfront and used consistently throughout

- 0 = Fundamental architectural misalignment — missing tenant isolation, wrong patterns, no dependency analysis
- 1 = Core patterns followed but gaps — some conventions missed, integration partially described, inconsistent terminology
- 2 = All OSAC patterns followed, dependencies clear, integration well-described, terminology consistent

**Calibration examples:**

- A=0: Design introduces new CRDs without tenant annotation, uses direct DB access instead of gRPC, proto schemas don't follow standard object shape, doesn't mention which repos need changes.
- A=1: Design follows controller patterns and has tenant isolation, proto schemas use standard object shape but mix spec/status ownership (e.g., user-modifiable fields in status), doesn't describe interaction with osac-aap for provisioning.
- A=2: Design follows all conventions, describes the full resource hierarchy with owner references, enumerates cross-repo changes (fulfillment-service proto + osac-operator controller + osac-aap role), and defines terminology upfront.

#### 2. Feasibility (0-2)

Is the implementation realistic, specific, and proportional to the scope?

Check:
- [ ] Implementation details are specific — names data structures, specifies error codes, defines validation rules
- [ ] Proto schemas included for new resources (at least key fields, types, constraints)
- [ ] No hand-waving on hard parts (e.g. vague phrases like `handle edge cases appropriately` or `implement as needed`)
- [ ] Effort is proportional to scope
- [ ] Workflow covers all lifecycle operations (create, get, list, update, delete)
- [ ] Error handling and failure modes described
- [ ] Risks are specific technical risks with concrete mitigations
- [ ] Drawbacks section steel-mans the argument against the proposal

- 0 = Vague implementation — no proto schemas, hand-waving on hard parts, generic risks ("things might break")
- 1 = Reasonable detail but gaps — some lifecycle operations missing, risks somewhat generic, thin error handling
- 2 = Deep technical detail, proto schemas present, all lifecycle ops covered, risks with concrete mitigations

**Calibration examples:**

- F=0: Example of vague implementation: `The controller will handle provisioning appropriately` with no detail on what provisioning means, no proto schema, and risks like "implementation might be complex."
- F=1: Design includes proto schemas for the main resource and describes create/get/list, but update and delete flows are "TBD." Risks mention "race conditions" without specifying which ones or how to mitigate.
- F=2: Design includes full proto schemas with field types and validation annotations, describes all CRUD lifecycle operations with error codes, identifies specific risks ("concurrent subnet allocation may cause CIDR overlap") with concrete mitigations ("use optimistic locking with resource version").

#### 3. Scope (0-2)

Is the design right-sized with clear boundaries, covering relevant personas and dimensions?

Check:
- [ ] Summary is 3-5 sentences: what's added, why it's valuable, key capabilities
- [ ] Goals are user-visible outcomes, not implementation tasks
- [ ] Non-goals are specific about what's explicitly out of scope and why
- [ ] No scope creep signals ("and related functionality", "all necessary changes")
- [ ] Alternatives section includes at least one real alternative with rationale for rejection
- [ ] User stories cover all relevant OSAC personas
- [ ] User stories follow: "As a [role], I want to [action] so that I can [goal]"

Using `.design/context/osac-dimensions.md`, also check cross-cutting dimension
coverage — for each dimension relevant to this design, the design must address it or
explicitly defer. Silence on a relevant dimension is a gap.

- 0 = Scope unbounded, only one persona, vague non-goals, no alternatives, relevant dimensions ignored
- 1 = Boundaries mostly clear, some personas missing, non-goals could be more specific, some dimensions not mentioned
- 2 = Clear boundaries, all relevant personas covered, specific non-goals, real alternatives, relevant dimensions addressed or deferred

**Calibration examples:**

- S=0: Design has no non-goals, covers only "Tenant User" persona, and says "Alternatives: none considered." Storage dimension is relevant but not mentioned.
- S=1: Design covers Tenant Admin and Tenant User but not Cloud Provider Admin (who would manage the feature's backend config). Non-goals say "advanced features are out of scope" without specifying which. Networking dimension acknowledged but not addressed.
- S=2: Design covers all relevant personas with user stories, non-goals explicitly exclude auto-scaling and multi-region ("deferred to v0.2, see OSAC-XXXX"), alternatives section compares two real approaches with trade-offs, and all relevant dimensions from osac-dimensions.md are addressed or explicitly deferred.

#### 4. Testability (0-2)

Does the design describe a concrete test strategy that would catch regressions?

Check:
- [ ] Test plan describes strategy per level: unit, integration, e2e
- [ ] Unit tests specify what's tested (validation logic, state transitions, error paths)
- [ ] Integration tests describe test infrastructure (kind cluster, mocked backends, etc.)
- [ ] E2E tests describe user-observable scenarios
- [ ] Graduation criteria are concrete conditions, not vague milestones

- 0 = No test plan, or placeholder ("tests will be added"). Graduation criteria absent or vague.
- 1 = Test plan mentions unit/integration/e2e but lacks specifics — doesn't say what's tested or how. Graduation criteria present but generic.
- 2 = Test plan specifies what's tested at each level with concrete scenarios. Graduation criteria are measurable conditions.

**Calibration examples:**

- T=0: "Unit and integration tests will be added" — no specifics on what's tested.
- T=1: "Unit tests for proto validation, integration tests with kind cluster" — right categories but no specific scenarios. Graduation criteria: "feature is stable."
- T=2: "Unit tests for CIDR validation and overlap detection; integration tests for subnet creation and attachment using kind cluster with mock network backend; e2e test for full tenant workflow: create VirtualNetwork → create Subnet → attach to ComputeInstance → verify connectivity." Graduation criteria: "All CRUD operations pass e2e, error paths tested, no regressions in existing networking tests."

### Pass/Fail

- **PASS**: Total >= 5/8 AND no zeros on any criterion
- **FAIL**: Total < 5 OR any zero (automatic fail regardless of total)

A single zero is an automatic fail because it signals a fundamental problem
(e.g., no test plan, or architectural misalignment). The author must fix
zero-scored criteria before resubmission.

## Output Format

Present findings as a structured review:

```markdown
## Design Review: {title}

### Rubric Scores

| Criterion | Score | Notes |
|-----------|-------|-------|
| Architecture | X/2 | {pattern compliance, dependency clarity, terminology} |
| Feasibility | X/2 | {implementation depth, proto schemas, risk quality} |
| Scope | X/2 | {boundary clarity, persona coverage, dimension coverage} |
| Testability | X/2 | {test strategy specificity, graduation criteria} |
| **Total** | **X/8** | **PASS / FAIL** |

### Verdict: {PASS / FAIL}

{1-2 sentence assessment. If fail, name the zero-scored criteria first.}

### Findings

#### Critical (must fix — zero-scored criteria)
1. {finding with specific section reference, quote the problematic text, suggest improvement}

#### Important (should fix)
1. {finding with specific section reference and suggestion}

#### Suggestions (nice to have)
1. {finding}

### Criterion Details

{For each criterion, explain the score with specific quotes from the design.
Show what's good and what needs improvement.}

### Cross-cutting Dimensions (from osac-dimensions.md)

| Dimension | Relevant? | Status |
|-----------|-----------|-----------|
| {name} | Yes / No | Addressed / Deferred / Gap |

### Comparison with Similar Designs
{Reference 1-2 merged designs from the design reference library in review-patterns.md
that cover similar scope. Note what this design does well or could learn from them.}
```

## Severity Classification

- **Critical**: Any zero-scored criterion. Also: missing tenant isolation on new resources, fundamental architectural misalignment, breaking changes without migration path, security gaps.
- **Important**: Score of 1 on any criterion. Also: incomplete sections, missing personas, unclear workflow, vague non-goals, generic risks, thin implementation details, relevant dimension neither addressed nor deferred.
- **Suggestion**: Style improvements, additional user stories, deeper alternatives discussion, more specific test plan, documentation polish.

## Notes

- Score based on what's in the design, not what you think should be there
- Use `osac-dimensions.md` to decide relevance per dimension — skip Networking for a storage-only design. When a dimension is relevant, require address-or-defer — silence is a gap
- Reference merged designs in `enhancement-proposals/enhancements/` for calibration on depth and style
- Push for specificity: "handle errors" is not a mitigation; "retry with exponential backoff, circuit-break after 3 failures" is
- The review process requires consensus from all stakeholders — flag sections that would likely trigger stakeholder questions

$ARGUMENTS
