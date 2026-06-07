# MGMT-23662: subnet-namespace annotation not persisted to API server during reconciliation

## Description
The osac.openshift.io/subnet-namespace annotation is set on the in-memory ComputeInstance object during reconciliation but never written to the API server. The Reconcile() function only calls r.Status().Update() (status subresource), not r.Update() for metadata. The annotation is lost after reconciliation because the metadata change is never persisted.

Steps to reproduce:
1. Create a ComputeInstance with a subnetRef pointing to an existing Subnet CR
2. Let the controller reconcile the ComputeInstance
3. Check the ComputeInstance annotations on the API server

Expected: The osac.openshift.io/subnet-namespace annotation should be persisted to the API server so that AAP (which reads from the API server, not in-memory) can use it during provisioning.
Actual: The annotation is set in memory but only r.Status().Update() is called, which updates the status subresource only. The annotation is lost.

## Comments
None

## Attachments
None
