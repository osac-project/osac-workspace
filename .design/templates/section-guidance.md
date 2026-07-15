# OSAC Design Document (EP) — Section Guidance

Instructions for the AI on how to fill each section of the OSAC design template.
This file is read during the `/draft` phase. It is not included in the final output.

## General Rules

These apply across all sections:

- **Favor conciseness.** Long design documents don't get read. Every sentence should earn its place.
- Write in third person, present tense.
- **Be specific.** No vague language: "efficient data structure" -> name the structure. "Appropriate caching" -> specify the cache strategy and invalidation approach. "Standard error handling" -> define the error taxonomy.
- Every design decision must be traceable to source material. Use source markers at the end of statements: `[PRD: FR-3]`, `[PRD: NFR-2]`, `[PRD: §2.1]`, `[Locked: D{N}]`, `[User]`, `[Assumption]`, `[Codebase: path/to/file]`.
- **Consolidate markers.** When most design decisions trace to the same PRD, tagging every statement with `[PRD: §X.Y]` adds noise without aiding traceability. Instead:
  - Tag each decision with its specific source(s) only when the source is non-obvious or differs from the primary PRD.
  - Rely on the YAML frontmatter's `tracking-link` and `prd` fields for the overall reference.
  - Reserve inline markers for clarification-derived changes (`[Locked: D{N}]`), direct user instructions (`[User]`), codebase-derived decisions (`[Codebase: ...]`), and assumptions (`[Assumption]`).
- **Incorporate, don't narrate.** When a clarification or PRD revision changed the scope or corrected an assumption, write the design decision in its final form. Do not describe what the original PRD said, what was removed, or why a previous position was abandoned.
- Do NOT invent requirements. If the PRD doesn't specify something, either mark it as an assumption or flag it as an open question.
- If information is unavailable, write "To be determined — {what's needed}".
- **No scope reduction.** Never use "simplified version", "v2", "placeholder", or "future enhancement" to silently reduce scope. If something won't fit, say so explicitly and propose a split.
- **Formatting restraint.** Use bold sparingly for genuine emphasis. When every noun phrase is bold, nothing stands out.
- **Diagrams:** Use Mermaid diagrams when they add clarity. Any Mermaid diagram type is allowed. Every diagram **must** be accompanied by narrative explaining what it shows and what the reader should take away.
  - Keep diagrams simple: labeled nodes, clear edge labels, no styling directives (`style`, `classDef`, color codes).
  - Do not use ASCII art or PlantUML.
- **Keep all required headers.** The enhancement-proposals repo enforces required sections via a linter CI job. If a section does not apply, explain why but do not remove it.

## Per-Section Guidance

### YAML Frontmatter

- **title**: Lowercase slug with hyphens (e.g., `networking-api`, `bare-metal-fulfillment`)
- **authors**: Email addresses (e.g., `agentil@redhat.com`)
- **creation-date**: ISO date format (YYYY-MM-DD)
- **last-updated**: ISO date format, update when making significant changes
- **tracking-link**: Full Jira URL (e.g., `https://redhat.atlassian.net/browse/OSAC-356`)
- **prd**: Relative path to the PRD document (typically `prd.md`)
- **see-also**: Related enhancements as paths (e.g., `/enhancements/networking`)
- **replaces/superseded-by**: Usually `N/A` for new proposals

### Summary

1-2 sentences. What this design achieves and the technical approach. End with a PRD reference: "See [PRD](prd.md) for detailed requirements." A reader should understand the scope of this document after reading only this section.

### Motivation

2-4 paragraphs. Restate the problem in implementation terms for technical reviewers. Explain the current system's limitations and why this approach is proposed.

Do NOT include user stories — those are in the PRD. Do not duplicate the PRD's problem statement. Bridge from it: assume the reader may not have read the PRD and needs enough context to understand the design decisions, but direct them to the PRD for the full picture.

### Goals

- Design-scoped goals that constrain the implementation approach, not product outcomes. "Reuse the existing controller reconciliation pattern" is a design goal. "Tenants can create VirtualNetworks" is a product goal (belongs in the PRD).
- 3-5 goals, each one sentence.

### Non-Goals

- Prevent scope creep at the implementation level. "Multi-region support" or "quota enforcement" are typical OSAC non-goals.
- 2-4 non-goals, each one sentence.

### Proposal

1-2 paragraphs introducing the key resources/APIs at a high level. Explain how they relate and why each is needed. For OSAC, this typically means naming the new CRDs, gRPC services, and controller changes.

### Workflow Description

- Define actors using OSAC personas (Provider, Tenant, Admin).
- Enumerate the steps a user takes to use the feature, starting from a defined starting state.
- Be explicit about APIs involved (gRPC, REST, kubectl).
- Include error handling and alternative paths (what if resource already exists? what if quota exceeded?).
- Use Mermaid sequence diagrams for multi-step interactions.

