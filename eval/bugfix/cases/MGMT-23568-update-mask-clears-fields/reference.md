# Real Fix: fulfillment-service PR #345

## Title
MGMT-23601: Fix ComputeInstance Update to respect field masks

## Summary
https://issues.redhat.com/browse/MGMT-23601
(Duplicate of https://redhat.atlassian.net/browse/MGMT-23568)

The public ComputeInstances server ignores the update_mask on Update
requests. Copy() wipes all unset fields from the existing DB record,
and the Update is sent to the private server without the mask,
causing a full replace that destroyed existing fields.

Fix: when an update_mask is present, create a fresh object with only
the masked fields and pass the mask to the private server. This
matches the pattern already used by the Clusters server.

Also make the private server's template and network validations
mask-aware, matching the Clusters server's pattern.

## Diff
```diff
diff --git a/internal/servers/compute_instances_server.go b/internal/servers/compute_instances_server.go
index b0c99007..4bdceb4f 100644
--- a/internal/servers/compute_instances_server.go
+++ b/internal/servers/compute_instances_server.go
@@ -253,17 +253,24 @@ func (s *ComputeInstancesServer) Update(ctx context.Context,
 		return
 	}
 
-	// Get the existing object from the private server:
-	getRequest := &privatev1.ComputeInstancesGetRequest{}
-	getRequest.SetId(id)
-	getResponse, err := s.delegate.Get(ctx, getRequest)
-	if err != nil {
-		return nil, err
+	// Determine how to prepare the private compute instance based on whether there's a field mask.
+	// When there's a field mask, copy to a new object and let the generic server handle the merge
+	// with the database object, which correctly applies field mask semantics.
+	var privateComputeInstance *privatev1.ComputeInstance
+	updateMask := request.GetUpdateMask()
+	if len(updateMask.GetPaths()) > 0 {
+		privateComputeInstance = &privatev1.ComputeInstance{}
+		privateComputeInstance.SetId(id)
+	} else {
+		getRequest := &privatev1.ComputeInstancesGetRequest{}
+		getRequest.SetId(id)
+		getResponse, err := s.delegate.Get(ctx, getRequest)
+		if err != nil {
+			return nil, err
+		}
+		privateComputeInstance = getResponse.GetObject()
 	}
-	existingPrivateComputeInstance := getResponse.GetObject()
-
-	// Map the public changes to the existing private object (preserving private data):
-	err = s.inMapper.Copy(ctx, publicComputeInstance, existingPrivateComputeInstance)
+	err = s.inMapper.Copy(ctx, publicComputeInstance, privateComputeInstance)
 	if err != nil {
 		s.logger.ErrorContext(
 			ctx,
@@ -274,9 +281,10 @@ func (s *ComputeInstancesServer) Update(ctx context.Context,
 		return
 	}
 
-	// Delegate to the private server with the merged object:
+	// Delegate to the private server:
 	privateRequest := &privatev1.ComputeInstancesUpdateRequest{}
-	privateRequest.SetObject(existingPrivateComputeInstance)
+	privateRequest.SetObject(privateComputeInstance)
+	privateRequest.SetUpdateMask(updateMask)
 	privateResponse, err := s.delegate.Update(ctx, privateRequest)
 	if err != nil {
 		return nil, err
diff --git a/internal/servers/compute_instances_server_test.go b/internal/servers/compute_instances_server_test.go
index 90b06145..ed29d745 100644
--- a/internal/servers/compute_instances_server_test.go
+++ b/internal/servers/compute_instances_server_test.go
@@ -23,6 +23,7 @@ import (
 	"google.golang.org/protobuf/proto"
 	"google.golang.org/protobuf/types/known/anypb"
 	"google.golang.org/protobuf/types/known/fieldmaskpb"
+	"google.golang.org/protobuf/types/known/timestamppb"
 	"google.golang.org/protobuf/types/known/wrapperspb"
 
 	privatev1 "github.com/osac-project/fulfillment-service/internal/api/osac/private/v1"
@@ -338,13 +339,22 @@ var _ = Describe("Compute instances server", func() {
 		It("Updates object", func() {
 			// Create templates first
 			createTemplate("general.small")
-			createTemplate("general.large")
 
-			// Create an object:
+			// Create an object with explicit fields:
 			createResponse, err := server.Create(ctx, publicv1.ComputeInstancesCreateRequest_builder{
 				Object: publicv1.ComputeInstance_builder{
 					Spec: publicv1.ComputeInstanceSpec_builder{
-						Template: "general.small",
+						Template:    "general.small",
+						Cores:       proto.Int32(4),
+						MemoryGib:   proto.Int32(8),
+						RunStrategy: proto.String("Always"),
+						Image: publicv1.ComputeInstanceImage_builder{
+							SourceType: "registry",
+							SourceRef:  "quay.io/test:latest",
+						}.Build(),
+						BootDisk: publicv1.ComputeInstanceDisk_builder{
+							SizeGib: 20,
+						}.Build(),
 					}.Build(),
 					Status: publicv1.ComputeInstanceStatus_builder{
 						State: publicv1.ComputeInstanceState_COMPUTE_INSTANCE_STATE_STARTING,
@@ -352,34 +362,50 @@ var _ = Describe("Compute instances server", func() {
 				}.Build(),
 			}.Build())
 			Expect(err).ToNot(HaveOccurred())
-			Expect(createResponse).ToNot(BeNil())
-			createdObject := createResponse.GetObject()
-			Expect(createdObject).ToNot(BeNil())
-			id := createdObject.GetId()
-			Expect(id).ToNot(BeEmpty())
+			id := createResponse.GetObject().GetId()
 
-			// Update the object:
+			// Update only restart_requested_at via field mask, explicit fields must survive:
+			restartTime := timestamppb.Now()
 			updateResponse, err := server.Update(ctx, publicv1.ComputeInstancesUpdateRequest_builder{
 				Object: publicv1.ComputeInstance_builder{
 					Id: id,
 					Spec: publicv1.ComputeInstanceSpec_builder{
-						Template: "general.large",
-					}.Build(),
-					Status: publicv1.ComputeInstanceStatus_builder{
-						State: publicv1.ComputeInstanceState_COMPUTE_INSTANCE_STATE_RUNNING,
+						RestartRequestedAt: restartTime,
 					}.Build(),
 				}.Build(),
 				UpdateMask: &fieldmaskpb.FieldMask{
-					Paths: []string{"spec.template", "status.state"},
+					Paths: []string{"spec.restart_requested_at"},
 				},
 			}.Build())
 			Expect(err).ToNot(HaveOccurred())
-			Expect(updateResponse).ToNot(BeNil())
 			object := updateResponse.GetObject()
-			Expect(object).ToNot(BeNil())
 			Expect(object.GetId()).To(Equal(id))
-			Expect(object.GetSpec().GetTemplate()).To(Equal("general.large"))
-			Expect(object.GetStatus().GetState()).To(Equal(publicv1.ComputeInstanceState_COMPUTE_INSTANCE_STATE_RUNNING))
+
+			// Verify the masked field was updated:
+			Expect(object.GetSpec().GetRestartRequestedAt().AsTime()).To(
+				BeTemporally("~", restartTime.AsTime()),
+			)
+
+			// Verify explicit fields were preserved:
+			Expect(object.GetSpec().GetTemplate()).To(Equal("general.small"))
+			Expect(object.GetSpec().GetCores()).To(BeNumerically("==", 4))
+			Expect(object.GetSpec().GetMemoryGib()).To(BeNumerically("==", 8))
+			Expect(object.GetSpec().GetRunStrategy()).To(Equal("Always"))
+			Expect(object.GetSpec().GetImage().GetSourceRef()).To(Equal("quay.io/test:latest"))
+			Expect(object.GetSpec().GetBootDisk().GetSizeGib()).To(BeNumerically("==", 20))
+
+			// Verify they survive a round-trip through the database:
+			getResponse, err := server.Get(ctx, publicv1.ComputeInstancesGetRequest_builder{
+				Id: id,
+			}.Build())
+			Expect(err).ToNot(HaveOccurred())
+			fetched := getResponse.GetObject()
+			Expect(fetched.GetSpec().GetCores()).To(BeNumerically("==", 4))
+			Expect(fetched.GetSpec().GetMemoryGib()).To(BeNumerically("==", 8))
+			Expect(fetched.GetSpec().GetRunStrategy()).To(Equal("Always"))
+			Expect(fetched.GetSpec().GetImage().GetSourceRef()).To(Equal("quay.io/test:latest"))
+			Expect(fetched.GetSpec().GetBootDisk().GetSizeGib()).To(BeNumerically("==", 20))
+			Expect(fetched.GetSpec().GetRestartRequestedAt()).ToNot(BeNil())
 		})
 
 		It("Deletes object", func() {
diff --git a/internal/servers/private_compute_instances_server.go b/internal/servers/private_compute_instances_server.go
index 1a23bf86..b8a825df 100644
--- a/internal/servers/private_compute_instances_server.go
+++ b/internal/servers/private_compute_instances_server.go
@@ -17,9 +17,11 @@ import (
 	"context"
 	"errors"
 	"log/slog"
+	"strings"
 
 	grpccodes "google.golang.org/grpc/codes"
 	grpcstatus "google.golang.org/grpc/status"
+	"google.golang.org/protobuf/types/known/fieldmaskpb"
 
 	privatev1 "github.com/osac-project/fulfillment-service/internal/api/osac/private/v1"
 	"github.com/osac-project/fulfillment-service/internal/auth"
@@ -171,16 +173,20 @@ func (s *PrivateComputeInstancesServer) Create(ctx context.Context,
 
 func (s *PrivateComputeInstancesServer) Update(ctx context.Context,
 	request *privatev1.ComputeInstancesUpdateRequest) (response *privatev1.ComputeInstancesUpdateResponse, err error) {
-	// Validate network references:
-	err = s.validateNetworkReferences(ctx, request.GetObject())
-	if err != nil {
-		return
+	// Only validate fields affected by the update mask. With a field mask the object
+	// is sparse so validating fields absent from it would fail incorrectly.
+	mask := request.GetUpdateMask()
+	if hasMaskPrefix(mask, "spec.subnet", "spec.security_groups") {
+		err = s.validateNetworkReferences(ctx, request.GetObject())
+		if err != nil {
+			return
+		}
 	}
-
-	// Validate template:
-	err = s.validateTemplate(ctx, request.GetObject())
-	if err != nil {
-		return
+	if hasMaskPrefix(mask, "spec.template", "spec.template_parameters") {
+		err = s.validateTemplate(ctx, request.GetObject())
+		if err != nil {
+			return
+		}
 	}
 
 	err = s.generic.Update(ctx, request, &response)
@@ -258,6 +264,20 @@ func (s *PrivateComputeInstancesServer) validateTemplate(ctx context.Context, vm
 	return nil
 }
 
+func hasMaskPrefix(mask *fieldmaskpb.FieldMask, prefixes ...string) bool {
+	if mask == nil || len(mask.GetPaths()) == 0 {
+		return true
+	}
+	for _, path := range mask.GetPaths() {
+		for _, prefix := range prefixes {
+			if path == prefix || strings.HasPrefix(path, prefix+".") {
+				return true
+			}
+		}
+	}
+	return false
+}
+
 // validateNetworkReferences validates that referenced Subnet and SecurityGroups exist, are in READY state,
 // belong to the same tenant, and SecurityGroups belong to the same VirtualNetwork as the Subnet.
 //
```
