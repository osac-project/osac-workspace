# Coding Conventions

**Analysis Date:** 2026-03-30

## Naming Patterns

**Files:**
- Source files: `snake_case.go` (e.g., `auth_context.go`, `clusters_server.go`)
- Test files: `*_test.go` suffix in same package (e.g., `auth_context_test.go`)
- Mock files: `*_mock.go` generated via mockgen (e.g., `attribution_logic_mock.go`)
- Suite test files: `*_suite_test.go` for package-level setup (e.g., `auth_suite_test.go`)

**Functions:**
- Public: `PascalCase` (e.g., `NewClustersServer()`, `SubjectFromContext()`, `DetermineAssignedCreators()`)
- Private: `camelCase` (e.g., `getDeletionTimestamp()`, `buildFilter()`)
- Constructor builders: `NewTypeName()` returning `*TypeBuilder` (e.g., `NewClustersServer()`, `NewLogger()`)
- Builder methods: `SetFieldName()` returning `*Builder` for method chaining (e.g., `SetLogger()`, `SetAttributionLogic()`)
- Getter/Setter pairs for single responsibility: `GetName()` / `SetName()` (e.g., `GetId()` / `SetId()`)

**Variables:**
- Constants: `camelCase` or `SCREAMING_SNAKE_CASE` depending on scope (e.g., `subjectContextKey`, `defaultLimit`)
- Type assertions: `value.(TypeName)` with switch case pattern (e.g., `subject := subject.(type)`)
- Interface types: `camelCase` private (e.g., `metadataIface`) or singular `InterfaceName` public

**Types:**
- Struct names: `PascalCase` (e.g., `ClustersServer`, `GenericDAO`, `LoggerBuilder`)
- Interface names: `PascalCase` (e.g., `AttributionLogic`, `Object`, `EventCallback`)
- Generic type parameters: Single capital letters (e.g., `[O Object]` for object type, `[T]` for table type)
- Error types: `Err` prefix for error types (e.g., `ErrNotFound`, `ErrAlreadyExists`, `ErrDenied`)

## Code Style

**Formatting:**
- Standard Go formatting via `gofmt` (enforced implicitly, no explicit .gofmtrc config)
- Indentation: tabs (Go default)
- Line length: no hard limit, but keep readable

**Linting:**
- Proto files: `buf lint` (configured in `buf.yaml`)
- YAML files: `yamllint` with strict mode (configured in `.pre-commit-config.yaml`)
- Pre-commit hooks: trailing whitespace, merge conflict markers, large files, JSON validation

**License Headers:**
- All `.go` and `.proto` files start with Apache 2.0 copyright header
- Format: Multi-line comment block with Red Hat Inc. copyright and Apache 2.0 license

## Import Organization

**Order:**
1. Standard library imports (e.g., `context`, `fmt`, `log/slog`)
2. Third-party imports (e.g., `google.golang.org`, `github.com/onsi/ginkgo`)
3. Project internal imports (e.g., `github.com/osac-project/fulfillment-service/internal/...`)

**Path Aliases:**
- No custom import aliases in standard code
- Generated proto packages under `internal/api/osac/{public,private}/v1/`
- Private internal packages under `internal/` use absolute paths

**Blank lines:**
- One blank line between import groups
- No custom aliases, use full paths for clarity

## Error Handling

**Patterns:**
- Custom error types as structs with fields (e.g., `ErrNotFound{IDs []string}`)
- Error interface implementation via `Error() string` method on error types
- Human-friendly error messages (no technical details in user-facing errors)
- Type switch for error inspection in handlers:
  ```go
  switch err := err.(type) {
  case *ErrNotFound:
      // handle not found
  case *ErrAlreadyExists:
      // handle exists
  case *ErrDenied:
      // handle denied
  default:
      // handle generic error
  }
  ```
- Panics used for invariant violations (e.g., `SubjectFromContext` panics if subject missing)
- Builder validation errors returned as error strings (e.g., "logger is mandatory")

## Logging

**Framework:** `log/slog` (Go 1.21+ standard library)

**Patterns:**
- Logger passed as `*slog.Logger` in builder/constructor patterns
- Structured logging with context methods: `logger.ErrorContext()`, `logger.InfoContext()`
- Contextual logger creation: `logger.With(...)` adds fields to new logger
- Logger output configured via builder: `SetWriter()`, `SetOut()`, `SetErr()`
- Log level set via builder: `SetLevel()` with string values (e.g., `slog.LevelDebug.String()`)
- Special field handling in logger: `%p` placeholder replaced with process ID
- Test integration: logs written to `GinkgoWriter` in tests for suite output

