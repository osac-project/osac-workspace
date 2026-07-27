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

This skill reviews a Product Requirements Document against a calibrated rubric
with concrete scoring examples. It uses calibrated 0-2 scoring per criterion with
hard pass/fail thresholds — no weighted averages that mask problems.

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
3. `reference/ARCHITECTURE.md` — system architecture for technical grounding

## Scoring Rubric

### Context

A PRD describes WHAT the product must do and WHY — from the user's perspective.
A design document (enhancement proposal) describes HOW — architecture,
controllers, API fields, playbooks. PRDs should be written from the perspective
of a Product Manager, not an engineer.

### Criteria (0-2 each, /10 total)

Score each criterion independently. For each, first state your reasoning,
then assign the score.

#### 1. WHAT — Clear user-facing need? (0-2)

Does the PRD describe a new or changed product capability — something that
requires building, not just writing content? A PRD whose sole deliverable is
documentation, example files, configuration samples, or other content with no
new platform capability is not an enhancement — it belongs in a Jira task, not
the PRD pipeline. Score 0 if there is no new product capability.

Does the PRD clearly describe what users can do or observe?

##### OSAC Dimensions Checklist

Using `.design/context/osac-dimensions.md`, also check whether the PRD
addresses the OSAC dimensions relevant to this feature:
- **Services**: Which services (BMaaS, CaaS, VMaaS, MaaS, Enclave) are in scope?
- **Personas**: Cloud Provider Admin, Cloud Infrastructure Admin, Tenant Admin, Tenant User — which are affected and how?
- **Cross-cutting dimensions** (tenant onboarding, inventory, provisioning, networking, storage, installation): addressed or explicitly out of scope where relevant?
- **Verification scope**: Milestone declares what must be demonstrably working for users (vs deferred); cross-cutting user journeys identified — detailed test plan belongs in the EP
- **Documentation**: User-observable doc needs identified; milestone scope (in scope vs deferred); impact on existing documented workflows — detailed doc plan belongs in the EP
- **UI**: User-observable console needs identified; persona workflows affected; milestone scope (in scope vs API/CLI-only vs deferred) — detailed UI design belongs in the EP
- **API resources**: For each in-scope service, affected API resources listed

##### Scoring

Not every dimension applies to every feature. Don't penalize for dimensions
that aren't relevant — but a PRD that names no personas or services has an
unclear WHAT.

Each affected persona must have at least one user story grouped under a
persona heading (e.g., `### Tenant User`). Mentioning a persona in prose
("Cloud Infrastructure Admins are affected") without a corresponding
`As a <persona>...` user story does not count — the reviewer cannot
evaluate what that persona can actually do.

- 0 = Vague, unclear, or describes system internals rather than user outcomes. No personas or services identified, or no per-persona user stories.
- 1 = Ambiguous — need is partially clear but mixed with implementation, missing specifics, or missing affected personas. Or: user stories exist but some affected personas lack stories.
- 2 = Clear, specific, user-observable capabilities. Affected personas and services identified. Each affected persona has at least one user story.

**Calibration examples:**

- W=0: "Ship example YAML files and a README in the repo so admins can load them with `osac create -f`." — the API and CLI already exist; the deliverable is content (example files + docs), not a product capability. This is a Jira task, not an enhancement.
- W=0: "Implement CSI driver installation via AAP playbook on ClusterOrder Ready event" — describes a system action, not a user need. No persona mentioned.
- W=0: A PRD states "Cloud Infrastructure Admin and Cloud Provider Admin personas are affected" in the problem statement and references personas in functional requirements, but has no User Stories section and no `As a <persona>...` stories. Personas are named but the PRD never describes what each persona can do — the reviewer cannot evaluate completeness.
- W=1: "Storage should be available on CaaS clusters" — right direction but vague. Which clusters? What does "available" mean to the user? How would a tenant know? No personas identified.
- W=1: "Tenant users can create and manage secrets" — right direction but generic. What secrets? SSH keypairs? OIDC client secrets? Cluster kubeconfigs? Cloud-init credentials? Without explicit use cases, reviewers can't evaluate whether the scope is right.
- W=2: "When a CaaS cluster is provisioned and ready, tenants can create persistent volumes using StorageClasses without manual configuration. Tenants can see whether storage is ready on their cluster. Cloud Provider Admins can see storage readiness across all tenant clusters." — clear, observable, specific, personas identified.
- W=2: "Tenant users can retrieve cluster kubeconfig and admin password via the secrets API. Tenant admins can store OIDC client secrets for IDP integration. Tenant users can store cloud-init credentials containing passwords for VM provisioning." — names the concrete artifacts and scenarios, not just the generic capability.