### API Extensions

For OSAC, this typically includes:
- New gRPC services in fulfillment-service (e.g., `VirtualNetworks`, `Subnets`)
- New CRDs in osac-operator (e.g., `VirtualNetwork`, `Subnet`)
- Webhooks for validation/defaulting
- Finalizers for cleanup
- Changes to existing resources owned by other teams

List each extension and note operational impact (what happens if the controller is down?).

### Implementation Details/Notes/Constraints

This is where technical depth lives. Include:
- Proto schema snippets following the standard object shape (`id`, `Metadata`, `<Type>Spec`, `<Type>Status`) and conventions in [`fulfillment-service/docs/API.md`](../../fulfillment-service/docs/API.md) — spec for desired state, status for observed state, conditions for lifecycle, declarative design (no imperative methods)
- Database schema considerations (new tables, migrations)
- Controller reconciliation logic (state machine, finalizer flow)
- Integration with existing OSAC components (fulfillment-service, osac-operator, osac-aap)

### Security Considerations

- Cover input validation, authentication/authorization changes, and data exposure risks.
- For multi-tenant features, describe how tenant isolation is enforced: OPA policies, namespace scoping, `osac.openshift.io/tenant` annotation filtering.
- If the feature inherits the existing security model without changes, state that and explain why it's sufficient.
- Do not invent security concerns that don't apply.

### Failure Handling and Recovery

- Enumerate concrete failure modes (not generic categories).
- For each: what happens, how the system recovers, what the user sees.
- Cover controller-side failures (reconciliation errors, stale caches), API-side failures (validation, database errors), and integration failures (AAP job timeouts, network provisioning failures).
- Note retry behavior and idempotency guarantees.
- For controllers: describe behavior when the controller is restarted mid-reconciliation.

### RBAC / Tenancy

- All new resources MUST include tenant isolation metadata: `osac.openshift.io/tenant` for tenant scoping, `osac.openshift.io/owner-reference` for resource hierarchy.
- Describe how OPA policies enforce isolation at runtime.
- Note visibility constraints: can a tenant see resources from other tenants? What about platform-defined resources (NetworkClass, PublicIPPool)?
- If no RBAC or tenancy changes: "No RBAC or tenancy changes required." with brief justification.

### Observability and Monitoring

- List new Prometheus metrics, Kubernetes events, and structured log events.
- For metrics: name, type (counter/gauge/histogram), labels, and what threshold indicates a problem.
- For events: type (Normal/Warning), reason, and when it fires.
- If none: "No new observability changes. Existing monitoring mechanisms apply."

### Risks and Mitigations

- Technical risks only (product risks are in the PRD).
- Each risk should have a concrete mitigation strategy or be flagged as "To be determined."
- Consider: version skew, performance bottlenecks, security exposure, backwards compatibility, cross-component coordination.

### Drawbacks

- Steel-man argument against the proposal.
- What trade-offs must be made? Maintenance burden? API complexity?
- How do we justify them?

### Alternatives (Not Implemented)

- At least one alternative for each non-trivial design decision.
- Include "Do nothing" if applicable.
- For each: brief description, pros, cons, rejection reason.
- Be honest about trade-offs.

### Open Questions

- Each open question gets its own numbered subsection.
- Frame as clear, answerable questions directed at reviewers.
- **Transient by design.** When resolved during PR review, the answer is incorporated into the relevant section and the entry removed.
- **Design scope only.** No process-level actions.
- This section is **optional**. If no open questions remain after drafting, omit it entirely.

### Test Plan

- Describe the testing strategy: unit, integration (kind cluster), e2e.
- Call out tricky areas: CIDR parsing, dual-stack, concurrent reconciliation.
- Reference OSAC test patterns: Ginkgo for unit/integration tests, pytest for e2e (via osac-test-infra).
- If details depend on implementation: "Test plan will be developed during implementation. Expected coverage: [describe what will be tested]."

### Graduation Criteria

- If not targeting a release: "Graduation criteria will be defined when targeting a release. Expected stages: Dev Preview -> Tech Preview -> GA based on production deployment feedback."
- If targeting a release: define maturity levels and success signals.

### Upgrade / Downgrade Strategy

- For new APIs: "This is a new API with no upgrade impact. Downgrade requires deleting all instances of the new resources before reverting."
- For changes to existing APIs: describe migration steps and backward compatibility.

### Version Skew Strategy

- Describe how fulfillment-service and osac-operator handle version skew during upgrades.
- Note any CRD version migration requirements.

### Support Procedures

- Failure detection: describe symptoms (events, metrics, alerts, log output).
- Disabling: how to disable the feature and consequences on cluster health, existing workloads, and new workloads.
- Recovery: how to re-enable and whether consistency is maintained.

### Infrastructure Needed

- Usually "None" for OSAC EPs.
- If needed: specify new test infrastructure, repos, or CI changes.
