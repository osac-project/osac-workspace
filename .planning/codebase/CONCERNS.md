# Codebase Concerns

**Analysis Date:** 2026-03-30

## Tech Debt

### Generic Server Type Coupling

**Area:** Event Notification System

**Issue:** The `GenericServer[O]` in `fulfillment-service/internal/servers/generic_server.go` contains hard-coded type switches for event payload handling. These type switches couple the generic server to specific message types (ClusterTemplate, Cluster, HostClass, Host, HostPool, Hub, ComputeInstanceTemplate, ComputeInstance, NetworkClass, VirtualNetwork, Subnet, SecurityGroup), breaking the abstraction.

**Files:**
- `fulfillment-service/internal/servers/generic_server.go` (lines 669-691, 693-730)

**Impact:**
- Adding new resource types requires modifying the generic server (violates Open/Closed principle)
- Makes the generic server harder to test — test suite must cover all resource types
- Code duplication exists in both `notifyEvent()` and `setPayload()` methods
- Maintenance burden increases with each new resource type

**Fix Approach:**
- Extract event payload mapping to a plugin interface or registrable type handler
- Use reflection or a registry pattern to map protobuf message types to event setters
- Consider moving to a `proto.Message` -> oneof handler pattern with dynamic dispatch

---

### PostgreSQL NOTIFY Payload Size Limitation

**Area:** Event Notification

**Issue:** Hub objects often exceed PostgreSQL's default 8000 byte notification limit. Currently, the code works around this by cloning the Hub message and stripping the Kubeconfig field (line 705-709), but this is a temporary workaround.

**Files:**
- `fulfillment-service/internal/servers/generic_server.go` (lines 705-709)

**Impact:**
- Very large Hub kubeconfigs (>8KB) will silently fail to deliver the Hub object in event notifications
- Event consumers won't have the full object state and must fetch separately
- Workaround is fragile — if kubeconfig can't be stripped (e.g., future message types), notifications break
- Database performance degrades as table of event payloads grows unbounded

**Fix Approach:**
- Implement a separate event payload table with foreign key to events
- Store full payloads in table, reference by ID in NOTIFY message
- Implement garbage collection for old payloads
- Alternative: switch to LISTEN/NOTIFY for state changes only, clients fetch state via API

---

### Incomplete Phase Mapping in Operator Feedback

**Area:** Kubernetes Operator Feedback

**Issue:** The `feedback_controller.go` and `hostpool_feedback_controller.go` in osac-operator have unimplemented phase mappings. Specifically, `ClusterOrderPhaseDeleting` has no equivalent phase in the fulfillment service, and the code just returns without updating status.

**Files:**
- `osac-operator/internal/controller/feedback_controller.go` (line 269)
- `osac-operator/internal/controller/hostpool_feedback_controller.go` (line 264)

**Impact:**
- Clusters in "Deleting" phase will not have their status synced to the fulfillment service
- Operator won't reflect actual deletion state, causing stale status in the API
- Users won't know if a cluster deletion is in progress or stuck
- No monitoring/alerting possible for stuck deletion operations

**Fix Approach:**
- Map `ClusterOrderPhaseDeleting` to `CLUSTER_STATE_DELETING` (or add this state if missing)
- Implement `syncPhaseDeleting()` to properly signal cluster state during deletion lifecycle
- Add integration test verifying deletion status propagation

---

### Unimplemented Object Filtering

**Area:** Event Reconciliation

**Issue:** The `Reconciler` builder in `fulfillment-service/internal/controllers/reconciler.go` (line 194) initializes `objectFilter` to empty string with a TODO comment indicating object filtering support hasn't been implemented yet.

**Files:**
- `fulfillment-service/internal/controllers/reconciler.go` (lines 193-195)

**Impact:**
- Reconcilers cannot filter objects before processing, wasting CPU on irrelevant events
- At scale, all reconcilers process all object events regardless of relevance
- No way to optimize reconciliation — e.g., "only reconcile Clusters in 'Progressing' state"
- Performance degrades linearly with total number of resources in the system

**Fix Approach:**
- Implement CEL filter expression parsing for objects (same pattern as event filters)
- Translate object filters to database WHERE clauses in `ListEvents` calls
- Add filter examples to reconciler builder documentation
- Test with large datasets to validate performance improvement

---

## Known Bugs

### KubeVirt Console Authentication Limitation

**Area:** Console Access

**Issue:** The `kubevirt_backend.go` in `fulfillment-service/internal/console/kubevirt_backend.go` only supports BearerToken authentication. If a hub kubeconfig uses BearerTokenFile, ExecProvider, or client certificates, the WebSocket connection will be unauthenticated.