#### 2. WHY — Business justification? (0-2)

Is there a clear reason this work matters — user pain, business need, or strategic goal?

- 0 = No justification, or circular reasoning ("we need X because we don't have X")
- 1 = Generic justification — plausible but no specific evidence (e.g., "users need this")
- 2 = Concrete justification — names the pain, quantifies impact, or ties to a strategic goal with a clear causal chain

Take stated evidence at face value. Search the entire PRD for evidence, not
just a dedicated section.

**Calibration examples:**

- Y=0: "Add storage support for CaaS clusters" with no explanation of why this matters or what happens without it.
- Y=0: A feature listing 11 Definition of Done bullets and 10 user stories but zero explanation of why this capability matters, who is asking for it, or what happens without it.
- Y=1: "Tenants cannot run stateful workloads on CaaS clusters without manual storage configuration." — describes the gap but no impact.
- Y=2: "CaaS clusters are provisioned without persistent storage. Tenants cannot run stateful workloads until someone manually configures storage, and there is no visibility into whether storage is available. This blocks CaaS adoption for any tenant with stateful workloads." — names the pain, describes the consequence, ties to adoption.
- Y=2: "Multi-tenant GPU clusters require InfiniBand tenant isolation to prevent cross-tenant traffic interference. Without isolation, tenants sharing a fabric can observe each other's RDMA traffic, which is a security and compliance blocker for sovereign AI deployments." — specific pain, concrete consequence, ties to strategic goal.

#### 3. User-Facing Focus — Free from design leakage? (0-2)

Does the PRD describe user-observable outcomes without prescribing implementation?
A PRD defines WHAT and WHY. The design document (enhancement proposal) defines HOW.

User-facing surfaces (CLI commands, UI pages, API resource names visible to
users) are WHAT. Internal architecture (controllers, reconcilers, playbooks,
env vars, finalizers, internal conditions) is HOW.

##### OSAC Platform Vocabulary

Referencing these by name is acceptable context, not design leakage:
- Platform: OpenShift, Kubernetes, Hosted Control Planes
- Services: BMaaS, CaaS, VMaaS, MaaS, Enclave
- Resources (user-facing): ClusterOrder, ComputeInstance, Tenant, VirtualNetwork, Subnet, SecurityGroup, PublicIPPool, PublicIP, StorageClass
- Networking: OVN, Multus, NetworkClass
- Storage: VAST, CSI
- Auth: Keycloak, OPA
- Tools: kubectl, grpcurl, Helm

##### Scoring

Naming platform technologies is not automatically prescriptive. But mandating
which internal component solves a problem, or describing controller logic,
finalizer behavior, or playbook parameters IS design leakage.

- 0 = PRD reads like a design document — names controllers, describes reconciliation logic, specifies internal API fields or conditions, references playbook parameters
- 1 = Mostly user-focused but some design details leak through — names an internal component or describes a behavior only observable by reading code
- 2 = Describes only user-observable outcomes; implementation details are absent or limited to platform vocabulary

##### Calibration Examples

- UF=0: "When a ClusterOrder reaches phase=Ready and the owning Tenant has StorageBackendReady=True, the storage controller invokes osac-create-tenant-cluster-storage with provisioning_target=hcp_data_plane." — names controllers, internal conditions, playbook parameters.
- UF=0: "The storage controller places a finalizer on each ClusterOrder where storage was set up. On deletion, it triggers osac-delete-tenant-cluster-storage to remove StorageClasses, VolumeSnapshotClasses, and CSI Secret from the CaaS cluster." — describes finalizer behavior and cleanup implementation.
- UF=1: "Storage is automatically provisioned on CaaS clusters when they become ready. The controller uses AAP to install the CSI driver." — good user outcome, but "the controller uses AAP" is an implementation detail.
- UF=2: "When a CaaS cluster is provisioned and ready, persistent storage is automatically available on the cluster without manual configuration." — pure user outcome.
- UF=2: "Tenants can see storage readiness on their ClusterOrder status." — ClusterOrder is user-facing platform vocabulary, readiness is observable.

**Smell tests:**
- "Could a PM verify this by using the product?" — if no, it's design leakage
- "Would this statement change if we swapped the implementation?" — if no, it belongs in the PRD; if yes, it's design
- "Does this name something only visible in code?" — if yes, it's design leakage

#### 4. Right-Sized — Focused scope? (0-2)

Is the PRD scoped to a coherent set of capabilities, or does it bundle
unrelated work?

When multiple capabilities are present, test independence: could each
ship on its own and provide value? Capabilities that cannot function
without each other are one feature regardless of how many user stories
they span.

