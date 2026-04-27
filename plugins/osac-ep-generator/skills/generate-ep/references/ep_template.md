# OSAC Enhancement Proposal — Section Completion Guide

> **Template source**: Read the upstream template directly from `enhancement-proposals/guidelines/enhancement_template.md`.
> Do NOT use a cached copy — always read the live file to pick up any changes.

This file provides guidance on completing each section of the template, based on analysis of successful OSAC enhancement proposals (Networking, Bare Metal Fulfillment, VMaaS).

---

### YAML Frontmatter

- **title**: Lowercase slug with hyphens (e.g., `networking-api`, `bare-metal-fulfillment`, `vmaas`)
- **authors**: Email addresses (e.g., `agentil@redhat.com`)
- **creation-date**: ISO date format (YYYY-MM-DD)
- **last-updated**: ISO date format, update when making significant changes
- **tracking-link**: YAML list of full Jira URLs (even for one item):
  ```yaml
  tracking-link:
    - https://issues.redhat.com/browse/MGMT-22637
  ```
- **see-also**: Related enhancements as paths (e.g., `/enhancements/networking`)
- **replaces/superseded-by**: Usually `N/A` for new proposals

### Summary (1 paragraph)

Good summaries are 3-5 sentences that answer: What is being added? Why is it valuable? What are the key capabilities? Reference patterns from existing EPs:
- Networking EP: Describes API resources (VirtualNetwork, Subnet, SecurityGroup), dual-stack support, and pluggable NetworkClass architecture
- Bare Metal EP: Explains the fulfillment process, key resources (HostPool, Host, HostClass), and tenant workflow
- VMaaS EP: Defines the service goal (self-service VM creation), key APIs (ComputeInstance, ComputeInstanceTemplate), and distinguishes from VDCaaS

### User Stories (at least 3-5)

Split into personas (Provider, Tenant, Admin). Each story follows the formula: "As a [role], I want to [action] so that I can [goal]". Good stories are specific and outcome-focused:
- Provider stories: Define resource classes, mark hosts available, configure templates
- Tenant stories: List available resources, create resources with parameters, manage lifecycle, access specialized hardware
- Admin stories: Monitor, troubleshoot, enforce quotas

### Goals (3-7 bullet points)

Goals describe what success looks like from the user's perspective. They are measurable and user-focused, not implementation details. Examples:
- "Provide a self-service API for tenants to create VirtualNetworks with IPv4, IPv6, or dual-stack CIDRs"
- "Support pluggable networking backends through NetworkClass"
- "Enable tenants to request bare metal hosts by resource class with custom network configuration"

### Non-Goals (2-5 bullet points)

Explicitly state what is deferred or out of scope. This prevents scope creep and focuses discussion. Common non-goals in OSAC EPs:
- Advanced orchestration features (auto-scaling, multi-region)
- Quota systems (deferred to separate proposal)
- Backup/disaster recovery
- Marketplace integrations

### Proposal (high-level overview)

Introduce the key resources/APIs at a high level (1-2 paragraphs per resource). Explain how they relate and why each is needed. Reference the Networking EP pattern:
- VirtualNetwork = tenant's isolated network (like AWS VPC)
- Subnet = subdivision with CIDR
- SecurityGroup = stateful firewall
- NetworkClass = pluggable backend (provider-defined)

### Workflow Description (step-by-step)

Define actors (cluster creator, tenant, provider) and enumerate the steps a user takes to use the feature. Be explicit:
1. Tenant creates VirtualNetwork with CIDR
2. Tenant creates Subnet within VirtualNetwork
3. Tenant creates SecurityGroup with rules
4. Tenant attaches ComputeInstance to Subnet and SecurityGroup

Include error handling and alternative paths (what if resource already exists? what if quota exceeded?).

### API Extensions

For OSAC, this typically means:
- New gRPC services in fulfillment-service (e.g., `VirtualNetworks`, `Subnets`)
- New CRDs in osac-operator (e.g., `VirtualNetwork`, `Subnet`)
- Webhooks for validation/defaulting
- Finalizers for cleanup

List each extension and its operational impact.

### Implementation Details

This is where technical depth lives. Include:
- Proto schema snippets (fields, enums, validation)
- Database schema considerations
- Controller reconciliation logic
- Integration with existing OSAC components (fulfillment-service, osac-operator, osac-aap)

The Networking EP is 818 lines — deep technical detail is expected here.

### Risks and Mitigations

Identify technical risks (version skew, performance bottlenecks, security concerns) and explain how they're mitigated. Examples:
- Risk: IPv6 adoption is low, dual-stack adds complexity → Mitigation: Make IPv6 optional, support IPv4-only mode
- Risk: SecurityGroup rules could create network isolation bugs → Mitigation: Default-allow within VirtualNetwork, explicit deny between VirtualNetworks

### Drawbacks

This is the "steel man" argument against the proposal. What are the costs (maintenance burden, API complexity, user confusion)? How do we justify them? Examples:
- NetworkClass adds abstraction complexity → Justified by need for pluggable backends
- Dual-stack support increases testing surface → Justified by multi-cloud parity

### Alternatives

Describe other approaches considered and why they were rejected. Examples:
- Alternative: Single global network per tenant → Rejected: No isolation between workloads
- Alternative: Flat network model without Subnets → Rejected: Doesn't scale, no CIDR subdivision

### Test Plan

Describe the testing strategy (unit, integration, e2e). Call out tricky areas:
- Unit tests: Proto validation, CIDR parsing, SecurityGroup rule evaluation
- Integration tests: VirtualNetwork creation, Subnet attachment, PublicIP allocation
- E2e tests: Full workflow from EP creation to running workload

If details depend on implementation, write: "Test plan will be developed during implementation. Expected coverage: [describe what will be tested]."

### Graduation Criteria

If not targeting a release, write: "Graduation criteria will be defined when targeting a release. Expected stages: Dev Preview → Tech Preview → GA based on production deployment feedback."

If targeting a release, define maturity levels (alpha/beta/GA) and success signals.

### Upgrade/Downgrade Strategy

For new APIs, typically write: "This is a new API with no upgrade impact. Downgrade requires deleting all instances of the new resources (VirtualNetwork, Subnet, etc.) before reverting."

For changes to existing APIs, describe migration steps and backward compatibility.

### Version Skew Strategy

Describe how components will handle version skew during upgrades. Example: "fulfillment-service and osac-operator must be upgraded together. CRD schema supports both v1alpha1 and v1 API versions during migration period."

### Support Procedures

Describe how to detect and resolve issues in production:
- Failure modes: "VirtualNetwork stuck in Pending → Check osac-operator logs for reconciliation errors"
- Disabling: "To disable the Networking API, scale osac-operator to 0 replicas. Existing VirtualNetworks will persist but not reconcile."
- Recovery: "Re-enable by scaling osac-operator back to 1 replica. Controller will resume reconciliation without data loss."

### Infrastructure Needed

Usually "None" for OSAC EPs. If needed, specify: "New test infrastructure for dual-stack networking" or "Additional GitHub repo for networking-specific documentation."
