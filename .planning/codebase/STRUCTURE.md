# Codebase Structure

**Analysis Date:** 2026-03-30

## Directory Layout

```
osac-project/                          # Monorepo root
├── fulfillment-service/               # gRPC API server with REST gateway
│   ├── cmd/                           # Binary entry points
│   ├── internal/                      # Private implementation
│   ├── proto/                         # Protocol Buffer definitions
│   ├── it/                            # Integration tests
│   ├── charts/                        # Helm deployment manifests
│   ├── manifests/                     # Kustomize deployment manifests
│   ├── docs/                          # API documentation
│   └── go.mod                         # Go module definition
├── osac-operator/                     # Kubernetes operator
│   ├── cmd/                           # Operator binary entry point
│   ├── api/                           # Kubernetes CRD definitions
│   ├── internal/                      # Private implementation
│   ├── config/                        # Kustomize configuration
│   ├── test/                          # E2E and unit tests
│   └── go.mod                         # Go module definition
├── osac-aap/                          # Ansible provisioning
│   └── collections/                   # Ansible collection with roles/playbooks
├── osac-installer/                    # Installation manifests
├── osac-test-infra/                   # Integration test utilities
├── enhancement-proposals/             # Design documents
├── CLAUDE.md                          # Project development guide
└── .planning/                         # Planning and working notes (gitignored)
    └── codebase/                      # Generated architecture docs
```

## Directory Purposes

**fulfillment-service/cmd:**
- Purpose: Binary entry points for service and CLI
- Contains: main.go files for `fulfillment-service` and `fulfillment-cli`
- Key files: `fulfillment-service/main.go`, `fulfillment-cli/main.go`

**fulfillment-service/internal/cmd:**
- Purpose: Command hierarchy and CLI structure
- Contains: Root commands, subcommand implementations, service startup logic
- Key files: `service/root_cmd.go`, `service/start/grpcserver/`, `cli/root_cmd.go`

**fulfillment-service/internal/cmd/service/start:**
- Purpose: Server startup implementations
- Contains: gRPC server, REST gateway, controller initialization
- Key files: `grpcserver/cmd.go`, `restgateway/cmd.go`, `controller/cmd.go`

**fulfillment-service/internal/servers:**
- Purpose: gRPC service implementations
- Contains: Resource-specific servers (one per resource type) plus generic server base
- Key files: `clusters_server.go`, `private_clusters_server.go`, `generic_server.go`, `generic_mapper.go`
- Pattern: Public server files like `clusters_server.go` contain public API + builder; private implementations in `private_clusters_server.go`

**fulfillment-service/internal/api/osac:**
- Purpose: Generated code from Protocol Buffers (never edit manually)
- Contains: Auto-generated Go protobuf message types and service stubs
- Subdirectories: `public/v1/` (user-facing), `private/v1/` (admin), `tests/v1/` (test utilities)

**fulfillment-service/internal/database:**
- Purpose: Database access and persistence
- Contains: Generic DAO implementation, schema management, migration files
- Key files: `dao/generic_dao.go`, `dao/filter_translator.go`, `migrations/*.up.sql`

**fulfillment-service/internal/database/dao:**
- Purpose: Data access object implementations
- Contains: CRUD operations, event callbacks, table management
- Key files: `generic_dao.go`, `generic_dao_create.go`, `generic_dao_get.go`, `generic_dao_list.go`, `generic_dao_update.go`, `generic_dao_delete.go`

**fulfillment-service/internal/database/migrations:**
- Purpose: SQL schema migrations
- Contains: Numbered migration files (.up.sql)
- Pattern: Each resource gets a migration creating its table with standard columns (id, name, creation_timestamp, deletion_timestamp, finalizers, creators, tenants, labels, annotations, data)

**fulfillment-service/internal/auth:**
- Purpose: Authentication, authorization, tenancy
- Contains: Attribution logic (creator tracking), tenancy logic (tenant identification), OPA integration
- Key files: `attribution_logic.go`, `tenancy_logic.go`

**fulfillment-service/internal/controllers:**
- Purpose: Resource reconciliation logic
- Contains: Reconciler base class, resource-specific controller implementations
- Subdirectories: `cluster/`, `computeinstance/`, `virtualnetwork/`, `subnet/`, `securitygroup/`, `hostpool/`, `host/`, `finalizers/`
- Key file: `reconciler.go` (generic reconciliation framework)

**fulfillment-service/internal/kubernetes:**
- Purpose: Kubernetes integration utilities
- Contains: Label/annotation helpers, CRD helpers, GroupVersionKind definitions
- Subdirectories: `labels/`, `annotations/`, `gvks/`

**fulfillment-service/proto/public:**
- Purpose: User-facing API definitions
- Contains: Type definitions and service definitions split by resource
- Structure: `osac/public/v1/<resource>_type.proto` (messages) and `<resource>s_service.proto` (RPC operations)