- 0 = Bundles 3+ independent capabilities that serve different personas or purposes
- 1 = Bundles 1-2 separable capabilities that could ship independently
- 2 = Focused — capabilities require each other to function

**Calibration examples:**

- R=0: "Add storage support, networking policy enforcement, and cluster monitoring for CaaS." — three independent capabilities for different concerns.
- R=0: "East-west connectivity: Ethernet fabric provisioning, InfiniBand tenant isolation, NVLink partition management, VPC peering, and cross-fabric validation." — five independent capabilities that each serve different fabric types and could ship independently. This should be split into individual features per fabric type.
- R=1: "Add CaaS cluster storage and add tenant storage quota management." — storage provisioning and quota management serve different workflows (day-1 vs day-2) and could ship independently.
- R=2: "CaaS cluster storage: automatic provisioning, readiness visibility, and cleanup on deletion." — provisioning without visibility is incomplete; cleanup without provisioning is meaningless. Tightly coupled.

When a PRD scores 0, recommend restructuring as an epic with individual
features that can be prioritized, estimated, and delivered independently.

#### 5. Testability — Verifiable requirements? (0-2)

Can the requirements be verified by a PM or QA engineer using the product?

- 0 = Requirements describe activities or system internals that can't be tested from the outside
- 1 = Some requirements are testable, others are vague or describe internal behavior
- 2 = Every requirement and acceptance criterion can be verified by using the product

**Calibration examples:**

- T=0: "The controller reconciles within 30 seconds" and "The finalizer is removed after cleanup completes" — not observable by users.
- T=1: "Tenants can create PVCs on CaaS clusters" (testable) mixed with "The AAP job succeeds and StorageClasses are confirmed" (internal).
- T=2: "A tenant can create a PVC using a StorageClass on their CaaS cluster within 5 minutes of the cluster becoming ready." — observable, measurable, testable.

### Pass/Fail

- **PASS**: Total >= 7/10 AND no zeros on any criterion
- **FAIL**: Total < 7 OR any zero (automatic fail regardless of total)

A single zero is an automatic fail because it signals a fundamental problem
(e.g., the PRD is a design doc, or requirements are untestable). The author
must fix zero-scored criteria before resubmission. Exception: if WHAT
scores zero because the work is content-only (docs, examples, config
samples), the recommendation is to track it as a Jira task, not resubmit
as a PRD.

## Output Format

Present findings as a structured review:

```markdown
## PRD Review: {title}

### Rubric Scores

| Criterion | Score | Notes |
|-----------|-------|-------|
| WHAT (clear need) | X/2 | {explain what need is described and how clearly; note persona/dimension coverage} |
| WHY (justification) | X/2 | {cite the specific evidence found or note its absence} |
| User-Facing Focus | X/2 | {note any design leakage or lack thereof} |
| Right-Sized | X/2 | {assess scope — independent capabilities?} |
| Testability | X/2 | {which requirements are verifiable by using the product?} |
| **Total** | **X/10** | **PASS / FAIL** |

### Verdict: {PASS / FAIL}

{1-2 sentence assessment. If fail, name the zero-scored criteria first.}

### Findings

#### Critical (must fix — zero-scored criteria)
1. {finding with specific section reference, quote the problematic text, suggest a user-focused rewrite}

#### Important (should fix)
1. {finding with specific section reference and suggestion}

#### Suggestions (nice to have)
1. {finding}

### Criterion Details

{For each criterion, explain the score with specific quotes from the PRD.
Show what's good and what needs improvement. For design leakage, quote the
offending text and show what a user-focused rewrite would look like.}
```

## Severity Classification

- **Critical**: Any zero-scored criterion. Also: missing required sections, no personas identified, PRD reads like a design document.
- **Important**: Score of 1 on any criterion. Also: vague non-goals, weak acceptance criteria, scope creep signals, requirements stated as generic capabilities without explicit use cases.
- **Suggestion**: Style improvements, additional non-goals, deeper risk analysis, more specific metrics.

## Notes

- Score based on what's in the PRD, not what you think should be there — if information is genuinely unavailable, "TBD" markers are acceptable
- The WHAT criterion uses `osac-dimensions.md` to check persona and dimension coverage — but features that don't touch networking shouldn't be penalized for not addressing networking
- Compare against the PRD template at `enhancement-proposals/guidelines/prd_template.md` for structural compliance
- See `enhancement-proposals/guidelines/prd_guide.md` for the author-facing guidance this rubric is calibrated against
- A PRD that names specific controllers, playbooks, env vars, or internal conditions has design leakage. This is the most common failure mode — score it under User-Facing Focus
- If the PRD was produced by `/prd:draft`, check that clarification locked decisions are reflected

$ARGUMENTS