## Comments

**When to Comment:**
- Package-level: Describe the purpose of the file/package (e.g., `// This file contains functions that extract information from the context.`)
- Public types and functions: Always comment exported symbols (required by Go conventions)
- Interface methods: Document the contract and behavior expectations
- Complex logic: Explain why something is done, not just what
- Context keys: Comment purpose (e.g., `// contextKey is the type used to store...`)

**JSDoc/TSDoc:**
- Go uses standard comment format above exported items
- No special tags (not a requirement of Go style)
- Documentation comments are prose, not structured tags
- Example:
  ```go
  // SubjectFromContext extracts the subject from the context. Panics if there is no subject in the
  // context.
  func SubjectFromContext(ctx context.Context) *Subject {
  ```

## Function Design

**Size:**
- Functions kept to single responsibility
- Builder methods intentionally short (single setter + return)
- Server methods grouped by operation (Create, Get, List, Update, Delete)

**Parameters:**
- Context always first parameter in functions that need it
- Builders use typed receiver: `(b *Builder) Method()`
- Interfaces prefer simple parameter types (avoid varargs for clarity)

**Return Values:**
- Builders return `*Builder` for chaining (e.g., `SetLogger(...).SetNotifier(...).Build()`)
- `Build()` methods return `(Type, error)` with validation errors
- Server methods return `(*ResponseType, error)` matching gRPC pattern
- Error as last return value (Go convention)

## Module Design

**Exports:**
- Public types: `PascalCase` (visible outside package)
- Public functions: `PascalCase` (visible outside package)
- Private types: `camelCase` or prefix-only (e.g., `contextKey`)
- Private functions: `camelCase` (not exported)
- Interfaces marked with `var _ InterfaceName = (*ConcreteType)(nil)` assertion

**Barrel Files:**
- No explicit barrel/index files
- Each package is a unit with its own exports
- Proto-generated code in `internal/api/` organized by version (public/v1, private/v1)

**Package Organization:**
- `internal/auth/` - Authentication logic, context, token handling
- `internal/servers/` - gRPC service implementations
- `internal/database/` - Database abstraction, migrations
- `internal/database/dao/` - Generic DAO and filter translation
- `internal/logging/` - Logger and interceptor builders
- `internal/testing/` - Test utilities and fixtures
- `proto/` - Protocol Buffer definitions split by API level

## Builder Pattern

**Usage:**
- All major components use builder pattern for complex initialization
- Mandatory fields checked in `Build()` method
- Optional fields have sensible defaults
- Method chaining enabled via returning `*Builder`
- Example:
  ```go
  server, err := NewClustersServer().
      SetLogger(logger).
      SetAttributionLogic(attribution).
      SetTenancyLogic(tenancy).
      Build()
  ```

## Proto Naming Conventions

**Files:** `snake_case.proto` (e.g., `virtual_network_type.proto`)

**Messages:** `PascalCase` (e.g., `VirtualNetwork`, `Cluster`)

**Fields:** `snake_case` (e.g., `creation_timestamp`, `ipv4_cidr`)

**Enums:** `SCREAMING_SNAKE_CASE` (e.g., `STATE_PENDING`, `STATE_READY`)

**Services:** `PascalCase` (e.g., `Clusters`, `VirtualNetworks`)

**RPC Methods:** `PascalCase` (e.g., `CreateCluster`, `GetVirtualNetwork`)

## Cross-Repo Dependencies

When changing one repo, check all dependent repos in this table before submitting:

| Change in | Also check | Why |
|-----------|-----------|-----|
| `fulfillment-service` proto fields | `osac-installer` CI overlays (`setup.sh`) | Installer pins fulfillment-service image version; proto changes need matching image update |
| `osac-aap` collection roles | `osac-installer` submodule refs | Installer pins AAP collection versions via submodule; new roles need submodule bump |
| `osac-operator` CRD types | `fulfillment-service` reconciler registration | New CRD types must be registered in the fulfillment-service reconciler |
| `osac-operator` CRD spec changes | `osac-aap` roles that read CRD fields | Adding a field to `ClusterOrderSpec` requires the AAP playbook to extract and use it |
| `fulfillment-service` CLI flag changes | `osac-test-infra` test helpers | Adding `--pull-secret-file` required updating `OsacCLI.create_cluster` in the test infra |

Evidence: MGMT-24226 eval scored 3/5 because the agent fixed `fulfillment-service` and `osac-aap` but missed updating `osac-installer` CI overlays.

---

*Convention analysis: 2026-03-30*