**Files:**
- `fulfillment-service/internal/console/kubevirt_backend.go` (lines 134-145)

**Symptoms:**
- Console connections fail with "unauthenticated" error when hub uses certificate or exec-based auth
- Logs show warning: "Hub REST config has no BearerToken; WebSocket connection may be unauthenticated"
- Users cannot access console for hubs using Kubernetes token files or certificate auth

**Trigger:**
- Hub kubeconfig generated with auth method other than inline BearerToken
- Any hub using token files, certificate authentication, or authentication plugins

**Workaround:**
- Export hub kubeconfig token explicitly and patch it into the hub object
- Limitation is documented in the warning message

**Fix Approach:**
- Use `k8s.io/client-go/transport.New()` to build a round-tripper from the REST config
- Extract all supported auth headers (Authorization, X-Custom-Headers, certificates) from round-tripper
- Pass headers to WebSocket dial configuration
- Test with kubeconfigs using token files, exec providers, and certificates

---

## Security Considerations

### ALPN Disabled for OpenShift Router Compatibility

**Area:** gRPC Client TLS Configuration

**Risk:** The gRPC client in `fulfillment-service/internal/network/grpc_client.go` uses experimental TLS credentials with ALPN disabled to work around OpenShift router limitations. This bypasses ALPN protocol negotiation, which is a security defense-in-depth mechanism.

**Files:**
- `fulfillment-service/internal/network/grpc_client.go` (lines 307-315)

**Current Mitigation:**
- Code comment documents the reason and references upstream issues
- Only affects controller-to-service communication, not client-facing API
- OpenShift router is the bottleneck, not our code

**Recommendations:**
- Track upstream issue: https://github.com/grpc/grpc-go/pull/7980
- Upgrade gRPC when ALPN support becomes standard in grpc-go (1.67+)
- Consider feature request to OpenShift to enable ALPN in the default router
- Monitor for gRPC 2.0+ which may have different ALPN handling
- Document this as a deployment constraint in operator README

---

### Custom Kubernetes Token Audience Not Configurable

**Area:** Authentication Configuration

**Risk:** The Authorino AuthConfig in `fulfillment-service/charts/service/templates/grpc-server/authconfig.yaml` hardcodes Kubernetes API server audiences instead of using a custom audience for the fulfillment service (line 26).

**Files:**
- `fulfillment-service/charts/service/templates/grpc-server/authconfig.yaml` (lines 26-56)

**Current Mitigation:**
- Falls back to cluster default audiences (`kubernetes.default.svc`, `kubernetes.default.svc.cluster.local`)
- Works for service accounts with auto-generated tokens
- Different Kubernetes flavors have different audience conventions (Kind vs. OpenShift)

**Recommendations:**
- Create a custom audience (e.g., `fulfillment-api`) and update AuthConfig
- Users would need to create tokens with custom audience: `kubectl create token -n osac --audience=fulfillment-api client`
- Investigate projected service account token support for controller pods
- Document token creation in the installation guide
- Test with different Kubernetes distributions before rolling out

---

## Performance Bottlenecks

### Large Integration Test Tool (1.2k+ lines)

**Area:** Integration Test Infrastructure

**Problem:** The `it_tool.go` file is 1,263 lines, handling cluster setup, deployment, health checks, and cleanup. This makes it hard to understand test flow and difficult to extend.

**Files:**
- `fulfillment-service/it/it_tool.go` (1,263 lines)
- `osac-installer/base/osac-fulfillment-service/it/it_tool.go` (1,295 lines — duplicated)

**Cause:** Combines multiple concerns (Kind management, Helm deployment, health checking, token generation, gRPC client setup)

**Improvement Path:**
- Split into smaller components: `kind_manager.go`, `helm_deployer.go`, `health_checker.go`, `client_factory.go`
- Extract common test utilities into `internal/testing/` reusable packages
- Reduce code duplication between main and installer versions
- Add unit tests for the tool's individual components

---

### Complex Filter Translator (905 lines)

**Area:** Database Query Translation

**Problem:** The `filter_translator.go` in `fulfillment-service/internal/database/dao/` is 905 lines of SQL generation logic for CEL filter expressions.

**Files:**
- `fulfillment-service/internal/database/dao/filter_translator.go` (905 lines)

**Impact:**
- Difficult to maintain and test — requires deep knowledge of CEL, SQL, and protobuf reflection
- Query generation logic is hard to verify for correctness and SQL injection safety
- Adding support for new operators requires editing a monolithic file

**Improvement Path:**
- Break into smaller visitor pattern components for each expression type
- Extract CEL evaluation logic into separate concern from SQL translation
- Add comprehensive integration tests with SQL injection payloads
- Consider using a proven library like `github.com/google/cel-go` + `sqlc` for safer translation

