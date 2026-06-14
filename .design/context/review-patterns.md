# OSAC Enhancement Proposal Review Patterns

Common review feedback patterns from past OSAC EP PRs. Both `/prd:draft` and
`/design:draft` should anticipate these expectations when producing documents.

## Reviewer Expectations

### Completeness
- All template sections must be present, even if marked "TBD" or "N/A"
- User stories should cover all four OSAC personas (see `osac-dimensions.md`)
- Implementation details should be thorough — successful EPs are 400-800 lines
- Test plans should describe strategy, not just "tests will be added"

### Clarity
- Technical terms should be defined upfront (see Networking EP's Terminology section)
- Relationships between resources should be explicit (parent-child, ownership, scope)
- Workflows should enumerate steps with actor roles clearly defined

### Consistency with OSAC Patterns
- New APIs should follow existing fulfillment-service patterns (gRPC + REST, proto schemas)
- Resources should include tenant isolation metadata (annotations for tenant-id, owner-reference)
- Controller patterns should align with osac-operator conventions
- Integration with osac-aap should be described for provisioning workflows
- Pluggable architectures (like NetworkClass) are preferred over hardcoded implementations

## Frequent Feedback Themes

| Theme | Anti-Pattern | Better Approach |
|-------|-------------|-----------------|
| Missing alternatives | No "Alternatives" section or only strawman options | Explain other approaches considered and why they were rejected |
| Vague non-goals | "Advanced features are out of scope" | "Auto-scaling and multi-region placement are out of scope — addressed in a separate proposal" |
| Implementation-focused user stories | "As a tenant, I want the VirtualNetwork CRD to have a CIDR field" | "As a tenant, I want to define an isolated network with my own IP address space so I can control my network topology" |
| Placeholder test plans | "Unit and integration tests will be added" | "Unit tests for proto validation and CIDR parsing; integration tests for VirtualNetwork creation and Subnet attachment; e2e tests for full networking stack" |
| Generic risks | "Risk: Implementation might have bugs" | "Risk: IPv6 dual-stack adds testing complexity. Mitigation: Make IPv6 optional, support IPv4-only mode" |
| Inconsistent terminology | "Floating IP" / "PublicIP" / "External IP" used interchangeably | Define terms in a Terminology section and use consistently |
| Workflow gaps | Jumps from creation to deletion | Include all lifecycle operations (create, read, update, delete, start/stop) |

## EP Reference Library

Existing EPs as quality benchmarks:

| Slug | Description | Lines | Notable Patterns |
|------|-------------|-------|------------------|
| `networking` | Networking API with VirtualNetwork, Subnet, SecurityGroup, PublicIP | 818 | Terminology section, dual-stack IPv4/IPv6, NetworkClass pluggable architecture |
| `bare-metal-fulfillment` | Bare metal provisioning with HostPool, Host, HostClass | ~400 | ESI integration, serial console, network attachment at interface level |
| `vmaas` | VM as a Service with ComputeInstance and ComputeInstanceTemplate | ~300 | Template-based provisioning, GPU support, live migration |
| `organizations` | Multi-tenancy organization model | ~300 | Tenant isolation, RBAC patterns |
| `tenant-specific-storageclasses` | Tenant-scoped storage class management | ~200 | Provider/tenant resource split pattern |
| `computeinstance-phase-condition-expansion` | ComputeInstance status and lifecycle updates | ~200 | API evolution pattern for existing resources |

Key takeaways:
- Networking EP (818 lines) sets the bar for technical depth
- All EPs follow the template structure exactly (no skipped sections)
- Successful EPs define terminology upfront and use it consistently

## Key Reviewers by Domain

| Domain | Reviewers |
|--------|-----------|
| Networking | adriengentil, eranco74, larsks, AlonaKaplan |
| Bare Metal | tzumainn, eranco74 |
| VMaaS | adriengentil, akshaynadkarni, hpdempsey |

## Review Process

- At least 2 approvals required for merge
- Address each comment explicitly (update the proposal or explain why not)
- Don't resolve comments yourself — let the reviewer resolve after confirming
- Update `last-updated` frontmatter field when making changes
- If architectural disagreement stalls the PR, escalate to synchronous discussion
