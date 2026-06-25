# PRD Section Guidance (OSAC)

Instructions for the AI on how to fill each section of the PRD template.
This file is read during the `/draft` phase. It is not included in the
final output.

## General Rules

- **A PRD defines what the product must do, not how it is built.** Every
  statement should be verifiable by a Product Manager using the product.
  Implementation details (which controller, which API field, which
  playbook) belong in the design document.
- **Favor conciseness.** Write enough to communicate clearly and no more.
  Long PRDs don't get read.
- Write in third person, present tense.
- Be specific about outcomes, not about mechanisms.
- Do not invent features, constraints, or details not supported by the
  ingested requirements or clarification responses.
- If information for a section is genuinely unavailable after clarification,
  write "To be determined" rather than fabricating content.
- Use bold sparingly for genuine emphasis.
- Use Mermaid diagrams only when a visual clarifies a user workflow.
  Do not diagram internal system architecture (that's design).
- Source markers (`[Jira: ...]`, `[Clarify: ...]`, `[User]`) follow the
  same consolidation rules as the default guidance: rely on the metadata
  table's Jira link for the overall reference, tag only non-obvious sources.

### Design Leakage

A PRD has strayed into design if it:

- Names specific API fields, CRD field paths, or condition names
  (e.g., `ClusterStorageReady`, `status.clusterStorage[]`)
- Names controllers, reconcilers, or internal components
  (e.g., "the storage controller places a finalizer")
- Names playbooks, AAP templates, or env vars
  (e.g., `osac-create-tenant-cluster-storage`, `STORAGE_TIERS`)
- Describes behavior only observable by reading code or logs
  (e.g., "the controller polls every 30s")
- Specifies implementation mechanisms
  (e.g., "passes kubeconfig as AAP extra vars")

When you catch yourself writing any of the above, rewrite the statement
as a user-observable outcome. The litmus test: could a PM verify this
by using the product?

**Design-flavored (avoid):**
> When a ClusterOrder reaches phase=Ready and the owning Tenant has
> StorageBackendReady=True, the storage controller invokes
> osac-create-tenant-cluster-storage with provisioning_target=hcp_data_plane.

**User-focused (preferred):**
> When a CaaS cluster is provisioned and ready, persistent storage is
> automatically available on the cluster without manual configuration.

## 1. Problem Statement

- Lead with the user's pain, not the solution.
- Name the affected personas (see `.design/context/osac-dimensions.md`).
- Quantify impact if the source material supports it.
- Explain the cost of inaction.
- Keep to 3-5 sentences.

## 2. Goals and Non-Goals

### 2.1 Goals

- Goals must be **user-observable outcomes**, not activities or
  implementation milestones.
- "Tenant users can create PVCs on CaaS clusters" is a goal.
  "Install CSI driver via AAP playbook" is an implementation step.
- Limit to 3-5 goals.

### 2.2 Success Metrics

- This subsection is **optional**. If the source material provides no
  quantifiable targets, omit it.
- Metrics should be user-observable (e.g., "time from cluster ready to
  storage available < 5 minutes"), not internal (e.g., "reconciliation
  loop completes in < 1s").

### 2.3 Non-Goals

- Non-goals prevent scope creep. Include anything a reasonable reader
  might assume is in scope but isn't.
- Non-goals should reference capabilities, not implementation artifacts.
  "Storage backend configuration" not "StorageBackend API integration."

## 3. Capabilities

This section replaces the traditional "Functional Requirements" with
user stories grouped by persona or workflow.

- Write as: **"As a [persona], when [trigger], [outcome]."** Or simply
  state what the user can do or observe.
- Group related stories under descriptive headings (by persona or
  workflow stage), not by internal subsystem.
- No stable IDs (FR-N) needed. Stories are self-describing.
- Each capability should answer: "What can the user do that they
  couldn't do before?"
- Do not describe how the system achieves the outcome internally.
  That belongs in the design document.

**Good:**
> As a Tenant User, when my CaaS cluster is ready, I can create PVCs
> using per-tier StorageClasses without any manual storage setup.

**Bad:**
> FR-5: The storage controller sets a ClusterStorageReady condition
> on the ClusterOrder CR: True when the AAP job succeeds and all
> expected StorageClasses are present.

### 3.1 Operational Expectations

- This subsection is **optional**. Include only quality constraints
  that are observable by users or operations teams.
- "Storage setup completes within 5 minutes" is operational.
  "Controller uses 30s poll interval" is implementation.
- "Credentials are never exposed in user-visible error messages" is
  operational. "Controller logs must not contain Secret contents" is
  implementation (log formats are design).
- Common categories: performance, security, reliability.

## 4. Acceptance Criteria

- These define **done** from the user's perspective.
- Each criterion should be verifiable by a PM or QA engineer using
  the product, not by reading code or inspecting internal state.
- Write as checkboxes. Each should be independently verifiable.
- Do not repeat capabilities as checkboxes. Acceptance criteria should
  describe end-to-end scenarios that prove the capabilities work.
- Cover the primary use cases. Edge cases belong in a test plan.

**Good:**
> A tenant user can create a PVC on a newly provisioned CaaS cluster
> without manual storage configuration.

**Bad:**
> ClusterStorageReady=True on ClusterOrder when setup succeeds.

## 5. Assumptions

- This section is **optional**.
- An assumption is a statement the PRD treats as true but that has
  not been confirmed. If it turns out to be false, one or more
  capabilities may need to change.
- Good assumptions surface hidden preconditions.
- Do not list things that are verifiable right now.

## 6. Dependencies

- This section is **optional**.
- List teams, services, or external work that this effort depends on
  or that depends on this effort.
- Include ordering constraints.
- Reference the dependency by name and ticket, not by implementation
  details.

## 7. Risks

- Each risk gets its own numbered subsection with **Owner** and
  **Mitigation** fields.
- Product scope only. Process-level risks belong in project
  management tools.
- This section is **optional**.

## 8. Open Questions

- Each open question gets its own numbered subsection with **Owner**
  and **Impact** fields.
- Frame as clear, answerable questions directed at reviewers.
- Product scope only. Implementation questions belong in the design
  document.
- This section is **optional**. Transient by design: resolved
  questions are incorporated into the PRD body and removed.