---

### Missing Tests in Core Public Servers

**Area:** Test Coverage

**Problem:** Several critical public API servers lack unit tests or have minimal coverage:
- `security_groups_server.go`
- `virtual_networks_server.go`
- `subnets_server.go`
- `clusters_server.go`
- Mapper functions in `generic_mapper.go`

**Files:**
- `fulfillment-service/internal/servers/*_server.go` (see above)

**Impact:**
- Regressions in public APIs may not be caught until integration tests
- Tenant isolation bugs could go undetected in unit test phase
- Permission check logic is only tested end-to-end, not in isolation

**Priority:** High

**Approach:**
- Add unit test files following existing test pattern (Ginkgo + Gomega)
- Mock the database layer with `gomock`
- Test both positive cases (success) and negative cases (permission denied, not found)
- Test multi-tenant isolation with different tenant IDs

---

## Fragile Areas

### Boilerplate Test Code in Operator Controllers

**Files:**
- `osac-operator/internal/controller/*_controller_test.go`

**Why Fragile:**
- Generated template code contains multiple `TODO(user):` comments (lines 42, 73, 95 in `hostpool_controller_test.go`)
- Tests are incomplete and never fully implemented — assertions are empty or placeholder
- Each controller test file copies the same pattern, creating maintenance burden
- If the template changes, multiple test files get out of sync

**Safe Modification:**
- Create a test helper package to share common setup logic (context creation, resource creation, reconciliation)
- Use Ginkgo shared behaviors to avoid duplication
- Fill in actual assertions instead of TODO comments
- Add pre-commit hook to catch remaining `TODO(user):` markers

---

### Context.TODO() Usages in Tests

**Files:** Multiple test files use `context.TODO()` instead of proper context management:
- `osac-operator/internal/controller/webhook_common_test.go:18`
- `osac-operator/internal/controller/suite_test.go:69`
- `osac-operator/internal/controller/*_controller_test.go` (multiple files)

**Risk:**
- Tests don't respect context cancellation or timeouts
- Goroutine leaks possible if tests hang
- Resource cleanup may not happen properly if context dies

**Safe Modification:**
- Use `context.WithCancel()` in BeforeSuite with proper cleanup via DeferCleanup
- Apply timeout contexts to individual test cases
- Verify no goroutines are left running after tests

---

## Scaling Limits

### Hard-Coded Event Payload Type Switch in Generic Server

**Area:** Resource Type Scalability

**Limit:** The `GenericServer.setPayload()` method has explicit case statements for each resource type. Supporting more than ~15-20 resource types becomes unwieldy.

**Current Count:** 12 resource types (ClusterTemplate, Cluster, HostClass, Host, HostPool, Hub, ComputeInstanceTemplate, ComputeInstance, NetworkClass, VirtualNetwork, Subnet, SecurityGroup)

**Scaling Path:**
- Implement type registry pattern: `EventPayloadHandler` interface with `Handle(msg proto.Message, event *Event) error`
- Register handlers at startup: `registry.Register(&ClusterPayloadHandler{})`
- Call `registry.Handle(object, event)` instead of switch statement
- New resource types only need to implement the interface, no server changes needed

---

### gRPC Method Allowlist in OPA Policy

**Area:** Authorization Policy Maintenance

**Problem:** The Authorino AuthConfig contains a hard-coded list of allowed gRPC methods for client access (lines 132-164 in `authconfig.yaml`). Adding new public endpoints requires manual list maintenance and redeploy.

**Files:**
- `fulfillment-service/charts/service/templates/grpc-server/authconfig.yaml`

**Current Methods:** ~40 client-accessible methods listed

**Scaling Path:**
- Move method allowlist to ConfigMap for runtime updates without redeploy
- Implement service discovery of public methods via reflection API
- Use annotation-based method classification (`osac.openshift.io/public="true"`)
- Auto-generate allowlist from proto service definitions

---

## Dependencies at Risk

### Experimental gRPC ALPN Workaround Dependency

**Risk:** The codebase depends on `google.golang.org/grpc/security/advancedtls/experimentalcredentials.NewTLSWithALPNDisabled()` which is marked experimental. This function may be removed or changed in future gRPC versions.

**Impact:** If experimental function is removed, gRPC clients to OpenShift will fail

**Migration Plan:**
1. Monitor gRPC releases for ALPN support in OpenShift
2. Upgrade to new gRPC version when ALPN works with OpenShift router
3. Remove experimental credentials usage and switch back to standard `grpc.WithTransportCredentials(creds.NewTLS(tlsConfig))`
4. Have fallback: use standard credentials, only use experimental if gRPC version < 1.67

