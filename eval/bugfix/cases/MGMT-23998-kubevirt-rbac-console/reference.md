# Real Fix: fulfillment-service PR #424

## Title
MGMT-23998: Log error when console backend connection fails

## Summary
## Summary

- Add ERROR-level logging when the KubeVirt WebSocket backend connection fails in the console server
- Previously, the error was returned to the client via gRPC but never logged server-side, making root cause diagnosis impossible from server logs (only INFO-level "Connecting to KubeVirt console" was visible)
- Logs: resource type, resource ID, hub, namespace, VM name, and the actual error

**Jira:** [MGMT-23998](https://issues.redhat.com/browse/MGMT-23998)
**Related:** RBAC fix in https://github.com/osac-project/osac-installer/pull/68

## Test plan

- [x] All 16 existing console unit tests pass (`ginkgo run --focus="Console" internal/servers`)
- [x] Verified log output includes full request context for diagnosis

Generated-By: Claude Code (Anthropic)

## Diff
```diff
diff --git a/internal/servers/console_server.go b/internal/servers/console_server.go
index 59fad70f..45b6bd83 100644
--- a/internal/servers/console_server.go
+++ b/internal/servers/console_server.go
@@ -184,6 +184,14 @@ func (s *consoleServer) Connect(stream publicv1.Console_ConnectServer) error {
 		if errors.As(err, &sessionErr) {
 			return status.Errorf(codes.FailedPrecondition, "%v", sessionErr)
 		}
+		s.logger.ErrorContext(ctx, "Failed to open console backend connection",
+			slog.String("resource_type", resourceType.String()),
+			slog.String("resource_id", resourceID),
+			slog.String("hub", target.HubID),
+			slog.String("namespace", target.Namespace),
+			slog.String("vm", target.VMName),
+			slog.Any("error", err),
+		)
 		return status.Errorf(codes.Internal, "failed to connect: %v", err)
 	}
 	defer conn.Close()
```

---

# Additional Fix: osac-installer PR #68

## Title
MGMT-23998: Add KubeVirt console RBAC for hub-access

## Diff
```diff
diff --git a/base/hub-access/rbac.yaml b/base/hub-access/rbac.yaml
index 1714371..c7b680a 100644
--- a/base/hub-access/rbac.yaml
+++ b/base/hub-access/rbac.yaml
@@ -130,3 +130,28 @@ subjects:
   - kind: ServiceAccount
     name: hub-access
     namespace: default
+---
+apiVersion: rbac.authorization.k8s.io/v1
+kind: ClusterRole
+metadata:
+  name: hub-access-console
+rules:
+  - apiGroups:
+      - subresources.kubevirt.io
+    resources:
+      - virtualmachineinstances/console
+    verbs:
+      - get
+---
+apiVersion: rbac.authorization.k8s.io/v1
+kind: ClusterRoleBinding
+metadata:
+  name: hub-access-console
+roleRef:
+  apiGroup: rbac.authorization.k8s.io
+  kind: ClusterRole
+  name: hub-access-console
+subjects:
+  - kind: ServiceAccount
+    name: hub-access
+    namespace: default
```
