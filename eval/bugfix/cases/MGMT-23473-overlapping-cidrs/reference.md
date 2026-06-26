# Real Fix: fulfillment-service PR #330

## Title
MGMT-23473: validate subnet CIDR overlap within same VirtualNetwork

## Summary
## Summary

- Reject subnet creation when the new subnet's IPv4 or IPv6 CIDR overlaps with any existing subnet in the same VirtualNetwork
- Returns `ALREADY_EXISTS` gRPC status with details about the conflicting subnet (name and CIDR)
- Uses existing `GenericServer.List()` with a filter to query sibling subnets — no new DAO required

## Details

Previously, two subnets with identical or overlapping CIDRs could be created in the same VirtualNetwork, which would result in conflicting network configurations on the target cluster (duplicate CUDNs with the same CIDR range).

The overlap check covers:
- Exact CIDR match (e.g., `10.0.1.0/24` vs `10.0.1.0/24`)
- Subset overlap (e.g., `10.0.1.0/24` within existing `10.0.0.0/20`)
- Superset overlap (e.g., `10.0.0.0/20` containing existing `10.0.1.0/24`)
- Both IPv4 and IPv6 CIDR fields
- Subnets in different VirtualNetworks are unaffected (same CIDR is allowed)

## Test plan

- [x] Rejects subnet with exact same IPv4 CIDR (returns `ALREADY_EXISTS`)
- [x] Rejects subnet where new CIDR is a subset of existing
- [x] Rejects subnet where new CIDR is a superset of existing
- [x] Accepts non-overlapping CIDRs in the same VirtualNetwork
- [x] Allows same CIDR in different VirtualNetworks
- [x] Rejects overlapping IPv6 CIDRs
- [x] All 387 existing tests continue to pass

