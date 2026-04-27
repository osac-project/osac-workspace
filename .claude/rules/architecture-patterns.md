# Architecture Patterns

## Multi-tenancy

All resources include tenant isolation metadata:
- `metadata.annotations["osac.openshift.io/tenant"]` for tenant scoping
- `metadata.annotations["osac.io/owner-reference"]` for resource hierarchy
- OPA policies enforce isolation at runtime
- Never skip tenant isolation metadata in new resources
- Use annotations for owner references, not separate fields

## Resource Hierarchy

```text
Cluster Resources:
  ClusterOrder → provisions OpenShift clusters via Hosted Control Planes

Compute Resources:
  ComputeInstance → KubeVirt VM, attached to Subnets + SecurityGroups

Networking Resources:
  NetworkClass (platform-defined, read-only for tenants)
  └── VirtualNetwork (tenant L2 network with CIDR)
        ├── Subnet (CIDR range within VirtualNetwork)
        └── SecurityGroup (firewall rules scoped to VirtualNetwork)

Public IP Resources:
  PublicIPPool (platform-defined, IP address ranges)
  └── PublicIP (allocated from pool, optionally attached to ComputeInstance)

Tenant Resources:
  Tenant → namespace and resource isolation
```

Parent-child relationships use owner reference annotations (`osac.io/owner-reference`).

## Service Stack (fulfillment-service)

- PostgreSQL for persistent storage
- gRPC with grpc-gateway for REST/JSON support
- Controller-runtime for Kubernetes integration
- OPA for authorization policies
- Prometheus for metrics

## Integration Testing (fulfillment-service)

- Kind clusters (named "fulfillment-service-it")
- TLS with SNI routing via Envoy Gateway
- Keycloak for authentication
- Requires `/etc/hosts` entries:
  - `127.0.0.1 keycloak.keycloak.svc.cluster.local`
  - `127.0.0.1 fulfillment-api.osac.svc.cluster.local`
- Use `IT_KEEP_KIND=true` to preserve cluster for debugging
- Clean up with: `kind delete cluster --name fulfillment-service-it`

## Detailed References

For deeper architecture, conventions, and structure analysis:
- `.planning/codebase/ARCHITECTURE.md` — system design and layers
- `.planning/codebase/CONVENTIONS.md` — naming and coding patterns
- `.planning/codebase/STACK.md` — technology stack details
- `.planning/codebase/TESTING.md` — test patterns and frameworks
- `.planning/codebase/STRUCTURE.md` — file organization
- [`docs/architecture/`](https://github.com/osac-project/docs/tree/main/architecture) — high-level diagrams and design documents
- [`enhancement-proposals/`](https://github.com/osac-project/enhancement-proposals) — RFCs and design proposals
