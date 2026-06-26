# MGMT-24142: osac get networkclasses fails — missing table rendering YAML

## Description
osac get networkclasses crashes with a file-not-found error because the table rendering definition for NetworkClass is missing from fulfillment-service. All sibling resources (Cluster, Subnet, VirtualNetwork, SecurityGroup, HostClass, etc.) have their osac.public.v1.<Type>.yaml file; NetworkClass was never added.

How reproducible: Always

Steps to reproduce:
Run: osac get networkclasses

Expected: Table output listing NetworkClass objects.
Actual: Error: open tables/osac.public.v1.NetworkClass.yaml: file does not exist

Root cause:
internal/rendering/tables/osac.public.v1.NetworkClass.yaml (and osac.private.v1.NetworkClass.yaml) are absent from fulfillment-service. The NetworkClass resource is otherwise fully implemented — gRPC server (network_classes_server.go), proto-generated types (network_class_type.pb.go), and the osac CLI binary all reference it. Only the table rendering YAML is missing.

Fix:
Add osac.public.v1.NetworkClass.yaml and osac.private.v1.NetworkClass.yaml to fulfillment-service/internal/rendering/tables/, modelled on osac.public.v1.VirtualNetwork.yaml or another networking sibling.

## Comments
None

## Attachments
None
