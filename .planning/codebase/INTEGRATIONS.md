# External Integrations

**Analysis Date:** 2026-03-30

## APIs & External Services

**Kubernetes/OpenShift:**
- OpenShift Container Platform - Deployment target for production
  - SDK: github.com/openshift/hypershift/api - HyperShift for hosted control planes (`osac-operator/go.mod`)
  - SDK: github.com/openshift/api - OpenShift API extensions
  - Purpose: Cluster provisioning and management via HyperShift

**Infrastructure Provisioning:**
- AWS (Amazon Web Services)
  - SDK: boto3, aiobotocore (Python) - Infrastructure provisioning
  - Auth: AWS credentials (via AWS_* environment variables or IAM roles)
  - Purpose: Compute, networking, and storage provisioning

- OpenStack
  - SDK: openstacksdk, python-openstackclient - Infrastructure management
  - Auth: OpenStack credentials (Keystone authentication)
  - Purpose: Virtual machine and networking provisioning

- Ironic (Bare Metal Service)
  - SDK: python-ironicclient - Bare metal node management
  - Auth: OpenStack/Keystone credentials
  - Purpose: Physical server provisioning and control

- ESI (Emergence System Initiative)
  - SDK: esisdk, python-esiclient - Specialized infrastructure
  - Auth: Keystone/OpenStack credentials
  - Purpose: Advanced infrastructure provisioning workflows

- ESI LEAP
  - SDK: python-esileapclient - Location-based resource provisioning
  - Auth: OpenStack credentials
  - Purpose: Distributed edge infrastructure management

**Networking:**
- OVN (Open Virtual Network)
  - SDK: github.com/ovn-org/ovn-kubernetes/go-controller (`osac-operator/go.mod`)
  - Purpose: Advanced SDN networking for Kubernetes

- Envoy Gateway
  - SDK: github.com/envoyproxy/go-control-plane/envoy - Service proxy control
  - Configuration: Via Authorino AuthConfig manifests (`fulfillment-service/charts/service/templates/grpc-server/authconfig.yaml`)
  - Purpose: TLS/SNI routing, advanced traffic management

## Data Storage

**Databases:**
- PostgreSQL 15+
  - Connection: `--db-url` flag (format: `postgres://user:pass@host:5432/db`)
  - Client: github.com/jackc/pgx/v5 - Native PostgreSQL driver
  - ORM/Query: Direct SQL via pgx (type-safe generic DAO pattern)
  - Location: `fulfillment-service/internal/database/`
  - Purpose: Persistent storage for all infrastructure resources (clusters, hosts, networks)

**File Storage:**
- Local filesystem only - No external file storage service
- Kubernetes ConfigMaps/Secrets for configuration storage

**Caching:**
- None detected - Services use direct database queries with CEL filtering

## Authentication & Identity

**Auth Provider:**
- Keycloak (Optional, configurable)
  - Implementation: JWT token validation
  - Helm chart: `fulfillment-service/charts/keycloak/`
  - Auth types: guest (no auth) or external (JWT-based)
  - Configuration: `--grpc-authn-type` flag (guest or external) and `--grpc-authn-external-address` flag
  - Location: `fulfillment-service/internal/auth/`
  - Purpose: OIDC/OpenID Connect identity provider for users

**Custom Implementation:**
- Guest authentication (no verification)
- Service account authentication (Kubernetes ServiceAccount tokens)
- Multi-tenancy enforcement via annotations: `osac.openshift.io/tenant` and `osac.openshift.io/owner-reference`
- Location: `fulfillment-service/internal/auth/auth_*.go`

**Token Management:**
- JWT validation: github.com/golang-jwt/jwt/v5
- Token sources: File-based (`auth_file_token_source.go`) or memory-based (`auth_memory_token_store.go`)
- External Auth Service: gRPC Envoy ext_authz protocol support for external authorization

## Authorization

**Policy Engine:**
- Open Policy Agent (OPA) v1.14.1
  - Purpose: Fine-grained authorization policies
  - Integration: Runtime policy enforcement
  - Location: `fulfillment-service/internal/` (authorization integration)
  - Configuration: OPA policies (location not visible in Go code)

**Tenancy Logic:**
- Three modes: guest, default, serviceaccount
- Tenant isolation via resource annotations and OPA policies
- Configuration: `--tenancy-logic` flag

