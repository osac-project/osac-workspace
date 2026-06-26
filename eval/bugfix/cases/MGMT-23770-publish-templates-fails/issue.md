# MGMT-23770: Network class publication from AAP fails

## Description
Publication of network classes fails from AAP with the following error:

TASK [osac.service.publish_templates : Create list of existing NetworkClass IDs]
fatal: [localhost]: FAILED! => {"msg": "The conditional check 'network_class_check is success and network_class_check.json.size > 0' failed. The error was: error while evaluating conditional (network_class_check is success and network_class_check.json.size > 0): 'dict object' has no attribute 'size'"}

The error appears in /runner/project/collections/ansible_collections/osac/service/roles/publish_templates/tasks/network_classes.yaml line 9.

This happens because there are no existing network classes in the fulfillment-service, and the API response dict doesn't have a 'size' attribute.

Component versions:
- fulfillment-cli: 0.0.50
- fulfillment-service/controller/rest-gateway: ghcr.io/osac-project/fulfillment-service@sha256:1e2f47d6...

## Comments
None

## Attachments
None