---

### OPA Version Constraint

**Risk:** Uses `open-policy-agent/opa v1.14.1`. OPA updates may change policy syntax or require policy rewrites.

**Files:**
- `fulfillment-service/go.mod` lists `github.com/open-policy-agent/opa v1.14.1`
- `fulfillment-service/charts/service/templates/grpc-server/authconfig.yaml` contains Rego policies

**Current Mitigation:**
- OPA 1.14.x is stable and widely used
- Policies use standard Rego (not bleeding-edge syntax)

**Recommendations:**
- Pin OPA version in Helm values and document upgrade procedure
- Test policy changes against new OPA versions before upgrading
- Keep Rego policies simple to avoid syntax incompatibilities

---

## Test Coverage Gaps

### Missing Unit Tests for Server Implementations

**What's Not Tested:** Public API server implementations for networking resources

**Files:**
- `fulfillment-service/internal/servers/virtual_networks_server.go`
- `fulfillment-service/internal/servers/subnets_server.go`
- `fulfillment-service/internal/servers/security_groups_server.go`
- `fulfillment-service/internal/servers/network_classes_server.go`

**Risk:**
- Tenant isolation bugs in CIDR validation or SecurityGroup rules won't be caught until integration tests
- Authorization logic may have edge cases (e.g., cross-tenant subnet creation)
- Permission checks for public vs. admin operations untested

**Priority:** High

**Fix:** Add unit test suite following pattern in `fulfillment-service/internal/servers/*_test.go`:
- Mock database layer with gomock
- Test Create with valid/invalid CIDR blocks
- Test List filtering by tenant ID
- Test permission checks (client vs. admin)
- Test multi-tenant isolation

---

### Operator Controller Reconciliation Logic Not Fully Tested

**What's Not Tested:** Feedback synchronization and phase mapping in operator controllers

**Files:**
- `osac-operator/internal/controller/feedback_controller.go` — `syncPhase()` logic incomplete
- `osac-operator/internal/controller/hostpool_feedback_controller.go` — `syncPhase()` has TODO
- `osac-operator/internal/controller/clusterorder_controller.go` — complex reconciliation loop

**Risk:**
- Stale status if phase mapping is incomplete
- Reconciliation loops may miss objects or requeue unnecessarily
- No detection of race conditions in controller logic

**Priority:** High

**Fix:** Expand controller tests to cover:
- All phases and transitions (Progressing → Ready, Failed, Deleting)
- Multiple reconciliation cycles
- Concurrent updates from multiple controllers

---

## Missing Critical Features

### No Garbage Collection for Event Notifications

**Problem:** Event notifications are stored in PostgreSQL NOTIFY queue, but there's no cleanup mechanism for old or failed notifications.

**Impact:**
- Database grows unbounded with abandoned events
- Notification queue may get congested
- No way to replay missed events

**Blocks:** Historical event auditing, event replaying for failed reconcilers

**Priority:** Medium

**Fix Approach:**
- Implement event retention policy (e.g., keep events 30 days)
- Add background job to purge old events
- Consider event replication to S3 or external event store for audit trail

---

### No Default Object Filter Implementation in Reconcilers

**Problem:** Reconcilers cannot filter objects, so all reconcilers process all object change events regardless of relevance.

**Impact:**
- Scalability limited — CPU usage scales with total resource count, not relevant resources
- No way to optimize reconciliation — e.g., "only process Clusters with state=Progressing"

**Blocks:** Efficient reconciliation at scale (1000+ resources)

---

## Summary

| Category | Count | Severity | Effort |
|----------|-------|----------|--------|
| Tech Debt | 3 | Medium | Medium |
| Known Bugs | 1 | Low | Medium |
| Security | 2 | Low | Medium |
| Performance | 3 | Low | Low |
| Fragile Areas | 2 | Medium | Medium |
| Scaling Limits | 2 | Medium | High |
| Dependencies at Risk | 2 | Low | Medium |
| Test Gaps | 3 | High | High |
| Missing Features | 2 | Medium | High |

**High Priority (Address First):**
1. Add unit tests for public API servers (test coverage)
2. Implement object filtering in reconcilers (blocking scalability)
3. Fix phase mapping in operator feedback (correctness)

**Medium Priority (Address in Next Cycle):**
1. Refactor generic server type coupling (maintainability)
2. Implement event payload table (robustness)
3. Extract integration test tool components (code quality)

**Low Priority (Address when time permits):**
1. Update ALPN handling when gRPC/OpenShift alignment improves
2. Fix KubeVirt console authentication for all auth types
3. Implement garbage collection for events

---

*Concerns audit: 2026-03-30*