## Monitoring & Observability

**Error Tracking:**
- None detected - No external error tracking service (Sentry, DataDog, etc.)
- Internal error handling via context-based error propagation

**Logs:**
- slog (structured logging library)
  - Framework: standard Go log/slog
  - Output: stdout/stderr (typical Kubernetes container logs)
  - Format: Structured JSON-compatible
  - Configuration: `--log-level` flag (debug, info, warn, error)
  - Location: `fulfillment-service/internal/logging/`

**Metrics:**
- Prometheus
  - Client: github.com/prometheus/client_golang v1.23.2
  - Metrics endpoint: `/metrics` on metrics listener (default `localhost:8080`)
  - Helm chart: `fulfillment-service/charts/prometheus/`
  - Configuration: `fulfillment-service/charts/prometheus/files/prometheus.yml`
  - gRPC metrics: Automatic collection via interceptor chain (`fulfillment-service/internal/metrics/grpc_metrics_interceptor.go`)
  - Purpose: Performance monitoring, request latency, error rates

**Tracing:**
- OpenTelemetry support detected in osac-operator (`go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp`)
- No active span/trace collector configured in fulfillment-service

## CI/CD & Deployment

**Hosting:**
- Kubernetes-native deployment (Kind for testing, OpenShift for production)
- Helm-based deployment (`fulfillment-service/charts/service/`)
- Kustomize overlays for alternative deployment (`fulfillment-service/manifests/`)

**CI Pipeline:**
- GitHub Actions (implied by gh CLI references in CLAUDE.md)
- No explicit CI pipeline files visible in codebase
- Operator SDK v1.39.1 for operator bundle generation and OLM publication

**Container Registry:**
- Default: ghcr.io (GitHub Container Registry) for osac-operator
- Build targets: `image-build`, `image-push` via Makefile
- Container tool: Podman (default) or Docker

## Environment Configuration

**Required Environment Variables:**
- None required at runtime - All configuration via command-line flags
- PostgreSQL connection details passed via `--db-url` flag

**Optional Environment Variables:**
- AWS credentials: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` (for osac-aap)
- OpenStack credentials: `OS_*` environment variables (for osac-aap)
- Kubernetes config: `KUBECONFIG` for cluster access

**Secrets Location:**
- `.env` files (not visible in codebase - location TBD)
- Kubernetes Secrets mounted as volumes
- Service Account tokens at `/var/run/secrets/kubernetes.io/serviceaccount/`
- JWT token files passed via `--auth-token-file` flag (if configured)

## Webhooks & Callbacks

**Incoming:**
- gRPC streaming endpoints for watch operations (Events Watch)
- Location: `fulfillment-service/internal/servers/events_server.go`
- No HTTP webhooks detected

**Outgoing:**
- None detected - Services are passive (respond to requests)
- Integration tests use port mappings for TLS/SNI testing (`fulfillment-service/internal/testing/kind.go`)

## Service-to-Service Communication

**Within fulfillment-service:**
- gRPC between internal services
- Public API (read operations) wraps Private API (full CRUD)
- Architecture: Public servers delegate to Private servers

**Between Components:**
- fulfillment-service to osac-operator: Kubernetes custom resources and controllers
- fulfillment-service to osac-aap: Likely via Ansible API or HTTP callbacks (details in osac-aap)
- osac-operator to HyperShift: Via OpenShift API

## Integration Testing Infrastructure

**Test Environment:**
- Kind (Kubernetes-in-Docker) cluster named `fulfillment-service-it`
- Requires `/etc/hosts` entries:
  - `127.0.0.1 keycloak.keycloak.svc.cluster.local`
  - `127.0.0.1 fulfillment-api.innabox.svc.cluster.local`
- Deployment modes: Helm (default) or Kustomize (`IT_DEPLOY_MODE` env var)
- Cluster preservation: `IT_KEEP_KIND=true` for debugging

**Local Development Database:**
```bash
podman run -d --name postgresql_database \
  -e POSTGRESQL_USER=user \
  -e POSTGRESQL_PASSWORD=pass \
  -e POSTGRESQL_DATABASE=db \
  -p 127.0.0.1:5432:5432 \
  quay.io/sclorg/postgresql-15-c9s:latest
```

---

*Integration audit: 2026-03-30*
