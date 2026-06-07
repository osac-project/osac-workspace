# MGMT-23473: Creating subnets with overlapping CIDRs within the same VirtualNetwork

## Description
The fulfillment-service does not validate that a new Subnet's CIDR doesn't overlap with existing Subnets under the same VirtualNetwork. Two Subnets with identical or overlapping IPv4/IPv6 CIDRs can be created, leading to conflicting network configurations on the target cluster.

Steps to reproduce:
1. Create a VirtualNetwork: ./scripts/networking.sh create-vn my-vnet <nc-id> 10.200.0.0/16
2. Create first subnet: ./scripts/networking.sh create-subnet subnet-a <vn-id> 10.200.1.0/24
3. Create second subnet with the same CIDR — should fail but succeeds: ./scripts/networking.sh create-subnet subnet-b <vn-id> 10.200.1.0/24

Expected: The second CreateSubnet call should return an error (e.g., ALREADY_EXISTS or INVALID_ARGUMENT) indicating that 10.200.1.0/24 overlaps with an existing subnet in the same VirtualNetwork.
Actual: The second subnet is created without error.

Comment from Eran Cohen: The CIDR overlap check should be added in the fulfillment-service at subnet creation time (private_subnets_server.go or the subnet reconciler), querying existing subnets for the same virtualNetwork and comparing CIDRs before persisting.

## Comments
None

## Attachments
None
