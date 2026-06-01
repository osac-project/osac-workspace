# Architecture

**Analysis Date:** 2026-03-30

## Pattern Overview

**Overall:** Multi-tier distributed system using Protocol Buffers for API definition, gRPC for service communication, and Kubernetes operators for resource orchestration.

**Key Characteristics:**
- Public and private API split at the Protocol Buffer definition level
- Generic server implementation for CRUD operations across all resources
- Database-driven (PostgreSQL) with DAO abstraction layer
- Kubernetes operators for orchestration and provisioning
- Provider-based architecture for pluggable provisioning backends (AAP, EDA webhooks)
- Multi-tenancy with tenant isolation at database and authorization layers
- Feedback loop integration between operator and fulfillment service

## Layers

**API Layer (Proto-based):**
- Purpose: Defines resource schemas and service contracts
- Location: `fulfillment-service/proto/public/osac/public/v1/` and `fulfillment-service/proto/private/osac/private/v1/`
- Contains: Type definitions (messages), service definitions (RPCs), enums for status
- Depends on: Protocol Buffers standard library, Google API annotations
- Used by: Generated Go code, OpenAPI specifications

**Server Layer (gRPC):**
- Purpose: Implements gRPC service definitions and REST gateway
- Location: `fulfillment-service/internal/servers/`
- Contains: Resource-specific servers (e.g., `clusters_server.go`), generic server base class, mappers for public/private API translation
- Depends on: Generated API code, database layer, authentication/authorization, notifications
- Used by: gRPC and REST clients via gateway
- Pattern: Builder pattern for server configuration; public servers wrap private servers and add tenant/auth logic

**Private Servers (Internal RPC):**
- Purpose: Full CRUD operations without user-facing restrictions
- Location: `fulfillment-service/internal/servers/private_*_server.go`
- Contains: All CRUD operations plus Signal RPC for controller feedback
- Depends on: Database DAO, generic server infrastructure
- Used by: Public servers, controllers via gRPC client

**Public Servers (User-facing):**
- Purpose: Tenant-aware API with read-heavy, limited write operations
- Location: `fulfillment-service/internal/servers/*_server.go`
- Contains: Get/List operations, restricted Create/Update/Delete (system-only)
- Depends on: Private servers, attribution/tenancy logic, mappers
- Used by: External clients (gRPC and REST)

**Database Layer:**
- Purpose: Persistent storage with multi-tenancy support
- Location: `fulfillment-service/internal/database/`, `fulfillment-service/internal/database/dao/`
- Contains: Generic DAO for type-safe CRUD, filter/sort translation, migrations
- Depends on: PostgreSQL, Protocol Buffers serialization
- Used by: Server layer, controller reconcilers

**Authentication & Authorization:**
- Purpose: Identity verification, tenancy enforcement, permission checks
- Location: `fulfillment-service/internal/auth/`
- Contains: Attribution logic (creator tracking), tenancy logic (tenant identification), OPA integration
- Depends on: JWT tokens, OpenPolicy Agent
- Used by: Server layer, generic server infrastructure

**Controller Layer (Kubernetes Operators):**
- Purpose: Reconciliation logic for resource provisioning and lifecycle management
- Location: `osac-operator/internal/controller/`, `fulfillment-service/internal/controllers/`
- Contains: Resource-specific controllers (Cluster, ComputeInstance, VirtualNetwork, etc.), feedback reconcilers
- Depends on: controller-runtime, provisioning providers, gRPC client to fulfillment service
- Used by: Kubernetes operator manager

**Provisioning Providers:**
- Purpose: Pluggable backends for resource provisioning
- Location: `osac-operator/internal/provisioning/`, `osac-operator/internal/aap/`
- Contains: Provider interfaces, AAP client, EDA webhook client, template management
- Depends on: HTTP clients, Ansible API
- Used by: Controllers for provision/deprovision operations

