# Real Fix: fulfillment-service PR #351

## Title
MGMT-23638: fix public VirtualNetwork API missing default region

## Summary
## Summary
- The public VirtualNetwork `Create` endpoint (`/api/fulfillment/v1/virtual_networks`) was rejecting all requests with `field 'spec.region' is required`
- The public API proto doesn't expose a `region` field, but the private server (delegate) requires it
- Fix: set `region` to `"default"` in the public server before delegating to the private server
- Added unit test verifying the default region is set correctly

## Jira
[MGMT-23638](https://issues.redhat.com/browse/MGMT-23638)

## Test plan
- [x] Unit test added and passing: `Create object via public API sets default region`
- [x] `go build ./...` passes
- [x] `gofmt -s -l .` clean

🤖 Generated with [Claude Code](https://claude.com/claude-code)

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

* **New Features**
  * Virtual networks now automatically receive a default region when one is not specified during creation.

* **Tests**
  * Added test coverage to verify default region assignment in virtual network creation.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->

## Diff
```diff
diff --git a/internal/servers/virtual_networks_server.go b/internal/servers/virtual_networks_server.go
index 45157fe9..e5eefcdd 100644
--- a/internal/servers/virtual_networks_server.go
+++ b/internal/servers/virtual_networks_server.go
@@ -212,6 +212,11 @@ func (s *VirtualNetworksServer) Create(ctx context.Context,
 		return
 	}
 
+	// Set default region if not provided (public API doesn't expose region):
+	if privateVirtualNetwork.HasSpec() && privateVirtualNetwork.GetSpec().GetRegion() == "" {
+		privateVirtualNetwork.GetSpec().SetRegion("default")
+	}
+
 	// Delegate to the private server:
 	privateRequest := &privatev1.VirtualNetworksCreateRequest{}
 	privateRequest.SetObject(privateVirtualNetwork)
diff --git a/internal/servers/virtual_networks_server_test.go b/internal/servers/virtual_networks_server_test.go
index 4a20e3e9..5c7c5e6e 100644
--- a/internal/servers/virtual_networks_server_test.go
+++ b/internal/servers/virtual_networks_server_test.go
@@ -294,6 +294,32 @@ var _ = Describe("Virtual networks server", func() {
 			Expect(getResponse.GetObject().GetMetadata().GetName()).To(Equal("updated-name"))
 		})
 
+		It("Create object via public API sets default region", func() {
+			// Create a VirtualNetwork via the public server (no region field):
+			createResponse, err := publicServer.Create(ctx, publicv1.VirtualNetworksCreateRequest_builder{
+				Object: publicv1.VirtualNetwork_builder{
+					Metadata: publicv1.Metadata_builder{
+						Name: "public-vn",
+					}.Build(),
+					Spec: publicv1.VirtualNetworkSpec_builder{
+						NetworkClass: "default",
+						Ipv4Cidr:     proto.String("10.0.0.0/16"),
+					}.Build(),
+				}.Build(),
+			}.Build())
+			Expect(err).ToNot(HaveOccurred())
+			publicObj := createResponse.GetObject()
+			Expect(publicObj.GetId()).ToNot(BeEmpty())
+			Expect(publicObj.GetSpec().GetNetworkClass()).To(Equal("default"))
+
+			// Verify via private server that region was set to "default":
+			privateGetResponse, err := privateServer.Get(ctx, privatev1.VirtualNetworksGetRequest_builder{
+				Id: publicObj.GetId(),
+			}.Build())
+			Expect(err).ToNot(HaveOccurred())
+			Expect(privateGetResponse.GetObject().GetSpec().GetRegion()).To(Equal("default"))
+		})
+
 		It("Delete object", func() {
 			// Create the object via the private server:
 			privateObj := createVirtualNetwork()
```