## Diff
```diff
diff --git a/internal/servers/private_subnets_server.go b/internal/servers/private_subnets_server.go
index cf554ee0..1360be7e 100644
--- a/internal/servers/private_subnets_server.go
+++ b/internal/servers/private_subnets_server.go
@@ -16,6 +16,7 @@ package servers
 import (
 	"context"
 	"errors"
+	"fmt"
 	"log/slog"
 	"net"
 
@@ -336,9 +337,98 @@ func (s *PrivateSubnetsServer) validateVirtualNetworkReference(ctx context.Conte
 		}
 	}
 
+	// Validate no CIDR overlap with existing subnets in the same VirtualNetwork:
+	if err := s.validateNoCIDROverlap(ctx, spec); err != nil {
+		return err
+	}
+
+	return nil
+}
+
+// validateNoCIDROverlap checks that the new subnet's CIDRs don't overlap with any existing
+// subnets in the same VirtualNetwork.
+// Note: this check is not fully atomic; concurrent subnet creation could bypass overlap
+// validation. A locking mechanism would be needed for complete reliability.
+func (s *PrivateSubnetsServer) validateNoCIDROverlap(ctx context.Context,
+	spec *privatev1.SubnetSpec) error {
+
+	// Fetch all existing subnets for the same VirtualNetwork using pagination:
+	filter := fmt.Sprintf("this.spec.virtual_network == '%s'", spec.GetVirtualNetwork())
+	var allSubnets []*privatev1.Subnet
+	var offset int32
+	for {
+		listRequest := &privatev1.SubnetsListRequest{}
+		listRequest.SetFilter(filter)
+		listRequest.SetOffset(offset)
+		var listResponse *privatev1.SubnetsListResponse
+		if err := s.generic.List(ctx, listRequest, &listResponse); err != nil {
+			s.logger.ErrorContext(
+				ctx,
+				"Failed to list sibling subnets",
+				slog.String("virtual_network_id", spec.GetVirtualNetwork()),
+				slog.Any("error", err),
+			)
+			return grpcstatus.Errorf(grpccodes.Internal, "failed to validate CIDR overlap")
+		}
+		allSubnets = append(allSubnets, listResponse.GetItems()...)
+		if offset+listResponse.GetSize() >= listResponse.GetTotal() {
+			break
+		}
+		offset += listResponse.GetSize()
+	}
+
+	for _, existing := range allSubnets {
+		existingSpec := existing.GetSpec()
+
+		// Check IPv4 overlap:
+		if spec.HasIpv4Cidr() && existingSpec.HasIpv4Cidr() {
+			overlap, err := cidrsOverlap(spec.GetIpv4Cidr(), existingSpec.GetIpv4Cidr())
+			if err != nil {
+				return grpcstatus.Errorf(grpccodes.Internal,
+					"failed to parse CIDRs for overlap check: %v", err)
+			}
+			if overlap {
+				return grpcstatus.Errorf(grpccodes.AlreadyExists,
+					"subnet IPv4 CIDR '%s' overlaps with existing subnet '%s' (CIDR '%s') "+
+						"in VirtualNetwork '%s'",
+					spec.GetIpv4Cidr(), existing.GetMetadata().GetName(),
+					existingSpec.GetIpv4Cidr(), spec.GetVirtualNetwork())
+			}
+		}
+
+		// Check IPv6 overlap:
+		if spec.HasIpv6Cidr() && existingSpec.HasIpv6Cidr() {
+			overlap, err := cidrsOverlap(spec.GetIpv6Cidr(), existingSpec.GetIpv6Cidr())
+			if err != nil {
+				return grpcstatus.Errorf(grpccodes.Internal,
+					"failed to parse CIDRs for overlap check: %v", err)
+			}
+			if overlap {
+				return grpcstatus.Errorf(grpccodes.AlreadyExists,
+					"subnet IPv6 CIDR '%s' overlaps with existing subnet '%s' (CIDR '%s') "+
+						"in VirtualNetwork '%s'",
+					spec.GetIpv6Cidr(), existing.GetMetadata().GetName(),
+					existingSpec.GetIpv6Cidr(), spec.GetVirtualNetwork())
+			}
+		}
+	}
+
 	return nil
 }
 
+// cidrsOverlap returns true if two CIDRs overlap (one contains any part of the other).
+func cidrsOverlap(cidrA, cidrB string) (bool, error) {
+	_, netA, errA := net.ParseCIDR(cidrA)
+	_, netB, errB := net.ParseCIDR(cidrB)
+	if errA != nil || errB != nil {
+		return false, fmt.Errorf(
+			"failed to parse CIDRs: %q: %v, %q: %v",
+			cidrA, errA, cidrB, errB,
+		)
+	}
+	return netA.Contains(netB.IP) || netB.Contains(netA.IP), nil
+}
+
 // validateImmutableFieldsSubnet validates that immutable fields have not been changed.
 func validateImmutableFieldsSubnet(newSubnet *privatev1.Subnet, existingSubnet *privatev1.Subnet) error {
 	if existingSubnet == nil {
diff --git a/internal/servers/private_subnets_server_test.go b/internal/servers/private_subnets_server_test.go
index fae0b86f..dd96526e 100644
--- a/internal/servers/private_subnets_server_test.go
+++ b/internal/servers/private_subnets_server_test.go
@@ -31,8 +31,9 @@ import (
 
 var _ = Describe("Private subnets server", func() {
 	var (
-		ctx context.Context
-		tx  database.Tx
+		ctx       context.Context
+		tx        database.Tx
+		subnetDao *dao.GenericDAO[*privatev1.Subnet]
 	)
 
 	BeforeEach(func() {
@@ -67,6 +68,15 @@ var _ = Describe("Private subnets server", func() {
 		// Create the tables:
 		err = dao.CreateTables(ctx, "subnets", "virtual_networks", "network_classes")
 		Expect(err).ToNot(HaveOccurred())
+
+		// Create the subnet DAO:
+		subnetDao, err = dao.NewGenericDAO[*privatev1.Subnet]().
+			SetLogger(logger).
+			SetTable("subnets").
+			SetAttributionLogic(attribution).
+			SetTenancyLogic(tenancy).
+			Build()
+		Expect(err).ToNot(HaveOccurred())
 	})
 
 	// Helper function to create a NetworkClass for validation tests
@@ -684,15 +694,6 @@ var _ = Describe("Private subnets server", func() {
 			It("verifies ownerReference annotation is set after Create", func() {
 				vn := createVirtualNetwork(ctx, "10.0.0.0/16", "")
 
-				// Create Subnet DAO for Create operation
-				subnetDao, err := dao.NewGenericDAO[*privatev1.Subnet]().
-					SetLogger(logger).
-					SetTable("subnets").
-					SetAttributionLogic(attribution).
-					SetTenancyLogic(tenancy).
-					Build()
-				Expect(err).ToNot(HaveOccurred())
-
 				subnet := privatev1.Subnet_builder{
 					Spec: privatev1.SubnetSpec_builder{
 						Ipv4Cidr:       proto.String("10.0.1.0/24"),
@@ -701,7 +702,7 @@ var _ = Describe("Private subnets server", func() {
 				}.Build()
 
 				// Simulate what Create operation does (validation + annotation)
-				err = server.validateSubnet(ctx, subnet, nil)
+				err := server.validateSubnet(ctx, subnet, nil)
 				Expect(err).ToNot(HaveOccurred())
 
 				// Set owner reference annotation
@@ -776,6 +777,138 @@ var _ = Describe("Private subnets server", func() {
 			})
 		})
 
+		Context("CIDR overlap validation", func() {
+			// Helper to create a subnet directly in the database
+			createSubnetInDB := func(ctx context.Context, name, ipv4Cidr, ipv6Cidr, virtualNetworkID string) {
+				builder := privatev1.SubnetSpec_builder{
+					VirtualNetwork: virtualNetworkID,
+				}
+				if ipv4Cidr != "" {
+					builder.Ipv4Cidr = proto.String(ipv4Cidr)
+				}
+				if ipv6Cidr != "" {
+					builder.Ipv6Cidr = proto.String(ipv6Cidr)
+				}
+
+				subnet := privatev1.Subnet_builder{
+					Metadata: privatev1.Metadata_builder{
+						Name: name,
+					}.Build(),
+					Spec: builder.Build(),
+				}.Build()
+
+				_, err := subnetDao.Create().
+					SetObject(subnet).
+					Do(ctx)
+				Expect(err).ToNot(HaveOccurred())
+			}
+
+			It("rejects subnet with exact same IPv4 CIDR", func() {
+				vn := createVirtualNetwork(ctx, "10.0.0.0/16", "")
+				createSubnetInDB(ctx, "existing-subnet", "10.0.1.0/24", "", vn.GetId())
+
+				newSubnet := privatev1.Subnet_builder{
+					Spec: privatev1.SubnetSpec_builder{
+						Ipv4Cidr:       proto.String("10.0.1.0/24"),
+						VirtualNetwork: vn.GetId(),
+					}.Build(),
+				}.Build()
+
+				err := server.validateSubnet(ctx, newSubnet, nil)
+				Expect(err).To(HaveOccurred())
+				status, ok := grpcstatus.FromError(err)
+				Expect(ok).To(BeTrue())
+				Expect(status.Code()).To(Equal(grpccodes.AlreadyExists))
+				Expect(err.Error()).To(ContainSubstring("overlaps"))
+				Expect(err.Error()).To(ContainSubstring("existing-subnet"))
+			})
+
+			It("rejects subnet with overlapping IPv4 CIDR (new is subset)", func() {
+				vn := createVirtualNetwork(ctx, "10.0.0.0/16", "")
+				createSubnetInDB(ctx, "wide-subnet", "10.0.0.0/20", "", vn.GetId())
+
+				newSubnet := privatev1.Subnet_builder{
+					Spec: privatev1.SubnetSpec_builder{
+						Ipv4Cidr:       proto.String("10.0.1.0/24"),
+						VirtualNetwork: vn.GetId(),
+					}.Build(),
+				}.Build()
+
+				err := server.validateSubnet(ctx, newSubnet, nil)
+				Expect(err).To(HaveOccurred())
+				status, ok := grpcstatus.FromError(err)
+				Expect(ok).To(BeTrue())
+				Expect(status.Code()).To(Equal(grpccodes.AlreadyExists))
+			})
+
+			It("rejects subnet with overlapping IPv4 CIDR (new is superset)", func() {
+				vn := createVirtualNetwork(ctx, "10.0.0.0/16", "")
+				createSubnetInDB(ctx, "narrow-subnet", "10.0.1.0/24", "", vn.GetId())
+
+				newSubnet := privatev1.Subnet_builder{
+					Spec: privatev1.SubnetSpec_builder{
+						Ipv4Cidr:       proto.String("10.0.0.0/20"),
+						VirtualNetwork: vn.GetId(),
+					}.Build(),
+				}.Build()
+
+				err := server.validateSubnet(ctx, newSubnet, nil)
+				Expect(err).To(HaveOccurred())
+				status, ok := grpcstatus.FromError(err)
+				Expect(ok).To(BeTrue())
+				Expect(status.Code()).To(Equal(grpccodes.AlreadyExists))
+			})
+
+			It("accepts subnet with non-overlapping IPv4 CIDR", func() {
+				vn := createVirtualNetwork(ctx, "10.0.0.0/16", "")
+				createSubnetInDB(ctx, "first-subnet", "10.0.1.0/24", "", vn.GetId())
+
+				newSubnet := privatev1.Subnet_builder{
+					Spec: privatev1.SubnetSpec_builder{
+						Ipv4Cidr:       proto.String("10.0.2.0/24"),
+						VirtualNetwork: vn.GetId(),
+					}.Build(),
+				}.Build()
+
+				err := server.validateSubnet(ctx, newSubnet, nil)
+				Expect(err).ToNot(HaveOccurred())
+			})
+
+			It("allows same CIDR in different VirtualNetworks", func() {
+				vn1 := createVirtualNetwork(ctx, "10.0.0.0/16", "")
+				vn2 := createVirtualNetwork(ctx, "10.0.0.0/16", "")
+				createSubnetInDB(ctx, "vn1-subnet", "10.0.1.0/24", "", vn1.GetId())
+
+				newSubnet := privatev1.Subnet_builder{
+					Spec: privatev1.SubnetSpec_builder{
+						Ipv4Cidr:       proto.String("10.0.1.0/24"),
+						VirtualNetwork: vn2.GetId(),
+					}.Build(),
+				}.Build()
+
+				err := server.validateSubnet(ctx, newSubnet, nil)
+				Expect(err).ToNot(HaveOccurred())
+			})
+
+			It("rejects subnet with overlapping IPv6 CIDR", func() {
+				vn := createVirtualNetwork(ctx, "", "2001:db8::/32")
+				createSubnetInDB(ctx, "existing-v6", "", "2001:db8:1::/48", vn.GetId())
+
+				newSubnet := privatev1.Subnet_builder{
+					Spec: privatev1.SubnetSpec_builder{
+						Ipv6Cidr:       proto.String("2001:db8:1::/48"),
+						VirtualNetwork: vn.GetId(),
+					}.Build(),
+				}.Build()
+
+				err := server.validateSubnet(ctx, newSubnet, nil)
+				Expect(err).To(HaveOccurred())
+				status, ok := grpcstatus.FromError(err)
+				Expect(ok).To(BeTrue())
+				Expect(status.Code()).To(Equal(grpccodes.AlreadyExists))
+			})
+		})
+
 		// SUB-VAL-12, SUB-VAL-13: Tenant isolation for Delete and List operations
 		// are covered by servers_tenancy_test.go, not validation tests
 	})
```