**fulfillment-service/proto/private:**
- Purpose: Admin/controller API definitions
- Contains: Full CRUD plus Signal RPC for feedback
- Structure: Same organization as public API; resource-specific files

**fulfillment-service/proto/tests:**
- Purpose: Test-only protocol definitions
- Contains: Test objects and test service definitions
- Location: `osac/tests/v1/`

**fulfillment-service/it:**
- Purpose: Integration tests
- Contains: Test suites, test fixtures, kind cluster setup
- Key files: `*_suite_test.go` (ginkgo suites), `crds/` (Kubernetes manifests for test setup)

**fulfillment-service/charts:**
- Purpose: Helm chart templates for deployment
- Contains: Charts for service, Keycloak, Prometheus, CA
- Subdirectories: `service/` (main service chart), `keycloak/`, `prometheus/`, `ca/`

**fulfillment-service/manifests:**
- Purpose: Kustomize-based deployment manifests
- Contains: Base and overlay configurations
- Structure: `base/` (component manifests), `overlays/{kind,openshift}/` (environment-specific overlays)

**fulfillment-service/docs:**
- Purpose: Generated documentation
- Contains: Generated API docs, OpenAPI specifications
- Key files: Auto-generated during build

**osac-operator/cmd:**
- Purpose: Operator binary entry point
- Contains: main.go with operator initialization and controller setup
- Key file: `main.go` (500+ lines with full operator bootstrap)

**osac-operator/api/v1alpha1:**
- Purpose: Kubernetes CRD definitions (ClusterOrder, HostPool, ComputeInstance, etc.)
- Contains: Go structs defining CustomResource types
- Key files: `clusterorder_types.go`, `hostpool_types.go`, `computeinstance_types.go`

**osac-operator/internal/controller:**
- Purpose: Kubernetes controller implementations
- Contains: Resource-specific controllers and feedback controllers
- Subdirectories: `clusterorder/`, `hostpool/`, `computeinstance/`, `tenant/`, `virtualnetwork/`, `subnet/`, `securitygroup/`
- Key files: `*_controller.go` (main controller), `*_feedback_controller.go` (feedback from provisioning)

**osac-operator/internal/provisioning:**
- Purpose: Provisioning backend abstraction
- Contains: Provider interfaces, AAP provider, EDA webhook provider
- Key files: `provider.go` (interface), `aap_provider.go`, `eda_provider.go`

**osac-operator/internal/aap:**
- Purpose: Ansible Automation Platform integration
- Contains: AAP client, template resolution, job submission
- Key files: `client.go`

**osac-operator/config/crd:**
- Purpose: Custom Resource Definition manifests
- Contains: CRD YAML for all operator resources
- Subdirectories: `bases/` (CRD definitions), `fakes/` (test CRDs)

**osac-operator/config/rbac:**
- Purpose: Role-based access control
- Contains: ClusterRole, ClusterRoleBinding, ServiceAccount manifests
- Generated from controller-gen markers in code

**osac-aap/collections/ansible_collections/massopencloud/esi:**
- Purpose: Ansible collection for infrastructure provisioning
- Contains: Roles and playbooks for VM and network provisioning
- Subdirectories: `roles/` (ansible roles for different provisioning tasks), `plugins/filter/` (custom ansible filters)
- Key roles: `host/`, `l2/`, `l3/`, `floating_ip/`, etc.

**osac-installer:**
- Purpose: Installation and setup
- Contains: Deployment scripts, prerequisites, demo configurations
- Key files: Setup scripts, prerequisite checklists

**osac-test-infra:**
- Purpose: Shared testing utilities
- Contains: Kind cluster helpers, test fixtures, common test setup
- Key files: Infrastructure setup and test utilities

**enhancement-proposals:**
- Purpose: Design documents and RFCs
- Contains: Markdown documents describing features and architecture decisions
- Key files: `.md` design documents

## Key File Locations

**Entry Points:**
- `fulfillment-service/cmd/fulfillment-service/main.go`: Service binary entry
- `fulfillment-service/cmd/fulfillment-cli/main.go`: CLI binary entry
- `osac-operator/cmd/main.go`: Operator entry point

**Configuration:**
- `fulfillment-service/CLAUDE.md`: Development guide with build commands
- `fulfillment-service/go.mod`: Go module and dependencies
- `fulfillment-service/buf.yaml`: Protocol Buffer linting and generation config
- `fulfillment-service/buf.gen.yaml`: Proto code generation rules
- `osac-operator/PROJECT`: Operator project metadata (for controller-gen)

**Core Logic:**
- `fulfillment-service/internal/servers/clusters_server.go`: Cluster resource server
- `fulfillment-service/internal/servers/private_clusters_server.go`: Cluster private RPC implementation
- `fulfillment-service/internal/servers/generic_server.go`: Generic CRUD server base
- `fulfillment-service/internal/database/dao/generic_dao.go`: Generic data access object
- `fulfillment-service/internal/controllers/reconciler.go`: Resource reconciliation base
- `osac-operator/internal/provisioning/provider.go`: Provisioning provider interface
- `osac-operator/internal/aap/client.go`: AAP integration