**Networking/Ansible:**
- Purpose: Low-level provisioning of VMs and network infrastructure
- Location: `osac-aap/collections/ansible_collections/massopencloud/esi/`
- Contains: Ansible roles and playbooks for compute and network provisioning
- Depends on: Ansible, cloud provider SDKs (e.g., OpenStack)
- Used by: AAP job execution triggered by provisioning providers

## Data Flow

**Create Resource (Client to Fulfillment):**

1. Client calls gRPC/REST endpoint on public server (e.g., CreateCluster)
2. Public server maps request to private API representation
3. Private server applies tenancy/attribution metadata
4. Generic server validates and creates database record
5. Success response returned to client
6. Notifier broadcasts change event if configured

**Resource Provisioning (Fulfillment to Operator):**

1. Controller polls or watches fulfillment service via Reconciler
2. Reconciler calls GetCluster with filter/watch expressions
3. Fulfillment service returns resource with current status
4. Controller reconciles spec vs status (checks conditions)
5. If action needed, controller triggers provisioning provider
6. Provider (AAP) executes Ansible jobs or webhooks

**Provisioning Feedback (Operator to Fulfillment):**

1. Controller receives event from provisioning provider (job completion, status)
2. Feedback controller sends Signal RPC to fulfillment service private API
3. Private server updates resource status, conditions, and finalizers
4. Status change persists to database
5. Public server reflects updated status when queried

**State Management:**

- Desired state: Stored in resource Spec (creation_timestamp, deletion_timestamp, labels, annotations)
- Observed state: Stored in resource Status (conditions, phase, last-observed-generation)
- Controller duty: Reconcile observed state toward desired state
- Database as source of truth: Controllers read from DB via gRPC, write back via Signal RPC
- Tenancy enforcement: All queries filtered by tenant ID in annotations

## Key Abstractions

**Resource Object (Proto Message):**
- Purpose: Represents infrastructure entities (Cluster, VirtualNetwork, ComputeInstance)
- Examples: `fulfillment-service/proto/public/osac/public/v1/cluster_type.proto`, `virtual_network_type.proto`
- Pattern: All have metadata (name, labels, annotations, timestamps), spec (user configuration), status (observed state)

**Generic DAO[O Object]:**
- Purpose: Type-safe database abstraction for any protobuf message
- Examples: `fulfillment-service/internal/database/dao/generic_dao.go`
- Pattern: Uses Go generics; implements Create, Get, List, Update, Delete, Exists; handles JSON serialization

**Generic Server[O Object]:**
- Purpose: Implements CRUD gRPC operations for any resource
- Examples: `fulfillment-service/internal/servers/generic_server.go`
- Pattern: Parameterized by object type; delegates to DAO; handles field masking, filtering, sorting; enforces tenancy

**Server Builder:**
- Purpose: Configures server with logger, DAO, notifier, auth logic before instantiation
- Examples: `ClustersServerBuilder`, `NewGenericServer[O]().SetLogger(...).SetService(...).Build()`
- Pattern: Builder pattern eliminates constructor parameter overload; mandatory vs optional configuration explicit

**Reconciler[O Object]:**
- Purpose: Polls/watches resource changes and executes custom reconciliation logic
- Examples: `fulfillment-service/internal/controllers/reconciler.go`, `osac-operator/internal/controller/`
- Pattern: Takes a ReconcilerFunction that receives current resource state and performs work

**Provisioning Provider:**
- Purpose: Abstraction for different provisioning backends
- Examples: `osac-operator/internal/provisioning/aap_provider.go`, `eda_provider.go`
- Pattern: Interface with Provision/Deprovision/GetStatus methods; supports template-based execution

## Entry Points

**fulfillment-service binary:**
- Location: `fulfillment-service/cmd/fulfillment-service/main.go` → `internal/cmd/service/Root()`
- Triggers: Service start commands (grpc-server, rest-gateway, controller), dev/probe commands
- Responsibilities: Service initialization, subcommand routing, logging setup

