# MGMT-23970: fulfillment-cli: TEMPLATE and HUB columns blank in ComputeInstance table output

## Description
When running fulfillment-cli get osac.public.v1.ComputeInstance or fulfillment-cli get osac.private.v1.ComputeInstance, the TEMPLATE column (both APIs) and HUB column (private API) always show blank, even when the underlying data is present.

Steps to reproduce:
fulfillment-cli get osac.public.v1.ComputeInstance  # TEMPLATE column is empty
fulfillment-cli get osac.private.v1.ComputeInstance  # TEMPLATE and HUB columns are empty

Confirmed that the data IS present via -o yaml:
- spec.template: osac.templates.ocp_virt_vm
- status.hub: hypershift1

Root cause:
In internal/rendering/table_renderer.go, lookupName() performs a gRPC lookup to resolve a template/hub reference to its human-readable name. All error paths (helper not found, list call failed, no items returned) correctly fall back to returning the raw key. However, when the object IS found but its metadata.name is empty string, the function returns "" with no fallback.

// lookupName line ~481:
result = metadata.GetName()   // returns "" when name not set
// missing: if result == "" { result = key }

Fix: Add a fallback to key in lookupName when GetName() returns empty string. Consistent with all other fallback paths in the same function.

## Comments
None

## Attachments
None