**Testing:**
- `fulfillment-service/it/*_suite_test.go`: Integration test suites
- `osac-operator/test/e2e/`: E2E test cases
- `fulfillment-service/internal/testing/`: Shared test utilities

## Naming Conventions

**Files:**
- `*_server.go`: Public gRPC server implementation
- `private_*_server.go`: Private gRPC server implementation (admin/controller)
- `*_server_test.go`: Unit tests for server
- `*_controller.go`: Kubernetes controller implementation
- `*_feedback_controller.go`: Feedback handler for provisioning events
- `*_type.proto`: Protocol Buffer message definitions
- `*s_service.proto`: Protocol Buffer service definitions (note: plural resource name + `s`)
- `*_test.go`: Unit test files

**Directories:**
- `internal/`: Private implementation packages
- `cmd/`: Binary entry points
- `api/`: Public API definitions
- `config/`: Configuration manifests
- `proto/`: Protocol Buffer definitions
- `it/`: Integration tests

## Where to Add New Code

**New Resource Type (e.g., LoadBalancer):**

1. **Proto Definitions:**
   - `fulfillment-service/proto/public/osac/public/v1/loadbalancer_type.proto` - Message schema
   - `fulfillment-service/proto/public/osac/public/v1/loadbalancers_service.proto` - RPC operations
   - `fulfillment-service/proto/private/osac/private/v1/loadbalancer_type.proto` - Private schema (mirror)
   - `fulfillment-service/proto/private/osac/private/v1/loadbalancers_service.proto` - Private operations

2. **Server Implementation:**
   - `fulfillment-service/internal/servers/loadbalancers_server.go` - Public server + builder
   - `fulfillment-service/internal/servers/private_loadbalancers_server.go` - Private implementation
   - `fulfillment-service/internal/servers/loadbalancers_server_test.go` - Server tests

3. **Database:**
   - `fulfillment-service/internal/database/migrations/NNNN_create_loadbalancers.up.sql` - Schema migration
   - Auto-used by GenericDAO with appropriate type parameter

4. **Controller (if operator-managed):**
   - `osac-operator/api/v1alpha1/loadbalancer_types.go` - CRD definition
   - `osac-operator/internal/controller/loadbalancer/controller.go` - Controller implementation
   - `osac-operator/config/crd/bases/` - Generated CRD manifests

5. **Tests:**
   - `fulfillment-service/internal/servers/loadbalancers_server_test.go` - Server unit tests
   - `fulfillment-service/it/loadbalancers_suite_test.go` - Integration tests (Ginkgo suite)
   - `osac-operator/test/e2e/loadbalancer_test.go` - E2E tests (if operator-managed)

**New Controller Reconciler (Fulfillment-service):**

- `fulfillment-service/internal/controllers/<resource>/reconciler.go` - Reconciliation implementation
- Use pattern from `internal/controllers/cluster/reconciler.go` or `virtualnetwork/reconciler.go`
- Inherit from base `Reconciler[O]` in `controllers/reconciler.go`

**New Server Middleware/Interceptor:**

- `fulfillment-service/internal/cmd/service/start/grpcserver/` - Register in gRPC server setup
- Follow pattern of existing interceptors (panic recovery, logging, metrics, auth)

**Utilities/Helpers:**

- Shared utilities: `fulfillment-service/internal/utils/`, `fulfillment-service/internal/text/`, `fulfillment-service/internal/json/`
- Kubernetes helpers: `fulfillment-service/internal/kubernetes/{labels,annotations,gvks}/`
- Networking helpers: `fulfillment-service/internal/network/`

## Special Directories

**fulfillment-service/internal/api/:**
- Purpose: Generated code (auto-generated by `buf generate`)
- Generated: Yes (do not edit manually)
- Committed: Yes (committed to git for reproducibility)
- Regenerate: After proto changes, run `buf generate` in fulfillment-service root

**osac-operator/config/crd/bases/:**
- Purpose: Kubernetes CRD manifests (auto-generated)
- Generated: Yes (auto-generated by controller-gen)
- Committed: Yes (committed to git)
- Regenerate: After CRD type changes, run `make manifests` in osac-operator root

**fulfillment-service/it/crds/:**
- Purpose: Kubernetes manifests used by integration tests
- Generated: No (manually maintained)
- Committed: Yes
- Usage: Loaded by integration tests to set up test cluster state

**fulfillment-service/charts/service/templates/:**
- Purpose: Helm chart templates for service deployment
- Generated: No (maintained manually)
- Committed: Yes
- Usage: Helm renders templates during installation/upgrade

---

*Structure analysis: 2026-03-30*