**gRPC Server:**
- Location: `fulfillment-service/internal/cmd/service/start/grpcserver/`
- Triggers: `fulfillment-service start grpc-server` CLI command
- Responsibilities: Listen on gRPC port, register all service implementations, set up interceptors (panic recovery, metrics, logging, auth, transactions)

**REST Gateway:**
- Location: `fulfillment-service/internal/cmd/service/start/restgateway/`
- Triggers: `fulfillment-service start rest-gateway` CLI command
- Responsibilities: Translate HTTP/JSON to gRPC; proxy requests to gRPC server; serve OpenAPI specs

**Controller (Fulfillment):**
- Location: `fulfillment-service/internal/cmd/service/start/controller/`
- Triggers: `fulfillment-service start controller` CLI command
- Responsibilities: Run reconcilers for in-process resource monitoring and feedback

**osac-operator binary:**
- Location: `osac-operator/cmd/main.go`
- Triggers: Kubernetes operator deployment (helm/kustomize)
- Responsibilities: Initialize multicluster manager, register controllers, set up gRPC client to fulfillment service, start reconciliation loops

**Cluster Controller (Operator):**
- Location: `osac-operator/internal/controller/`
- Triggers: ClusterOrder resource created/updated in Kubernetes
- Responsibilities: Check Hosted Control Planes readiness, trigger provisioning, update status, handle feedback

**Compute Instance Controller (Operator):**
- Location: `osac-operator/internal/controller/computeinstance/`
- Triggers: ComputeInstance resource created/updated in Kubernetes or fulfillment service
- Responsibilities: Create KubeVirt VM, attach to networks, apply security groups, monitor provisioning status

**Networking Controllers (Operator):**
- Location: `osac-operator/internal/controller/{virtualnetwork,subnet,securitygroup}`
- Triggers: VirtualNetwork/Subnet/SecurityGroup resources via fulfillment service
- Responsibilities: Translate logical network specs to AAP/EDA provisioning, track implementation status

**CLI binary:**
- Location: `fulfillment-service/cmd/fulfillment-cli/main.go` → `internal/cmd/cli/Root()`
- Triggers: Manual CLI invocation for cluster/host/compute instance management
- Responsibilities: Provide kubectl-like CLI interface, call fulfillment service gRPC APIs

## Error Handling

**Strategy:** Hierarchical error wrapping with context preservation; gRPC status codes mapped to domain errors.

**Patterns:**

- DAO errors: Wrapped with table/operation context (e.g., "failed to create cluster in table 'clusters'")
- Server errors: Translated to gRPC status codes (NotFound → Code.NOT_FOUND, AlreadyExists → Code.ALREADY_EXISTS)
- Controller errors: Logged with full context; reconciliation retried with exponential backoff
- Auth errors: Return Unauthenticated or PermissionDenied gRPC codes; tenancy violations logged
- Database transaction errors: Automatically rolled back; client receives clear error message

## Cross-Cutting Concerns

**Logging:** slog (Go's structured logging); each layer logs with context (request ID, resource ID, tenant ID); configuration via CLI flags (`--log-level`, `--log-format`)

**Validation:** CEL expressions in database layer for filtering; Protocol Buffer field presence/constraints at message definition; server-side validation before storage

**Authentication:** JWT token extraction from gRPC metadata; OAuth2 token file reading for service-to-service auth; token verification delegated to Keycloak

**Multi-tenancy:** Tenant ID stored in resource annotations (`osac.openshift.io/tenant`); all database queries filtered by tenant automatically; OPA policies enforce isolation at authorization layer

**Observability:**
- Metrics: Prometheus instrumentation at gRPC interceptor level; controller reconciliation metrics tracked
- Health checks: gRPC health check protocol; Kubernetes liveness/readiness probes
- Events: Database change events published via Notifier; watch streams propagate changes to controllers

**Transactions:** gRPC interceptor wraps each RPC in database transaction; automatic rollback on error; ensures consistency across CRUD operations

---

*Architecture analysis: 2026-03-30*
