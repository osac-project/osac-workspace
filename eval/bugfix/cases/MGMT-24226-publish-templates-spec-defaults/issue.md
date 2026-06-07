# MGMT-24226: [OSAC] osac-publish-templates job fails

## Description
The osac-publish-templates job fails with the following error:

TASK [osac.service.publish_templates : Create new ComputeInstance template]
[ERROR]: Task failed: Module failed: Status code was 400 and not [200]: HTTP Error 400: Bad Request

The error details show:
{"code": 3, "message": "proto: (line 1:579): unknown field \"spec_defaults\""}

The template payload being sent includes a spec_defaults field:
"spec_defaults": {"boot_disk": {"size_gib": 10}, "cores": 2, "image": {"source_ref": " ", "source_type": "registry"}, "memory_gib": 2, "run_strategy": "Always"}

But the fulfillment-service proto for ComputeInstanceTemplate does not have a spec_defaults field yet.

Steps to reproduce:
Let the setup.sh script finish — the osac-publish-templates job should succeed but fails.

Expected: The osac-publish-templates job should succeed.

Root cause: The AAP collection was updated to send spec_defaults before the fulfillment-service proto was updated to accept it, and CI overlays were not pinned to the correct submodule commit.

## Comments
None

## Attachments
None
