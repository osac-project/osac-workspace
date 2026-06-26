# MGMT-23654: Public SecurityGroup Create returns 500: unknown object type

## Description
The public SecurityGroup Create endpoint returns HTTP 500 with error: unknown object type '*privatev1.SecurityGroup'

The error originates from GenericServer.Create in generic_server.go, called via PrivateSecurityGroupsServer.Create -> SecurityGroupsServer.Create.

Steps to reproduce:
curl -s -X POST $API/api/fulfillment/v1/security_groups -d '{
  "metadata": {"name": "test-sg"},
  "spec": {
    "virtual_network": "",
    "ingress": [{"protocol": "PROTOCOL_TCP", "port_from": 22, "port_to": 22, "ipv4_cidr": "0.0.0.0/0"}],
    "egress": [{"protocol": "PROTOCOL_ALL", "ipv4_cidr": "0.0.0.0/0"}]
  }
}'

Returns: {"code":13,"message":"failed to create object"}
Server log: unknown object type '*privatev1.SecurityGroup'

Expected: SecurityGroup should be created and returned with a generated ID.
Actual: HTTP 500 / gRPC INTERNAL error. The SecurityGroup CRUD is not functional.

Affected components:
- fulfillment-service/internal/servers/generic_server.go (type registry / setPayload switch)

## Comments
None

## Attachments
None
