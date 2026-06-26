# MGMT-24061: Disable scm_update_on_launch in AAP job templates — slows down job processing

## Description
AAP job templates in the config-as-code have scm_update_on_launch: true, which triggers an SCM sync before every job execution. This significantly slows down job processing for all networking resources (VirtualNetwork, Subnet, SecurityGroup, ComputeInstance), adding unnecessary delay to every provisioning/deprovisioning operation.

How reproducible: Always — every AAP job launch triggers an SCM update.

Steps to reproduce:
1. Trigger any networking provisioning job (VirtualNetwork create, Subnet create, etc.)
2. Observe AAP job queue — SCM sync runs before the actual job
3. Job total time is significantly inflated by the sync step

Expected: scm_update_on_launch: false on all job templates. SCM updates should be managed separately, not triggered per-job.
Actual: scm_update_on_launch: true causes an SCM sync before every job execution, slowing down all provisioning operations.

## Comments
None

## Attachments
None
