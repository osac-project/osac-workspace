# MGMT-23998: Missing KubeVirt RBAC for hub-access breaks VM serial console

## Description
The VM serial console feature fails on deployments where the hub-access service account lacks RBAC permissions for the KubeVirt console subresource. The CLI enters a reconnect loop with no actionable error message, and the server logs show no error — only INFO-level "Connecting to KubeVirt console" messages.

Root Cause:
The hub-access service account (defined in osac-installer/base/hub-access/rbac.yaml) only has permissions for OSAC CRDs (clusterorders, computeinstances) and secrets. It is missing the KubeVirt permission required by the serial console feature:
- apiGroups: subresources.kubevirt.io
- resources: virtualmachineinstances/console
- verbs: get

Since VMs can be created in different namespaces (per-order or per-tenant), this must be a ClusterRole with a ClusterRoleBinding, not a namespace-scoped Role.

Secondary Issue - Silent Failure:
The fulfillment-service does not log the backend connection error. In console_server.go, when manager.Connect() fails, the error is returned as a gRPC status code but never logged at ERROR level. This makes diagnosing the issue from server logs impossible.

Reproduction:
$ fulfillment-cli console computeinstance test2
Connecting to 019d9abe-73c5-7e75-a90d-7e360989c594...
Connection lost. Reconnecting...
Connection lost. Reconnecting (attempt 2/5)...

Server log shows only:
{"time":"...","level":"INFO","msg":"Connecting to KubeVirt console","hub":"hypershift1","namespace":"osac-agentil","vm":"vm-j5pht"}

Fix (two repos):
1. osac-installer: Add a ClusterRole and ClusterRoleBinding granting the hub-access service account get on virtualmachineinstances/console in the subresources.kubevirt.io API group.
2. fulfillment-service: Log at ERROR level when the backend connection fails in console_server.go.

## Comments
None

## Attachments
None
