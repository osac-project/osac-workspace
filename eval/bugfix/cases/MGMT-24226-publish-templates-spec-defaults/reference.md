# Real Fix: osac-installer PR #85

## Title
MGMT-24226: Pin AAP runtime refs to submodule commit in CI overlays

## Summary
https://redhat.atlassian.net/browse/MGMT-24194

CI overlays (`vmaas-ci`, `caas-ci`) used `AAP_EE_IMAGE=:latest` and
`AAP_PROJECT_GIT_BRANCH=main`, causing AAP to pull whatever is on
osac-aap `main` at runtime — regardless of the submodule pin in
`base/kustomization.yaml`.

This means a breaking change merged to osac-aap would silently break
all osac-installer e2e tests without any submodule bump, and the
failure would surface on an unrelated PR that happens to trigger e2e.

This is exactly what happened today: osac-aap [MGMT-23769](https://redhat.atlassian.net/browse/MGMT-23769) (compute
instance template restructure) landed on `main` on Apr 28-29, and
PR #84 (DNS docs, completely unrelated) caught the `publish-templates`
timeout failure on Apr 30.

Changes:
- Pin `AAP_EE_IMAGE` to `sha-<submodule-commit>` in CI overlays
- Pin `AAP_PROJECT_GIT_BRANCH` to the full submodule commit SHA
- Extend `sync-image-tags.sh` to validate these, so bumping the
  submodule without updating the overlay is caught by the existing
  `check-image-tags` CI workflow
- Dev overlays (`development`, `hypershift2`) are intentionally left
  on `latest`/`main`

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

* **Chores**
  * Pinned CI infrastructure image references to specific versions instead of using latest tags.
  * Updated CI configuration to use specific commit identifiers.
  * Enhanced synchronization tooling to validate and maintain version consistency across CI overlays.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->

## Diff
```diff
diff --git a/overlays/caas-ci/kustomization.yaml b/overlays/caas-ci/kustomization.yaml
index 27d4eb4..1211059 100644
--- a/overlays/caas-ci/kustomization.yaml
+++ b/overlays/caas-ci/kustomization.yaml
@@ -42,9 +42,9 @@ secretGenerator:
   options:
     disableNameSuffixHash: true
   literals:
-    - AAP_EE_IMAGE=ghcr.io/osac-project/osac-aap:latest
+    - AAP_EE_IMAGE=ghcr.io/osac-project/osac-aap:sha-ffe8959
     - AAP_PROJECT_GIT_URI=https://github.com/osac-project/osac-aap
-    - AAP_PROJECT_GIT_BRANCH=main
+    - AAP_PROJECT_GIT_BRANCH=ffe89599749830427c5c3b765071b7355a0f14f3
 
 - name: cluster-fulfillment-ig
   options:
diff --git a/overlays/vmaas-ci/kustomization.yaml b/overlays/vmaas-ci/kustomization.yaml
index e574072..eec80bb 100644
--- a/overlays/vmaas-ci/kustomization.yaml
+++ b/overlays/vmaas-ci/kustomization.yaml
@@ -42,9 +42,9 @@ secretGenerator:
   options:
     disableNameSuffixHash: true
   literals:
-    - AAP_EE_IMAGE=ghcr.io/osac-project/osac-aap:latest
+    - AAP_EE_IMAGE=ghcr.io/osac-project/osac-aap:sha-ffe8959
     - AAP_PROJECT_GIT_URI=https://github.com/osac-project/osac-aap
-    - AAP_PROJECT_GIT_BRANCH=main
+    - AAP_PROJECT_GIT_BRANCH=ffe89599749830427c5c3b765071b7355a0f14f3
 
 - name: cluster-fulfillment-ig
   options:
diff --git a/scripts/sync-image-tags.sh b/scripts/sync-image-tags.sh
index 1d19a0b..1077a43 100755
--- a/scripts/sync-image-tags.sh
+++ b/scripts/sync-image-tags.sh
@@ -37,6 +37,36 @@ for submodule in osac-operator osac-fulfillment-service osac-aap; do
   fi
 done
 
+aap_commit=$(git -C "${REPO_ROOT}" submodule status "base/osac-aap" | awk '{print $1}' | tr -d '+')
+aap_short="${aap_commit:0:7}"
+aap_tag="sha-${aap_short}"
+
+CI_OVERLAYS=("vmaas-ci" "caas-ci")
+
+for overlay in "${CI_OVERLAYS[@]}"; do
+  overlay_file="${REPO_ROOT}/overlays/${overlay}/kustomization.yaml"
+  [[ ! -f "${overlay_file}" ]] && continue
+
+  current_ee=$(grep "AAP_EE_IMAGE=" "${overlay_file}" | sed 's/.*AAP_EE_IMAGE=//' | tr -d ' ')
+  expected_ee="ghcr.io/osac-project/osac-aap:${aap_tag}"
+
+  current_branch=$(grep "AAP_PROJECT_GIT_BRANCH=" "${overlay_file}" | sed 's/.*AAP_PROJECT_GIT_BRANCH=//' | tr -d ' ')
+  expected_branch="${aap_commit}"
+
+  for pair in "AAP_EE_IMAGE ${current_ee} ${expected_ee}" "AAP_PROJECT_GIT_BRANCH ${current_branch} ${expected_branch}"; do
+    read -r key current expected <<< "${pair}"
+    if [[ "${current}" == "${expected}" ]]; then
+      echo "${overlay} ${key}: OK"
+    elif [[ "${1:-}" == "--fix" ]]; then
+      sed -i "s|${key}=${current}|${key}=${expected}|" "${overlay_file}"
+      echo "${overlay} ${key}: FIXED ${current} -> ${expected}"
+    else
+      echo "${overlay} ${key}: MISMATCH current=${current} expected=${expected}"
+      errors=$((errors + 1))
+    fi
+  done
+done
+
 if [[ ${errors} -gt 0 ]]; then
   echo ""
   echo "Run '$0 --fix' to update the tags automatically."
```

---

# Additional Fix: fulfillment-service PR #414

## Title
MGMT-23769: Provide up front validation and handling of template prov…

## Diff
```diff
diff --git a/internal/api/osac/private/v1/compute_instance_template_type.pb.go b/internal/api/osac/private/v1/compute_instance_template_type.pb.go
index 8b30eef8..5860e863 100644
--- a/internal/api/osac/private/v1/compute_instance_template_type.pb.go
+++ b/internal/api/osac/private/v1/compute_instance_template_type.pb.go
@@ -39,11 +39,16 @@ const (
 type ComputeInstanceTemplate struct {
 	state protoimpl.MessageState `protogen:"hybrid.v1"`
 	// Public data.
-	Id            string                                        `protobuf:"bytes,1,opt,name=id,proto3" json:"id,omitempty"`
-	Metadata      *Metadata                                     `protobuf:"bytes,2,opt,name=metadata,proto3" json:"metadata,omitempty"`
-	Title         string                                        `protobuf:"bytes,3,opt,name=title,proto3" json:"title,omitempty"`
-	Description   string                                        `protobuf:"bytes,4,opt,name=description,proto3" json:"description,omitempty"`
-	Parameters    []*ComputeInstanceTemplateParameterDefinition `protobuf:"bytes,5,rep,name=parameters,proto3" json:"parameters,omitempty"`
+	Id          string                                        `protobuf:"bytes,1,opt,name=id,proto3" json:"id,omitempty"`
+	Metadata    *Metadata                                     `protobuf:"bytes,2,opt,name=metadata,proto3" json:"metadata,omitempty"`
+	Title       string                                        `protobuf:"bytes,3,opt,name=title,proto3" json:"title,omitempty"`
+	Description string                                        `protobuf:"bytes,4,opt,name=description,proto3" json:"description,omitempty"`
+	Parameters  []*ComputeInstanceTemplateParameterDefinition `protobuf:"bytes,5,rep,name=parameters,proto3" json:"parameters,omitempty"`
+	// Default values for compute instance spec fields. When a user creates a
+	// compute instance without setting these fields, these values are applied.
+	//
+	// User-provided spec field values always override these defaults.
+	SpecDefaults  *ComputeInstanceTemplateSpecDefaults `protobuf:"bytes,6,opt,name=spec_defaults,json=specDefaults,proto3" json:"spec_defaults,omitempty"`
 	unknownFields protoimpl.UnknownFields
 	sizeCache     protoimpl.SizeCache
 }
@@ -108,6 +113,13 @@ func (x *ComputeInstanceTemplate) GetParameters() []*ComputeInstanceTemplatePara
 	return nil
 }
 
+func (x *ComputeInstanceTemplate) GetSpecDefaults() *ComputeInstanceTemplateSpecDefaults {
+	if x != nil {
+		return x.SpecDefaults
+	}
+	return nil
+}
+
 func (x *ComputeInstanceTemplate) SetId(v string) {
 	x.Id = v
 }
@@ -128,6 +140,10 @@ func (x *ComputeInstanceTemplate) SetParameters(v []*ComputeInstanceTemplatePara
 	x.Parameters = v
 }
 
+func (x *ComputeInstanceTemplate) SetSpecDefaults(v *ComputeInstanceTemplateSpecDefaults) {
+	x.SpecDefaults = v
+}
+
 func (x *ComputeInstanceTemplate) HasMetadata() bool {
 	if x == nil {
 		return false
@@ -135,10 +151,21 @@ func (x *ComputeInstanceTemplate) HasMetadata() bool {
 	return x.Metadata != nil
 }
 
+func (x *ComputeInstanceTemplate) HasSpecDefaults() bool {
+	if x == nil {
+		return false
+	}
+	return x.SpecDefaults != nil
+}
+
 func (x *ComputeInstanceTemplate) ClearMetadata() {
 	x.Metadata = nil
 }
 
+func (x *ComputeInstanceTemplate) ClearSpecDefaults() {
+	x.SpecDefaults = nil
+}
+
 type ComputeInstanceTemplate_builder struct {
 	_ [0]func() // Prevents comparability and use of unkeyed literals for the builder.
 
@@ -148,6 +175,11 @@ type ComputeInstanceTemplate_builder struct {
 	Title       string
 	Description string
 	Parameters  []*ComputeInstanceTemplateParameterDefinition
+	// Default values for compute instance spec fields. When a user creates a
+	// compute instance without setting these fields, these values are applied.
+	//
+	// User-provided spec field values always override these defaults.
+	SpecDefaults *ComputeInstanceTemplateSpecDefaults
 }
 
 func (b0 ComputeInstanceTemplate_builder) Build() *ComputeInstanceTemplate {
@@ -159,6 +191,7 @@ func (b0 ComputeInstanceTemplate_builder) Build() *ComputeInstanceTemplate {
 	x.Title = b.Title
 	x.Description = b.Description
 	x.Parameters = b.Parameters
+	x.SpecDefaults = b.SpecDefaults
 	return m0
 }
 
@@ -300,6 +333,185 @@ func (b0 ComputeInstanceTemplateParameterDefinition_builder) Build() *ComputeIns
 	return m0
 }
 
+// Default values for compute instance spec fields.
+type ComputeInstanceTemplateSpecDefaults struct {
+	state protoimpl.MessageState `protogen:"hybrid.v1"`
+	// Default number of CPU cores.
+	Cores *int32 `protobuf:"varint,1,opt,name=cores,proto3,oneof" json:"cores,omitempty"`
+	// Default memory size in GiB.
+	MemoryGib *int32 `protobuf:"varint,2,opt,name=memory_gib,json=memoryGib,proto3,oneof" json:"memory_gib,omitempty"`
+	// Default image configuration.
+	Image *ComputeInstanceImage `protobuf:"bytes,3,opt,name=image,proto3,oneof" json:"image,omitempty"`
+	// Default boot disk configuration.
+	BootDisk *ComputeInstanceDisk `protobuf:"bytes,4,opt,name=boot_disk,json=bootDisk,proto3,oneof" json:"boot_disk,omitempty"`
+	// Default run strategy.
+	RunStrategy   *string `protobuf:"bytes,5,opt,name=run_strategy,json=runStrategy,proto3,oneof" json:"run_strategy,omitempty"`
+	unknownFields protoimpl.UnknownFields
+	sizeCache     protoimpl.SizeCache
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) Reset() {
+	*x = ComputeInstanceTemplateSpecDefaults{}
+	mi := &file_osac_private_v1_compute_instance_template_type_proto_msgTypes[2]
+	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
+	ms.StoreMessageInfo(mi)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) String() string {
+	return protoimpl.X.MessageStringOf(x)
+}
+
+func (*ComputeInstanceTemplateSpecDefaults) ProtoMessage() {}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ProtoReflect() protoreflect.Message {
+	mi := &file_osac_private_v1_compute_instance_template_type_proto_msgTypes[2]
+	if x != nil {
+		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
+		if ms.LoadMessageInfo() == nil {
+			ms.StoreMessageInfo(mi)
+		}
+		return ms
+	}
+	return mi.MessageOf(x)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetCores() int32 {
+	if x != nil && x.Cores != nil {
+		return *x.Cores
+	}
+	return 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetMemoryGib() int32 {
+	if x != nil && x.MemoryGib != nil {
+		return *x.MemoryGib
+	}
+	return 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetImage() *ComputeInstanceImage {
+	if x != nil {
+		return x.Image
+	}
+	return nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetBootDisk() *ComputeInstanceDisk {
+	if x != nil {
+		return x.BootDisk
+	}
+	return nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetRunStrategy() string {
+	if x != nil && x.RunStrategy != nil {
+		return *x.RunStrategy
+	}
+	return ""
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetCores(v int32) {
+	x.Cores = &v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetMemoryGib(v int32) {
+	x.MemoryGib = &v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetImage(v *ComputeInstanceImage) {
+	x.Image = v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetBootDisk(v *ComputeInstanceDisk) {
+	x.BootDisk = v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetRunStrategy(v string) {
+	x.RunStrategy = &v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasCores() bool {
+	if x == nil {
+		return false
+	}
+	return x.Cores != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasMemoryGib() bool {
+	if x == nil {
+		return false
+	}
+	return x.MemoryGib != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasImage() bool {
+	if x == nil {
+		return false
+	}
+	return x.Image != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasBootDisk() bool {
+	if x == nil {
+		return false
+	}
+	return x.BootDisk != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasRunStrategy() bool {
+	if x == nil {
+		return false
+	}
+	return x.RunStrategy != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearCores() {
+	x.Cores = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearMemoryGib() {
+	x.MemoryGib = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearImage() {
+	x.Image = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearBootDisk() {
+	x.BootDisk = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearRunStrategy() {
+	x.RunStrategy = nil
+}
+
+type ComputeInstanceTemplateSpecDefaults_builder struct {
+	_ [0]func() // Prevents comparability and use of unkeyed literals for the builder.
+
+	// Default number of CPU cores.
+	Cores *int32
+	// Default memory size in GiB.
+	MemoryGib *int32
+	// Default image configuration.
+	Image *ComputeInstanceImage
+	// Default boot disk configuration.
+	BootDisk *ComputeInstanceDisk
+	// Default run strategy.
+	RunStrategy *string
+}
+
+func (b0 ComputeInstanceTemplateSpecDefaults_builder) Build() *ComputeInstanceTemplateSpecDefaults {
+	m0 := &ComputeInstanceTemplateSpecDefaults{}
+	b, x := &b0, m0
+	_, _ = b, x
+	x.Cores = b.Cores
+	x.MemoryGib = b.MemoryGib
+	x.Image = b.Image
+	x.BootDisk = b.BootDisk
+	x.RunStrategy = b.RunStrategy
+	return m0
+}
+
 var File_osac_private_v1_compute_instance_template_type_proto protoreflect.FileDescriptor
 
 var file_osac_private_v1_compute_instance_template_type_proto_rawDesc = string([]byte{
@@ -309,71 +521,108 @@ var file_osac_private_v1_compute_instance_template_type_proto_rawDesc = string([
 	0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x12, 0x0f, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69,
 	0x76, 0x61, 0x74, 0x65, 0x2e, 0x76, 0x31, 0x1a, 0x19, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x2f,
 	0x70, 0x72, 0x6f, 0x74, 0x6f, 0x62, 0x75, 0x66, 0x2f, 0x61, 0x6e, 0x79, 0x2e, 0x70, 0x72, 0x6f,
-	0x74, 0x6f, 0x1a, 0x23, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65,
-	0x2f, 0x76, 0x31, 0x2f, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x5f, 0x74, 0x79, 0x70,
-	0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x22, 0xf5, 0x01, 0x0a, 0x17, 0x43, 0x6f, 0x6d, 0x70,
+	0x74, 0x6f, 0x1a, 0x2b, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65,
+	0x2f, 0x76, 0x31, 0x2f, 0x63, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x5f, 0x69, 0x6e, 0x73, 0x74,
+	0x61, 0x6e, 0x63, 0x65, 0x5f, 0x74, 0x79, 0x70, 0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x1a,
+	0x23, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2f, 0x76, 0x31,
+	0x2f, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x5f, 0x74, 0x79, 0x70, 0x65, 0x2e, 0x70,
+	0x72, 0x6f, 0x74, 0x6f, 0x22, 0xd0, 0x02, 0x0a, 0x17, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65,
+	0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65,
+	0x12, 0x0e, 0x0a, 0x02, 0x69, 0x64, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x02, 0x69, 0x64,
+	0x12, 0x35, 0x0a, 0x08, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x18, 0x02, 0x20, 0x01,
+	0x28, 0x0b, 0x32, 0x19, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74,
+	0x65, 0x2e, 0x76, 0x31, 0x2e, 0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x52, 0x08, 0x6d,
+	0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65,
+	0x18, 0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a,
+	0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x04, 0x20, 0x01,
+	0x28, 0x09, 0x52, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12,
+	0x5b, 0x0a, 0x0a, 0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x18, 0x05, 0x20,
+	0x03, 0x28, 0x0b, 0x32, 0x3b, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61,
+	0x74, 0x65, 0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73,
+	0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72,
+	0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e,
+	0x52, 0x0a, 0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x12, 0x59, 0x0a, 0x0d,
+	0x73, 0x70, 0x65, 0x63, 0x5f, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73, 0x18, 0x06, 0x20,
+	0x01, 0x28, 0x0b, 0x32, 0x34, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61,
+	0x74, 0x65, 0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73,
+	0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x53, 0x70, 0x65,
+	0x63, 0x44, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73, 0x52, 0x0c, 0x73, 0x70, 0x65, 0x63, 0x44,
+	0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73, 0x22, 0xd8, 0x01, 0x0a, 0x2a, 0x43, 0x6f, 0x6d, 0x70,
 	0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c,
-	0x61, 0x74, 0x65, 0x12, 0x0e, 0x0a, 0x02, 0x69, 0x64, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52,
-	0x02, 0x69, 0x64, 0x12, 0x35, 0x0a, 0x08, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x18,
-	0x02, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x19, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69,
-	0x76, 0x61, 0x74, 0x65, 0x2e, 0x76, 0x31, 0x2e, 0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61,
-	0x52, 0x08, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69,
-	0x74, 0x6c, 0x65, 0x18, 0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65,
+	0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69,
+	0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x12, 0x0a, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x18, 0x01,
+	0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69,
+	0x74, 0x6c, 0x65, 0x18, 0x02, 0x20, 0x01, 0x28, 0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65,
 	0x12, 0x20, 0x0a, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18,
-	0x04, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69,
-	0x6f, 0x6e, 0x12, 0x5b, 0x0a, 0x0a, 0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73,
-	0x18, 0x05, 0x20, 0x03, 0x28, 0x0b, 0x32, 0x3b, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72,
-	0x69, 0x76, 0x61, 0x74, 0x65, 0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65,
-	0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65,
-	0x50, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74,
-	0x69, 0x6f, 0x6e, 0x52, 0x0a, 0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x22,
-	0xd8, 0x01, 0x0a, 0x2a, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61,
-	0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61, 0x6d,
-	0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x12,
-	0x0a, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x6e, 0x61,
-	0x6d, 0x65, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x18, 0x02, 0x20, 0x01, 0x28,
-	0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a, 0x0b, 0x64, 0x65, 0x73, 0x63,
-	0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b, 0x64,
-	0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x1a, 0x0a, 0x08, 0x72, 0x65,
-	0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x18, 0x04, 0x20, 0x01, 0x28, 0x08, 0x52, 0x08, 0x72, 0x65,
-	0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x12, 0x12, 0x0a, 0x04, 0x74, 0x79, 0x70, 0x65, 0x18, 0x05,
-	0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x74, 0x79, 0x70, 0x65, 0x12, 0x2e, 0x0a, 0x07, 0x64, 0x65,
-	0x66, 0x61, 0x75, 0x6c, 0x74, 0x18, 0x06, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x14, 0x2e, 0x67, 0x6f,
-	0x6f, 0x67, 0x6c, 0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x62, 0x75, 0x66, 0x2e, 0x41, 0x6e,
-	0x79, 0x52, 0x07, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x42, 0xeb, 0x01, 0x0a, 0x13, 0x63,
-	0x6f, 0x6d, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2e,
-	0x76, 0x31, 0x42, 0x20, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61,
-	0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x54, 0x79, 0x70, 0x65, 0x50,
-	0x72, 0x6f, 0x74, 0x6f, 0x50, 0x01, 0x5a, 0x52, 0x67, 0x69, 0x74, 0x68, 0x75, 0x62, 0x2e, 0x63,
-	0x6f, 0x6d, 0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2d, 0x70, 0x72, 0x6f, 0x6a, 0x65, 0x63, 0x74, 0x2f,
-	0x66, 0x75, 0x6c, 0x66, 0x69, 0x6c, 0x6c, 0x6d, 0x65, 0x6e, 0x74, 0x2d, 0x73, 0x65, 0x72, 0x76,
-	0x69, 0x63, 0x65, 0x2f, 0x69, 0x6e, 0x74, 0x65, 0x72, 0x6e, 0x61, 0x6c, 0x2f, 0x61, 0x70, 0x69,
-	0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2f, 0x76, 0x31,
-	0x3b, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x76, 0x31, 0xa2, 0x02, 0x03, 0x4f, 0x50, 0x58,
-	0xaa, 0x02, 0x0f, 0x4f, 0x73, 0x61, 0x63, 0x2e, 0x50, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2e,
-	0x56, 0x31, 0xca, 0x02, 0x10, 0x4f, 0x73, 0x61, 0x63, 0x5c, 0x50, 0x72, 0x69, 0x76, 0x61, 0x74,
-	0x65, 0x5f, 0x5c, 0x56, 0x31, 0xe2, 0x02, 0x1c, 0x4f, 0x73, 0x61, 0x63, 0x5c, 0x50, 0x72, 0x69,
-	0x76, 0x61, 0x74, 0x65, 0x5f, 0x5c, 0x56, 0x31, 0x5c, 0x47, 0x50, 0x42, 0x4d, 0x65, 0x74, 0x61,
-	0x64, 0x61, 0x74, 0x61, 0xea, 0x02, 0x11, 0x4f, 0x73, 0x61, 0x63, 0x3a, 0x3a, 0x50, 0x72, 0x69,
-	0x76, 0x61, 0x74, 0x65, 0x3a, 0x3a, 0x56, 0x31, 0x62, 0x06, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x33,
+	0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69,
+	0x6f, 0x6e, 0x12, 0x1a, 0x0a, 0x08, 0x72, 0x65, 0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x18, 0x04,
+	0x20, 0x01, 0x28, 0x08, 0x52, 0x08, 0x72, 0x65, 0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x12, 0x12,
+	0x0a, 0x04, 0x74, 0x79, 0x70, 0x65, 0x18, 0x05, 0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x74, 0x79,
+	0x70, 0x65, 0x12, 0x2e, 0x0a, 0x07, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x18, 0x06, 0x20,
+	0x01, 0x28, 0x0b, 0x32, 0x14, 0x2e, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x2e, 0x70, 0x72, 0x6f,
+	0x74, 0x6f, 0x62, 0x75, 0x66, 0x2e, 0x41, 0x6e, 0x79, 0x52, 0x07, 0x64, 0x65, 0x66, 0x61, 0x75,
+	0x6c, 0x74, 0x22, 0xd8, 0x02, 0x0a, 0x23, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e,
+	0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x53, 0x70,
+	0x65, 0x63, 0x44, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73, 0x12, 0x19, 0x0a, 0x05, 0x63, 0x6f,
+	0x72, 0x65, 0x73, 0x18, 0x01, 0x20, 0x01, 0x28, 0x05, 0x48, 0x00, 0x52, 0x05, 0x63, 0x6f, 0x72,
+	0x65, 0x73, 0x88, 0x01, 0x01, 0x12, 0x22, 0x0a, 0x0a, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x5f,
+	0x67, 0x69, 0x62, 0x18, 0x02, 0x20, 0x01, 0x28, 0x05, 0x48, 0x01, 0x52, 0x09, 0x6d, 0x65, 0x6d,
+	0x6f, 0x72, 0x79, 0x47, 0x69, 0x62, 0x88, 0x01, 0x01, 0x12, 0x40, 0x0a, 0x05, 0x69, 0x6d, 0x61,
+	0x67, 0x65, 0x18, 0x03, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x25, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e,
+	0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75,
+	0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x49, 0x6d, 0x61, 0x67, 0x65, 0x48,
+	0x02, 0x52, 0x05, 0x69, 0x6d, 0x61, 0x67, 0x65, 0x88, 0x01, 0x01, 0x12, 0x46, 0x0a, 0x09, 0x62,
+	0x6f, 0x6f, 0x74, 0x5f, 0x64, 0x69, 0x73, 0x6b, 0x18, 0x04, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x24,
+	0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2e, 0x76, 0x31,
+	0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65,
+	0x44, 0x69, 0x73, 0x6b, 0x48, 0x03, 0x52, 0x08, 0x62, 0x6f, 0x6f, 0x74, 0x44, 0x69, 0x73, 0x6b,
+	0x88, 0x01, 0x01, 0x12, 0x26, 0x0a, 0x0c, 0x72, 0x75, 0x6e, 0x5f, 0x73, 0x74, 0x72, 0x61, 0x74,
+	0x65, 0x67, 0x79, 0x18, 0x05, 0x20, 0x01, 0x28, 0x09, 0x48, 0x04, 0x52, 0x0b, 0x72, 0x75, 0x6e,
+	0x53, 0x74, 0x72, 0x61, 0x74, 0x65, 0x67, 0x79, 0x88, 0x01, 0x01, 0x42, 0x08, 0x0a, 0x06, 0x5f,
+	0x63, 0x6f, 0x72, 0x65, 0x73, 0x42, 0x0d, 0x0a, 0x0b, 0x5f, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79,
+	0x5f, 0x67, 0x69, 0x62, 0x42, 0x08, 0x0a, 0x06, 0x5f, 0x69, 0x6d, 0x61, 0x67, 0x65, 0x42, 0x0c,
+	0x0a, 0x0a, 0x5f, 0x62, 0x6f, 0x6f, 0x74, 0x5f, 0x64, 0x69, 0x73, 0x6b, 0x42, 0x0f, 0x0a, 0x0d,
+	0x5f, 0x72, 0x75, 0x6e, 0x5f, 0x73, 0x74, 0x72, 0x61, 0x74, 0x65, 0x67, 0x79, 0x42, 0xeb, 0x01,
+	0x0a, 0x13, 0x63, 0x6f, 0x6d, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61,
+	0x74, 0x65, 0x2e, 0x76, 0x31, 0x42, 0x20, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e,
+	0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x54, 0x79,
+	0x70, 0x65, 0x50, 0x72, 0x6f, 0x74, 0x6f, 0x50, 0x01, 0x5a, 0x52, 0x67, 0x69, 0x74, 0x68, 0x75,
+	0x62, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2d, 0x70, 0x72, 0x6f, 0x6a, 0x65,
+	0x63, 0x74, 0x2f, 0x66, 0x75, 0x6c, 0x66, 0x69, 0x6c, 0x6c, 0x6d, 0x65, 0x6e, 0x74, 0x2d, 0x73,
+	0x65, 0x72, 0x76, 0x69, 0x63, 0x65, 0x2f, 0x69, 0x6e, 0x74, 0x65, 0x72, 0x6e, 0x61, 0x6c, 0x2f,
+	0x61, 0x70, 0x69, 0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65,
+	0x2f, 0x76, 0x31, 0x3b, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x76, 0x31, 0xa2, 0x02, 0x03,
+	0x4f, 0x50, 0x58, 0xaa, 0x02, 0x0f, 0x4f, 0x73, 0x61, 0x63, 0x2e, 0x50, 0x72, 0x69, 0x76, 0x61,
+	0x74, 0x65, 0x2e, 0x56, 0x31, 0xca, 0x02, 0x10, 0x4f, 0x73, 0x61, 0x63, 0x5c, 0x50, 0x72, 0x69,
+	0x76, 0x61, 0x74, 0x65, 0x5f, 0x5c, 0x56, 0x31, 0xe2, 0x02, 0x1c, 0x4f, 0x73, 0x61, 0x63, 0x5c,
+	0x50, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x5f, 0x5c, 0x56, 0x31, 0x5c, 0x47, 0x50, 0x42, 0x4d,
+	0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0xea, 0x02, 0x11, 0x4f, 0x73, 0x61, 0x63, 0x3a, 0x3a,
+	0x50, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x3a, 0x3a, 0x56, 0x31, 0x62, 0x06, 0x70, 0x72, 0x6f,
+	0x74, 0x6f, 0x33,
 })
 
-var file_osac_private_v1_compute_instance_template_type_proto_msgTypes = make([]protoimpl.MessageInfo, 2)
+var file_osac_private_v1_compute_instance_template_type_proto_msgTypes = make([]protoimpl.MessageInfo, 3)
 var file_osac_private_v1_compute_instance_template_type_proto_goTypes = []any{
 	(*ComputeInstanceTemplate)(nil),                    // 0: osac.private.v1.ComputeInstanceTemplate
 	(*ComputeInstanceTemplateParameterDefinition)(nil), // 1: osac.private.v1.ComputeInstanceTemplateParameterDefinition
-	(*Metadata)(nil),                                   // 2: osac.private.v1.Metadata
-	(*anypb.Any)(nil),                                  // 3: google.protobuf.Any
+	(*ComputeInstanceTemplateSpecDefaults)(nil),        // 2: osac.private.v1.ComputeInstanceTemplateSpecDefaults
+	(*Metadata)(nil),             // 3: osac.private.v1.Metadata
+	(*anypb.Any)(nil),            // 4: google.protobuf.Any
+	(*ComputeInstanceImage)(nil), // 5: osac.private.v1.ComputeInstanceImage
+	(*ComputeInstanceDisk)(nil),  // 6: osac.private.v1.ComputeInstanceDisk
 }
 var file_osac_private_v1_compute_instance_template_type_proto_depIdxs = []int32{
-	2, // 0: osac.private.v1.ComputeInstanceTemplate.metadata:type_name -> osac.private.v1.Metadata
+	3, // 0: osac.private.v1.ComputeInstanceTemplate.metadata:type_name -> osac.private.v1.Metadata
 	1, // 1: osac.private.v1.ComputeInstanceTemplate.parameters:type_name -> osac.private.v1.ComputeInstanceTemplateParameterDefinition
-	3, // 2: osac.private.v1.ComputeInstanceTemplateParameterDefinition.default:type_name -> google.protobuf.Any
-	3, // [3:3] is the sub-list for method output_type
-	3, // [3:3] is the sub-list for method input_type
-	3, // [3:3] is the sub-list for extension type_name
-	3, // [3:3] is the sub-list for extension extendee
-	0, // [0:3] is the sub-list for field type_name
+	2, // 2: osac.private.v1.ComputeInstanceTemplate.spec_defaults:type_name -> osac.private.v1.ComputeInstanceTemplateSpecDefaults
+	4, // 3: osac.private.v1.ComputeInstanceTemplateParameterDefinition.default:type_name -> google.protobuf.Any
+	5, // 4: osac.private.v1.ComputeInstanceTemplateSpecDefaults.image:type_name -> osac.private.v1.ComputeInstanceImage
+	6, // 5: osac.private.v1.ComputeInstanceTemplateSpecDefaults.boot_disk:type_name -> osac.private.v1.ComputeInstanceDisk
+	6, // [6:6] is the sub-list for method output_type
+	6, // [6:6] is the sub-list for method input_type
+	6, // [6:6] is the sub-list for extension type_name
+	6, // [6:6] is the sub-list for extension extendee
+	0, // [0:6] is the sub-list for field type_name
 }
 
 func init() { file_osac_private_v1_compute_instance_template_type_proto_init() }
@@ -381,14 +630,16 @@ func file_osac_private_v1_compute_instance_template_type_proto_init() {
 	if File_osac_private_v1_compute_instance_template_type_proto != nil {
 		return
 	}
+	file_osac_private_v1_compute_instance_type_proto_init()
 	file_osac_private_v1_metadata_type_proto_init()
+	file_osac_private_v1_compute_instance_template_type_proto_msgTypes[2].OneofWrappers = []any{}
 	type x struct{}
 	out := protoimpl.TypeBuilder{
 		File: protoimpl.DescBuilder{
 			GoPackagePath: reflect.TypeOf(x{}).PkgPath(),
 			RawDescriptor: unsafe.Slice(unsafe.StringData(file_osac_private_v1_compute_instance_template_type_proto_rawDesc), len(file_osac_private_v1_compute_instance_template_type_proto_rawDesc)),
 			NumEnums:      0,
-			NumMessages:   2,
+			NumMessages:   3,
 			NumExtensions: 0,
 			NumServices:   0,
 		},
diff --git a/internal/api/osac/private/v1/compute_instance_template_type_protoopaque.pb.go b/internal/api/osac/private/v1/compute_instance_template_type_protoopaque.pb.go
index 6bf9b058..666e29ce 100644
--- a/internal/api/osac/private/v1/compute_instance_template_type_protoopaque.pb.go
+++ b/internal/api/osac/private/v1/compute_instance_template_type_protoopaque.pb.go
@@ -37,14 +37,15 @@ const (
 )
 
 type ComputeInstanceTemplate struct {
-	state                  protoimpl.MessageState                         `protogen:"opaque.v1"`
-	xxx_hidden_Id          string                                         `protobuf:"bytes,1,opt,name=id,proto3"`
-	xxx_hidden_Metadata    *Metadata                                      `protobuf:"bytes,2,opt,name=metadata,proto3"`
-	xxx_hidden_Title       string                                         `protobuf:"bytes,3,opt,name=title,proto3"`
-	xxx_hidden_Description string                                         `protobuf:"bytes,4,opt,name=description,proto3"`
-	xxx_hidden_Parameters  *[]*ComputeInstanceTemplateParameterDefinition `protobuf:"bytes,5,rep,name=parameters,proto3"`
-	unknownFields          protoimpl.UnknownFields
-	sizeCache              protoimpl.SizeCache
+	state                   protoimpl.MessageState                         `protogen:"opaque.v1"`
+	xxx_hidden_Id           string                                         `protobuf:"bytes,1,opt,name=id,proto3"`
+	xxx_hidden_Metadata     *Metadata                                      `protobuf:"bytes,2,opt,name=metadata,proto3"`
+	xxx_hidden_Title        string                                         `protobuf:"bytes,3,opt,name=title,proto3"`
+	xxx_hidden_Description  string                                         `protobuf:"bytes,4,opt,name=description,proto3"`
+	xxx_hidden_Parameters   *[]*ComputeInstanceTemplateParameterDefinition `protobuf:"bytes,5,rep,name=parameters,proto3"`
+	xxx_hidden_SpecDefaults *ComputeInstanceTemplateSpecDefaults           `protobuf:"bytes,6,opt,name=spec_defaults,json=specDefaults,proto3"`
+	unknownFields           protoimpl.UnknownFields
+	sizeCache               protoimpl.SizeCache
 }
 
 func (x *ComputeInstanceTemplate) Reset() {
@@ -109,6 +110,13 @@ func (x *ComputeInstanceTemplate) GetParameters() []*ComputeInstanceTemplatePara
 	return nil
 }
 
+func (x *ComputeInstanceTemplate) GetSpecDefaults() *ComputeInstanceTemplateSpecDefaults {
+	if x != nil {
+		return x.xxx_hidden_SpecDefaults
+	}
+	return nil
+}
+
 func (x *ComputeInstanceTemplate) SetId(v string) {
 	x.xxx_hidden_Id = v
 }
@@ -129,6 +137,10 @@ func (x *ComputeInstanceTemplate) SetParameters(v []*ComputeInstanceTemplatePara
 	x.xxx_hidden_Parameters = &v
 }
 
+func (x *ComputeInstanceTemplate) SetSpecDefaults(v *ComputeInstanceTemplateSpecDefaults) {
+	x.xxx_hidden_SpecDefaults = v
+}
+
 func (x *ComputeInstanceTemplate) HasMetadata() bool {
 	if x == nil {
 		return false
@@ -136,10 +148,21 @@ func (x *ComputeInstanceTemplate) HasMetadata() bool {
 	return x.xxx_hidden_Metadata != nil
 }
 
+func (x *ComputeInstanceTemplate) HasSpecDefaults() bool {
+	if x == nil {
+		return false
+	}
+	return x.xxx_hidden_SpecDefaults != nil
+}
+
 func (x *ComputeInstanceTemplate) ClearMetadata() {
 	x.xxx_hidden_Metadata = nil
 }
 
+func (x *ComputeInstanceTemplate) ClearSpecDefaults() {
+	x.xxx_hidden_SpecDefaults = nil
+}
+
 type ComputeInstanceTemplate_builder struct {
 	_ [0]func() // Prevents comparability and use of unkeyed literals for the builder.
 
@@ -149,6 +172,11 @@ type ComputeInstanceTemplate_builder struct {
 	Title       string
 	Description string
 	Parameters  []*ComputeInstanceTemplateParameterDefinition
+	// Default values for compute instance spec fields. When a user creates a
+	// compute instance without setting these fields, these values are applied.
+	//
+	// User-provided spec field values always override these defaults.
+	SpecDefaults *ComputeInstanceTemplateSpecDefaults
 }
 
 func (b0 ComputeInstanceTemplate_builder) Build() *ComputeInstanceTemplate {
@@ -160,6 +188,7 @@ func (b0 ComputeInstanceTemplate_builder) Build() *ComputeInstanceTemplate {
 	x.xxx_hidden_Title = b.Title
 	x.xxx_hidden_Description = b.Description
 	x.xxx_hidden_Parameters = &b.Parameters
+	x.xxx_hidden_SpecDefaults = b.SpecDefaults
 	return m0
 }
 
@@ -301,6 +330,200 @@ func (b0 ComputeInstanceTemplateParameterDefinition_builder) Build() *ComputeIns
 	return m0
 }
 
+// Default values for compute instance spec fields.
+type ComputeInstanceTemplateSpecDefaults struct {
+	state                  protoimpl.MessageState `protogen:"opaque.v1"`
+	xxx_hidden_Cores       int32                  `protobuf:"varint,1,opt,name=cores,proto3,oneof"`
+	xxx_hidden_MemoryGib   int32                  `protobuf:"varint,2,opt,name=memory_gib,json=memoryGib,proto3,oneof"`
+	xxx_hidden_Image       *ComputeInstanceImage  `protobuf:"bytes,3,opt,name=image,proto3,oneof"`
+	xxx_hidden_BootDisk    *ComputeInstanceDisk   `protobuf:"bytes,4,opt,name=boot_disk,json=bootDisk,proto3,oneof"`
+	xxx_hidden_RunStrategy *string                `protobuf:"bytes,5,opt,name=run_strategy,json=runStrategy,proto3,oneof"`
+	XXX_raceDetectHookData protoimpl.RaceDetectHookData
+	XXX_presence           [1]uint32
+	unknownFields          protoimpl.UnknownFields
+	sizeCache              protoimpl.SizeCache
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) Reset() {
+	*x = ComputeInstanceTemplateSpecDefaults{}
+	mi := &file_osac_private_v1_compute_instance_template_type_proto_msgTypes[2]
+	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
+	ms.StoreMessageInfo(mi)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) String() string {
+	return protoimpl.X.MessageStringOf(x)
+}
+
+func (*ComputeInstanceTemplateSpecDefaults) ProtoMessage() {}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ProtoReflect() protoreflect.Message {
+	mi := &file_osac_private_v1_compute_instance_template_type_proto_msgTypes[2]
+	if x != nil {
+		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
+		if ms.LoadMessageInfo() == nil {
+			ms.StoreMessageInfo(mi)
+		}
+		return ms
+	}
+	return mi.MessageOf(x)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetCores() int32 {
+	if x != nil {
+		return x.xxx_hidden_Cores
+	}
+	return 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetMemoryGib() int32 {
+	if x != nil {
+		return x.xxx_hidden_MemoryGib
+	}
+	return 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetImage() *ComputeInstanceImage {
+	if x != nil {
+		return x.xxx_hidden_Image
+	}
+	return nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetBootDisk() *ComputeInstanceDisk {
+	if x != nil {
+		return x.xxx_hidden_BootDisk
+	}
+	return nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetRunStrategy() string {
+	if x != nil {
+		if x.xxx_hidden_RunStrategy != nil {
+			return *x.xxx_hidden_RunStrategy
+		}
+		return ""
+	}
+	return ""
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetCores(v int32) {
+	x.xxx_hidden_Cores = v
+	protoimpl.X.SetPresent(&(x.XXX_presence[0]), 0, 5)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetMemoryGib(v int32) {
+	x.xxx_hidden_MemoryGib = v
+	protoimpl.X.SetPresent(&(x.XXX_presence[0]), 1, 5)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetImage(v *ComputeInstanceImage) {
+	x.xxx_hidden_Image = v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetBootDisk(v *ComputeInstanceDisk) {
+	x.xxx_hidden_BootDisk = v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetRunStrategy(v string) {
+	x.xxx_hidden_RunStrategy = &v
+	protoimpl.X.SetPresent(&(x.XXX_presence[0]), 4, 5)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasCores() bool {
+	if x == nil {
+		return false
+	}
+	return protoimpl.X.Present(&(x.XXX_presence[0]), 0)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasMemoryGib() bool {
+	if x == nil {
+		return false
+	}
+	return protoimpl.X.Present(&(x.XXX_presence[0]), 1)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasImage() bool {
+	if x == nil {
+		return false
+	}
+	return x.xxx_hidden_Image != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasBootDisk() bool {
+	if x == nil {
+		return false
+	}
+	return x.xxx_hidden_BootDisk != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasRunStrategy() bool {
+	if x == nil {
+		return false
+	}
+	return protoimpl.X.Present(&(x.XXX_presence[0]), 4)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearCores() {
+	protoimpl.X.ClearPresent(&(x.XXX_presence[0]), 0)
+	x.xxx_hidden_Cores = 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearMemoryGib() {
+	protoimpl.X.ClearPresent(&(x.XXX_presence[0]), 1)
+	x.xxx_hidden_MemoryGib = 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearImage() {
+	x.xxx_hidden_Image = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearBootDisk() {
+	x.xxx_hidden_BootDisk = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearRunStrategy() {
+	protoimpl.X.ClearPresent(&(x.XXX_presence[0]), 4)
+	x.xxx_hidden_RunStrategy = nil
+}
+
+type ComputeInstanceTemplateSpecDefaults_builder struct {
+	_ [0]func() // Prevents comparability and use of unkeyed literals for the builder.
+
+	// Default number of CPU cores.
+	Cores *int32
+	// Default memory size in GiB.
+	MemoryGib *int32
+	// Default image configuration.
+	Image *ComputeInstanceImage
+	// Default boot disk configuration.
+	BootDisk *ComputeInstanceDisk
+	// Default run strategy.
+	RunStrategy *string
+}
+
+func (b0 ComputeInstanceTemplateSpecDefaults_builder) Build() *ComputeInstanceTemplateSpecDefaults {
+	m0 := &ComputeInstanceTemplateSpecDefaults{}
+	b, x := &b0, m0
+	_, _ = b, x
+	if b.Cores != nil {
+		protoimpl.X.SetPresentNonAtomic(&(x.XXX_presence[0]), 0, 5)
+		x.xxx_hidden_Cores = *b.Cores
+	}
+	if b.MemoryGib != nil {
+		protoimpl.X.SetPresentNonAtomic(&(x.XXX_presence[0]), 1, 5)
+		x.xxx_hidden_MemoryGib = *b.MemoryGib
+	}
+	x.xxx_hidden_Image = b.Image
+	x.xxx_hidden_BootDisk = b.BootDisk
+	if b.RunStrategy != nil {
+		protoimpl.X.SetPresentNonAtomic(&(x.XXX_presence[0]), 4, 5)
+		x.xxx_hidden_RunStrategy = b.RunStrategy
+	}
+	return m0
+}
+
 var File_osac_private_v1_compute_instance_template_type_proto protoreflect.FileDescriptor
 
 var file_osac_private_v1_compute_instance_template_type_proto_rawDesc = string([]byte{
@@ -310,71 +533,108 @@ var file_osac_private_v1_compute_instance_template_type_proto_rawDesc = string([
 	0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x12, 0x0f, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69,
 	0x76, 0x61, 0x74, 0x65, 0x2e, 0x76, 0x31, 0x1a, 0x19, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x2f,
 	0x70, 0x72, 0x6f, 0x74, 0x6f, 0x62, 0x75, 0x66, 0x2f, 0x61, 0x6e, 0x79, 0x2e, 0x70, 0x72, 0x6f,
-	0x74, 0x6f, 0x1a, 0x23, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65,
-	0x2f, 0x76, 0x31, 0x2f, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x5f, 0x74, 0x79, 0x70,
-	0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x22, 0xf5, 0x01, 0x0a, 0x17, 0x43, 0x6f, 0x6d, 0x70,
+	0x74, 0x6f, 0x1a, 0x2b, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65,
+	0x2f, 0x76, 0x31, 0x2f, 0x63, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x5f, 0x69, 0x6e, 0x73, 0x74,
+	0x61, 0x6e, 0x63, 0x65, 0x5f, 0x74, 0x79, 0x70, 0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x1a,
+	0x23, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2f, 0x76, 0x31,
+	0x2f, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x5f, 0x74, 0x79, 0x70, 0x65, 0x2e, 0x70,
+	0x72, 0x6f, 0x74, 0x6f, 0x22, 0xd0, 0x02, 0x0a, 0x17, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65,
+	0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65,
+	0x12, 0x0e, 0x0a, 0x02, 0x69, 0x64, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x02, 0x69, 0x64,
+	0x12, 0x35, 0x0a, 0x08, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x18, 0x02, 0x20, 0x01,
+	0x28, 0x0b, 0x32, 0x19, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74,
+	0x65, 0x2e, 0x76, 0x31, 0x2e, 0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x52, 0x08, 0x6d,
+	0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65,
+	0x18, 0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a,
+	0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x04, 0x20, 0x01,
+	0x28, 0x09, 0x52, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12,
+	0x5b, 0x0a, 0x0a, 0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x18, 0x05, 0x20,
+	0x03, 0x28, 0x0b, 0x32, 0x3b, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61,
+	0x74, 0x65, 0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73,
+	0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72,
+	0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e,
+	0x52, 0x0a, 0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x12, 0x59, 0x0a, 0x0d,
+	0x73, 0x70, 0x65, 0x63, 0x5f, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73, 0x18, 0x06, 0x20,
+	0x01, 0x28, 0x0b, 0x32, 0x34, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61,
+	0x74, 0x65, 0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73,
+	0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x53, 0x70, 0x65,
+	0x63, 0x44, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73, 0x52, 0x0c, 0x73, 0x70, 0x65, 0x63, 0x44,
+	0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73, 0x22, 0xd8, 0x01, 0x0a, 0x2a, 0x43, 0x6f, 0x6d, 0x70,
 	0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c,
-	0x61, 0x74, 0x65, 0x12, 0x0e, 0x0a, 0x02, 0x69, 0x64, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52,
-	0x02, 0x69, 0x64, 0x12, 0x35, 0x0a, 0x08, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x18,
-	0x02, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x19, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69,
-	0x76, 0x61, 0x74, 0x65, 0x2e, 0x76, 0x31, 0x2e, 0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61,
-	0x52, 0x08, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69,
-	0x74, 0x6c, 0x65, 0x18, 0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65,
+	0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69,
+	0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x12, 0x0a, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x18, 0x01,
+	0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69,
+	0x74, 0x6c, 0x65, 0x18, 0x02, 0x20, 0x01, 0x28, 0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65,
 	0x12, 0x20, 0x0a, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18,
-	0x04, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69,
-	0x6f, 0x6e, 0x12, 0x5b, 0x0a, 0x0a, 0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73,
-	0x18, 0x05, 0x20, 0x03, 0x28, 0x0b, 0x32, 0x3b, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72,
-	0x69, 0x76, 0x61, 0x74, 0x65, 0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65,
-	0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65,
-	0x50, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74,
-	0x69, 0x6f, 0x6e, 0x52, 0x0a, 0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x22,
-	0xd8, 0x01, 0x0a, 0x2a, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61,
-	0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61, 0x6d,
-	0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x12,
-	0x0a, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x6e, 0x61,
-	0x6d, 0x65, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x18, 0x02, 0x20, 0x01, 0x28,
-	0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a, 0x0b, 0x64, 0x65, 0x73, 0x63,
-	0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b, 0x64,
-	0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x1a, 0x0a, 0x08, 0x72, 0x65,
-	0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x18, 0x04, 0x20, 0x01, 0x28, 0x08, 0x52, 0x08, 0x72, 0x65,
-	0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x12, 0x12, 0x0a, 0x04, 0x74, 0x79, 0x70, 0x65, 0x18, 0x05,
-	0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x74, 0x79, 0x70, 0x65, 0x12, 0x2e, 0x0a, 0x07, 0x64, 0x65,
-	0x66, 0x61, 0x75, 0x6c, 0x74, 0x18, 0x06, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x14, 0x2e, 0x67, 0x6f,
-	0x6f, 0x67, 0x6c, 0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x62, 0x75, 0x66, 0x2e, 0x41, 0x6e,
-	0x79, 0x52, 0x07, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x42, 0xeb, 0x01, 0x0a, 0x13, 0x63,
-	0x6f, 0x6d, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2e,
-	0x76, 0x31, 0x42, 0x20, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61,
-	0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x54, 0x79, 0x70, 0x65, 0x50,
-	0x72, 0x6f, 0x74, 0x6f, 0x50, 0x01, 0x5a, 0x52, 0x67, 0x69, 0x74, 0x68, 0x75, 0x62, 0x2e, 0x63,
-	0x6f, 0x6d, 0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2d, 0x70, 0x72, 0x6f, 0x6a, 0x65, 0x63, 0x74, 0x2f,
-	0x66, 0x75, 0x6c, 0x66, 0x69, 0x6c, 0x6c, 0x6d, 0x65, 0x6e, 0x74, 0x2d, 0x73, 0x65, 0x72, 0x76,
-	0x69, 0x63, 0x65, 0x2f, 0x69, 0x6e, 0x74, 0x65, 0x72, 0x6e, 0x61, 0x6c, 0x2f, 0x61, 0x70, 0x69,
-	0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2f, 0x76, 0x31,
-	0x3b, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x76, 0x31, 0xa2, 0x02, 0x03, 0x4f, 0x50, 0x58,
-	0xaa, 0x02, 0x0f, 0x4f, 0x73, 0x61, 0x63, 0x2e, 0x50, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2e,
-	0x56, 0x31, 0xca, 0x02, 0x10, 0x4f, 0x73, 0x61, 0x63, 0x5c, 0x50, 0x72, 0x69, 0x76, 0x61, 0x74,
-	0x65, 0x5f, 0x5c, 0x56, 0x31, 0xe2, 0x02, 0x1c, 0x4f, 0x73, 0x61, 0x63, 0x5c, 0x50, 0x72, 0x69,
-	0x76, 0x61, 0x74, 0x65, 0x5f, 0x5c, 0x56, 0x31, 0x5c, 0x47, 0x50, 0x42, 0x4d, 0x65, 0x74, 0x61,
-	0x64, 0x61, 0x74, 0x61, 0xea, 0x02, 0x11, 0x4f, 0x73, 0x61, 0x63, 0x3a, 0x3a, 0x50, 0x72, 0x69,
-	0x76, 0x61, 0x74, 0x65, 0x3a, 0x3a, 0x56, 0x31, 0x62, 0x06, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x33,
+	0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69,
+	0x6f, 0x6e, 0x12, 0x1a, 0x0a, 0x08, 0x72, 0x65, 0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x18, 0x04,
+	0x20, 0x01, 0x28, 0x08, 0x52, 0x08, 0x72, 0x65, 0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x12, 0x12,
+	0x0a, 0x04, 0x74, 0x79, 0x70, 0x65, 0x18, 0x05, 0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x74, 0x79,
+	0x70, 0x65, 0x12, 0x2e, 0x0a, 0x07, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x18, 0x06, 0x20,
+	0x01, 0x28, 0x0b, 0x32, 0x14, 0x2e, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x2e, 0x70, 0x72, 0x6f,
+	0x74, 0x6f, 0x62, 0x75, 0x66, 0x2e, 0x41, 0x6e, 0x79, 0x52, 0x07, 0x64, 0x65, 0x66, 0x61, 0x75,
+	0x6c, 0x74, 0x22, 0xd8, 0x02, 0x0a, 0x23, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e,
+	0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x53, 0x70,
+	0x65, 0x63, 0x44, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73, 0x12, 0x19, 0x0a, 0x05, 0x63, 0x6f,
+	0x72, 0x65, 0x73, 0x18, 0x01, 0x20, 0x01, 0x28, 0x05, 0x48, 0x00, 0x52, 0x05, 0x63, 0x6f, 0x72,
+	0x65, 0x73, 0x88, 0x01, 0x01, 0x12, 0x22, 0x0a, 0x0a, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x5f,
+	0x67, 0x69, 0x62, 0x18, 0x02, 0x20, 0x01, 0x28, 0x05, 0x48, 0x01, 0x52, 0x09, 0x6d, 0x65, 0x6d,
+	0x6f, 0x72, 0x79, 0x47, 0x69, 0x62, 0x88, 0x01, 0x01, 0x12, 0x40, 0x0a, 0x05, 0x69, 0x6d, 0x61,
+	0x67, 0x65, 0x18, 0x03, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x25, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e,
+	0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75,
+	0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x49, 0x6d, 0x61, 0x67, 0x65, 0x48,
+	0x02, 0x52, 0x05, 0x69, 0x6d, 0x61, 0x67, 0x65, 0x88, 0x01, 0x01, 0x12, 0x46, 0x0a, 0x09, 0x62,
+	0x6f, 0x6f, 0x74, 0x5f, 0x64, 0x69, 0x73, 0x6b, 0x18, 0x04, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x24,
+	0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2e, 0x76, 0x31,
+	0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65,
+	0x44, 0x69, 0x73, 0x6b, 0x48, 0x03, 0x52, 0x08, 0x62, 0x6f, 0x6f, 0x74, 0x44, 0x69, 0x73, 0x6b,
+	0x88, 0x01, 0x01, 0x12, 0x26, 0x0a, 0x0c, 0x72, 0x75, 0x6e, 0x5f, 0x73, 0x74, 0x72, 0x61, 0x74,
+	0x65, 0x67, 0x79, 0x18, 0x05, 0x20, 0x01, 0x28, 0x09, 0x48, 0x04, 0x52, 0x0b, 0x72, 0x75, 0x6e,
+	0x53, 0x74, 0x72, 0x61, 0x74, 0x65, 0x67, 0x79, 0x88, 0x01, 0x01, 0x42, 0x08, 0x0a, 0x06, 0x5f,
+	0x63, 0x6f, 0x72, 0x65, 0x73, 0x42, 0x0d, 0x0a, 0x0b, 0x5f, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79,
+	0x5f, 0x67, 0x69, 0x62, 0x42, 0x08, 0x0a, 0x06, 0x5f, 0x69, 0x6d, 0x61, 0x67, 0x65, 0x42, 0x0c,
+	0x0a, 0x0a, 0x5f, 0x62, 0x6f, 0x6f, 0x74, 0x5f, 0x64, 0x69, 0x73, 0x6b, 0x42, 0x0f, 0x0a, 0x0d,
+	0x5f, 0x72, 0x75, 0x6e, 0x5f, 0x73, 0x74, 0x72, 0x61, 0x74, 0x65, 0x67, 0x79, 0x42, 0xeb, 0x01,
+	0x0a, 0x13, 0x63, 0x6f, 0x6d, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x72, 0x69, 0x76, 0x61,
+	0x74, 0x65, 0x2e, 0x76, 0x31, 0x42, 0x20, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e,
+	0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x54, 0x79,
+	0x70, 0x65, 0x50, 0x72, 0x6f, 0x74, 0x6f, 0x50, 0x01, 0x5a, 0x52, 0x67, 0x69, 0x74, 0x68, 0x75,
+	0x62, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2d, 0x70, 0x72, 0x6f, 0x6a, 0x65,
+	0x63, 0x74, 0x2f, 0x66, 0x75, 0x6c, 0x66, 0x69, 0x6c, 0x6c, 0x6d, 0x65, 0x6e, 0x74, 0x2d, 0x73,
+	0x65, 0x72, 0x76, 0x69, 0x63, 0x65, 0x2f, 0x69, 0x6e, 0x74, 0x65, 0x72, 0x6e, 0x61, 0x6c, 0x2f,
+	0x61, 0x70, 0x69, 0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65,
+	0x2f, 0x76, 0x31, 0x3b, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x76, 0x31, 0xa2, 0x02, 0x03,
+	0x4f, 0x50, 0x58, 0xaa, 0x02, 0x0f, 0x4f, 0x73, 0x61, 0x63, 0x2e, 0x50, 0x72, 0x69, 0x76, 0x61,
+	0x74, 0x65, 0x2e, 0x56, 0x31, 0xca, 0x02, 0x10, 0x4f, 0x73, 0x61, 0x63, 0x5c, 0x50, 0x72, 0x69,
+	0x76, 0x61, 0x74, 0x65, 0x5f, 0x5c, 0x56, 0x31, 0xe2, 0x02, 0x1c, 0x4f, 0x73, 0x61, 0x63, 0x5c,
+	0x50, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x5f, 0x5c, 0x56, 0x31, 0x5c, 0x47, 0x50, 0x42, 0x4d,
+	0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0xea, 0x02, 0x11, 0x4f, 0x73, 0x61, 0x63, 0x3a, 0x3a,
+	0x50, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x3a, 0x3a, 0x56, 0x31, 0x62, 0x06, 0x70, 0x72, 0x6f,
+	0x74, 0x6f, 0x33,
 })
 
-var file_osac_private_v1_compute_instance_template_type_proto_msgTypes = make([]protoimpl.MessageInfo, 2)
+var file_osac_private_v1_compute_instance_template_type_proto_msgTypes = make([]protoimpl.MessageInfo, 3)
 var file_osac_private_v1_compute_instance_template_type_proto_goTypes = []any{
 	(*ComputeInstanceTemplate)(nil),                    // 0: osac.private.v1.ComputeInstanceTemplate
 	(*ComputeInstanceTemplateParameterDefinition)(nil), // 1: osac.private.v1.ComputeInstanceTemplateParameterDefinition
-	(*Metadata)(nil),                                   // 2: osac.private.v1.Metadata
-	(*anypb.Any)(nil),                                  // 3: google.protobuf.Any
+	(*ComputeInstanceTemplateSpecDefaults)(nil),        // 2: osac.private.v1.ComputeInstanceTemplateSpecDefaults
+	(*Metadata)(nil),             // 3: osac.private.v1.Metadata
+	(*anypb.Any)(nil),            // 4: google.protobuf.Any
+	(*ComputeInstanceImage)(nil), // 5: osac.private.v1.ComputeInstanceImage
+	(*ComputeInstanceDisk)(nil),  // 6: osac.private.v1.ComputeInstanceDisk
 }
 var file_osac_private_v1_compute_instance_template_type_proto_depIdxs = []int32{
-	2, // 0: osac.private.v1.ComputeInstanceTemplate.metadata:type_name -> osac.private.v1.Metadata
+	3, // 0: osac.private.v1.ComputeInstanceTemplate.metadata:type_name -> osac.private.v1.Metadata
 	1, // 1: osac.private.v1.ComputeInstanceTemplate.parameters:type_name -> osac.private.v1.ComputeInstanceTemplateParameterDefinition
-	3, // 2: osac.private.v1.ComputeInstanceTemplateParameterDefinition.default:type_name -> google.protobuf.Any
-	3, // [3:3] is the sub-list for method output_type
-	3, // [3:3] is the sub-list for method input_type
-	3, // [3:3] is the sub-list for extension type_name
-	3, // [3:3] is the sub-list for extension extendee
-	0, // [0:3] is the sub-list for field type_name
+	2, // 2: osac.private.v1.ComputeInstanceTemplate.spec_defaults:type_name -> osac.private.v1.ComputeInstanceTemplateSpecDefaults
+	4, // 3: osac.private.v1.ComputeInstanceTemplateParameterDefinition.default:type_name -> google.protobuf.Any
+	5, // 4: osac.private.v1.ComputeInstanceTemplateSpecDefaults.image:type_name -> osac.private.v1.ComputeInstanceImage
+	6, // 5: osac.private.v1.ComputeInstanceTemplateSpecDefaults.boot_disk:type_name -> osac.private.v1.ComputeInstanceDisk
+	6, // [6:6] is the sub-list for method output_type
+	6, // [6:6] is the sub-list for method input_type
+	6, // [6:6] is the sub-list for extension type_name
+	6, // [6:6] is the sub-list for extension extendee
+	0, // [0:6] is the sub-list for field type_name
 }
 
 func init() { file_osac_private_v1_compute_instance_template_type_proto_init() }
@@ -382,14 +642,16 @@ func file_osac_private_v1_compute_instance_template_type_proto_init() {
 	if File_osac_private_v1_compute_instance_template_type_proto != nil {
 		return
 	}
+	file_osac_private_v1_compute_instance_type_proto_init()
 	file_osac_private_v1_metadata_type_proto_init()
+	file_osac_private_v1_compute_instance_template_type_proto_msgTypes[2].OneofWrappers = []any{}
 	type x struct{}
 	out := protoimpl.TypeBuilder{
 		File: protoimpl.DescBuilder{
 			GoPackagePath: reflect.TypeOf(x{}).PkgPath(),
 			RawDescriptor: unsafe.Slice(unsafe.StringData(file_osac_private_v1_compute_instance_template_type_proto_rawDesc), len(file_osac_private_v1_compute_instance_template_type_proto_rawDesc)),
 			NumEnums:      0,
-			NumMessages:   2,
+			NumMessages:   3,
 			NumExtensions: 0,
 			NumServices:   0,
 		},
diff --git a/internal/api/osac/public/v1/compute_instance_template_type.pb.go b/internal/api/osac/public/v1/compute_instance_template_type.pb.go
index ea15a96d..7a1b8554 100644
--- a/internal/api/osac/public/v1/compute_instance_template_type.pb.go
+++ b/internal/api/osac/public/v1/compute_instance_template_type.pb.go
@@ -52,7 +52,12 @@ type ComputeInstanceTemplate struct {
 	//
 	// Note that these are only the *definitions* of the parameters, not the actual values. The actual values are in the
 	// `spec.template_parameters` field of the compute instance.
-	Parameters    []*ComputeInstanceTemplateParameterDefinition `protobuf:"bytes,5,rep,name=parameters,proto3" json:"parameters,omitempty"`
+	Parameters []*ComputeInstanceTemplateParameterDefinition `protobuf:"bytes,5,rep,name=parameters,proto3" json:"parameters,omitempty"`
+	// Default values for compute instance spec fields. When a user creates a
+	// compute instance without setting these fields, these values are applied.
+	//
+	// User-provided spec field values always override these defaults.
+	SpecDefaults  *ComputeInstanceTemplateSpecDefaults `protobuf:"bytes,6,opt,name=spec_defaults,json=specDefaults,proto3" json:"spec_defaults,omitempty"`
 	unknownFields protoimpl.UnknownFields
 	sizeCache     protoimpl.SizeCache
 }
@@ -117,6 +122,13 @@ func (x *ComputeInstanceTemplate) GetParameters() []*ComputeInstanceTemplatePara
 	return nil
 }
 
+func (x *ComputeInstanceTemplate) GetSpecDefaults() *ComputeInstanceTemplateSpecDefaults {
+	if x != nil {
+		return x.SpecDefaults
+	}
+	return nil
+}
+
 func (x *ComputeInstanceTemplate) SetId(v string) {
 	x.Id = v
 }
@@ -137,6 +149,10 @@ func (x *ComputeInstanceTemplate) SetParameters(v []*ComputeInstanceTemplatePara
 	x.Parameters = v
 }
 
+func (x *ComputeInstanceTemplate) SetSpecDefaults(v *ComputeInstanceTemplateSpecDefaults) {
+	x.SpecDefaults = v
+}
+
 func (x *ComputeInstanceTemplate) HasMetadata() bool {
 	if x == nil {
 		return false
@@ -144,10 +160,21 @@ func (x *ComputeInstanceTemplate) HasMetadata() bool {
 	return x.Metadata != nil
 }
 
+func (x *ComputeInstanceTemplate) HasSpecDefaults() bool {
+	if x == nil {
+		return false
+	}
+	return x.SpecDefaults != nil
+}
+
 func (x *ComputeInstanceTemplate) ClearMetadata() {
 	x.Metadata = nil
 }
 
+func (x *ComputeInstanceTemplate) ClearSpecDefaults() {
+	x.SpecDefaults = nil
+}
+
 type ComputeInstanceTemplate_builder struct {
 	_ [0]func() // Prevents comparability and use of unkeyed literals for the builder.
 
@@ -164,6 +191,11 @@ type ComputeInstanceTemplate_builder struct {
 	// Note that these are only the *definitions* of the parameters, not the actual values. The actual values are in the
 	// `spec.template_parameters` field of the compute instance.
 	Parameters []*ComputeInstanceTemplateParameterDefinition
+	// Default values for compute instance spec fields. When a user creates a
+	// compute instance without setting these fields, these values are applied.
+	//
+	// User-provided spec field values always override these defaults.
+	SpecDefaults *ComputeInstanceTemplateSpecDefaults
 }
 
 func (b0 ComputeInstanceTemplate_builder) Build() *ComputeInstanceTemplate {
@@ -175,6 +207,7 @@ func (b0 ComputeInstanceTemplate_builder) Build() *ComputeInstanceTemplate {
 	x.Title = b.Title
 	x.Description = b.Description
 	x.Parameters = b.Parameters
+	x.SpecDefaults = b.SpecDefaults
 	return m0
 }
 
@@ -385,6 +418,185 @@ func (b0 ComputeInstanceTemplateParameterDefinition_builder) Build() *ComputeIns
 	return m0
 }
 
+// Default values for compute instance spec fields.
+type ComputeInstanceTemplateSpecDefaults struct {
+	state protoimpl.MessageState `protogen:"hybrid.v1"`
+	// Default number of CPU cores.
+	Cores *int32 `protobuf:"varint,1,opt,name=cores,proto3,oneof" json:"cores,omitempty"`
+	// Default memory size in GiB.
+	MemoryGib *int32 `protobuf:"varint,2,opt,name=memory_gib,json=memoryGib,proto3,oneof" json:"memory_gib,omitempty"`
+	// Default image configuration.
+	Image *ComputeInstanceImage `protobuf:"bytes,3,opt,name=image,proto3,oneof" json:"image,omitempty"`
+	// Default boot disk configuration.
+	BootDisk *ComputeInstanceDisk `protobuf:"bytes,4,opt,name=boot_disk,json=bootDisk,proto3,oneof" json:"boot_disk,omitempty"`
+	// Default run strategy.
+	RunStrategy   *string `protobuf:"bytes,5,opt,name=run_strategy,json=runStrategy,proto3,oneof" json:"run_strategy,omitempty"`
+	unknownFields protoimpl.UnknownFields
+	sizeCache     protoimpl.SizeCache
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) Reset() {
+	*x = ComputeInstanceTemplateSpecDefaults{}
+	mi := &file_osac_public_v1_compute_instance_template_type_proto_msgTypes[2]
+	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
+	ms.StoreMessageInfo(mi)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) String() string {
+	return protoimpl.X.MessageStringOf(x)
+}
+
+func (*ComputeInstanceTemplateSpecDefaults) ProtoMessage() {}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ProtoReflect() protoreflect.Message {
+	mi := &file_osac_public_v1_compute_instance_template_type_proto_msgTypes[2]
+	if x != nil {
+		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
+		if ms.LoadMessageInfo() == nil {
+			ms.StoreMessageInfo(mi)
+		}
+		return ms
+	}
+	return mi.MessageOf(x)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetCores() int32 {
+	if x != nil && x.Cores != nil {
+		return *x.Cores
+	}
+	return 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetMemoryGib() int32 {
+	if x != nil && x.MemoryGib != nil {
+		return *x.MemoryGib
+	}
+	return 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetImage() *ComputeInstanceImage {
+	if x != nil {
+		return x.Image
+	}
+	return nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetBootDisk() *ComputeInstanceDisk {
+	if x != nil {
+		return x.BootDisk
+	}
+	return nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetRunStrategy() string {
+	if x != nil && x.RunStrategy != nil {
+		return *x.RunStrategy
+	}
+	return ""
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetCores(v int32) {
+	x.Cores = &v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetMemoryGib(v int32) {
+	x.MemoryGib = &v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetImage(v *ComputeInstanceImage) {
+	x.Image = v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetBootDisk(v *ComputeInstanceDisk) {
+	x.BootDisk = v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetRunStrategy(v string) {
+	x.RunStrategy = &v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasCores() bool {
+	if x == nil {
+		return false
+	}
+	return x.Cores != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasMemoryGib() bool {
+	if x == nil {
+		return false
+	}
+	return x.MemoryGib != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasImage() bool {
+	if x == nil {
+		return false
+	}
+	return x.Image != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasBootDisk() bool {
+	if x == nil {
+		return false
+	}
+	return x.BootDisk != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasRunStrategy() bool {
+	if x == nil {
+		return false
+	}
+	return x.RunStrategy != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearCores() {
+	x.Cores = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearMemoryGib() {
+	x.MemoryGib = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearImage() {
+	x.Image = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearBootDisk() {
+	x.BootDisk = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearRunStrategy() {
+	x.RunStrategy = nil
+}
+
+type ComputeInstanceTemplateSpecDefaults_builder struct {
+	_ [0]func() // Prevents comparability and use of unkeyed literals for the builder.
+
+	// Default number of CPU cores.
+	Cores *int32
+	// Default memory size in GiB.
+	MemoryGib *int32
+	// Default image configuration.
+	Image *ComputeInstanceImage
+	// Default boot disk configuration.
+	BootDisk *ComputeInstanceDisk
+	// Default run strategy.
+	RunStrategy *string
+}
+
+func (b0 ComputeInstanceTemplateSpecDefaults_builder) Build() *ComputeInstanceTemplateSpecDefaults {
+	m0 := &ComputeInstanceTemplateSpecDefaults{}
+	b, x := &b0, m0
+	_, _ = b, x
+	x.Cores = b.Cores
+	x.MemoryGib = b.MemoryGib
+	x.Image = b.Image
+	x.BootDisk = b.BootDisk
+	x.RunStrategy = b.RunStrategy
+	return m0
+}
+
 var File_osac_public_v1_compute_instance_template_type_proto protoreflect.FileDescriptor
 
 var file_osac_public_v1_compute_instance_template_type_proto_rawDesc = string([]byte{
@@ -394,71 +606,107 @@ var file_osac_public_v1_compute_instance_template_type_proto_rawDesc = string([]
 	0x70, 0x72, 0x6f, 0x74, 0x6f, 0x12, 0x0e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c,
 	0x69, 0x63, 0x2e, 0x76, 0x31, 0x1a, 0x19, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x2f, 0x70, 0x72,
 	0x6f, 0x74, 0x6f, 0x62, 0x75, 0x66, 0x2f, 0x61, 0x6e, 0x79, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f,
-	0x1a, 0x22, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2f, 0x76, 0x31,
-	0x2f, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x5f, 0x74, 0x79, 0x70, 0x65, 0x2e, 0x70,
-	0x72, 0x6f, 0x74, 0x6f, 0x22, 0xf3, 0x01, 0x0a, 0x17, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65,
-	0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65,
-	0x12, 0x0e, 0x0a, 0x02, 0x69, 0x64, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x02, 0x69, 0x64,
-	0x12, 0x34, 0x0a, 0x08, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x18, 0x02, 0x20, 0x01,
-	0x28, 0x0b, 0x32, 0x18, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63,
-	0x2e, 0x76, 0x31, 0x2e, 0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x52, 0x08, 0x6d, 0x65,
-	0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x18,
-	0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a, 0x0b,
-	0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x04, 0x20, 0x01, 0x28,
-	0x09, 0x52, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x5a,
-	0x0a, 0x0a, 0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x18, 0x05, 0x20, 0x03,
-	0x28, 0x0b, 0x32, 0x3a, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63,
-	0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61,
-	0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61, 0x6d,
-	0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x52, 0x0a,
-	0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x22, 0xd8, 0x01, 0x0a, 0x2a, 0x43,
+	0x1a, 0x2a, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2f, 0x76, 0x31,
+	0x2f, 0x63, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x5f, 0x69, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63,
+	0x65, 0x5f, 0x74, 0x79, 0x70, 0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x1a, 0x22, 0x6f, 0x73,
+	0x61, 0x63, 0x2f, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2f, 0x76, 0x31, 0x2f, 0x6d, 0x65, 0x74,
+	0x61, 0x64, 0x61, 0x74, 0x61, 0x5f, 0x74, 0x79, 0x70, 0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f,
+	0x22, 0xcd, 0x02, 0x0a, 0x17, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74,
+	0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x12, 0x0e, 0x0a, 0x02,
+	0x69, 0x64, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x02, 0x69, 0x64, 0x12, 0x34, 0x0a, 0x08,
+	0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x18, 0x02, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x18,
+	0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x2e,
+	0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x52, 0x08, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61,
+	0x74, 0x61, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x18, 0x03, 0x20, 0x01, 0x28,
+	0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a, 0x0b, 0x64, 0x65, 0x73, 0x63,
+	0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x04, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b, 0x64,
+	0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x5a, 0x0a, 0x0a, 0x70, 0x61,
+	0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x18, 0x05, 0x20, 0x03, 0x28, 0x0b, 0x32, 0x3a,
+	0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x2e,
+	0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54,
+	0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72,
+	0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x52, 0x0a, 0x70, 0x61, 0x72, 0x61,
+	0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x12, 0x58, 0x0a, 0x0d, 0x73, 0x70, 0x65, 0x63, 0x5f, 0x64,
+	0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73, 0x18, 0x06, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x33, 0x2e,
+	0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x2e, 0x43,
 	0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65,
-	0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x44,
-	0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x12, 0x0a, 0x04, 0x6e, 0x61, 0x6d,
-	0x65, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x12, 0x14, 0x0a,
-	0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x18, 0x02, 0x20, 0x01, 0x28, 0x09, 0x52, 0x05, 0x74, 0x69,
-	0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69,
-	0x6f, 0x6e, 0x18, 0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69,
-	0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x1a, 0x0a, 0x08, 0x72, 0x65, 0x71, 0x75, 0x69, 0x72, 0x65,
-	0x64, 0x18, 0x04, 0x20, 0x01, 0x28, 0x08, 0x52, 0x08, 0x72, 0x65, 0x71, 0x75, 0x69, 0x72, 0x65,
-	0x64, 0x12, 0x12, 0x0a, 0x04, 0x74, 0x79, 0x70, 0x65, 0x18, 0x05, 0x20, 0x01, 0x28, 0x09, 0x52,
-	0x04, 0x74, 0x79, 0x70, 0x65, 0x12, 0x2e, 0x0a, 0x07, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74,
-	0x18, 0x06, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x14, 0x2e, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x2e,
-	0x70, 0x72, 0x6f, 0x74, 0x6f, 0x62, 0x75, 0x66, 0x2e, 0x41, 0x6e, 0x79, 0x52, 0x07, 0x64, 0x65,
-	0x66, 0x61, 0x75, 0x6c, 0x74, 0x42, 0xe4, 0x01, 0x0a, 0x12, 0x63, 0x6f, 0x6d, 0x2e, 0x6f, 0x73,
-	0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x42, 0x20, 0x43, 0x6f,
-	0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d,
-	0x70, 0x6c, 0x61, 0x74, 0x65, 0x54, 0x79, 0x70, 0x65, 0x50, 0x72, 0x6f, 0x74, 0x6f, 0x50, 0x01,
-	0x5a, 0x50, 0x67, 0x69, 0x74, 0x68, 0x75, 0x62, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x6f, 0x73, 0x61,
-	0x63, 0x2d, 0x70, 0x72, 0x6f, 0x6a, 0x65, 0x63, 0x74, 0x2f, 0x66, 0x75, 0x6c, 0x66, 0x69, 0x6c,
-	0x6c, 0x6d, 0x65, 0x6e, 0x74, 0x2d, 0x73, 0x65, 0x72, 0x76, 0x69, 0x63, 0x65, 0x2f, 0x69, 0x6e,
-	0x74, 0x65, 0x72, 0x6e, 0x61, 0x6c, 0x2f, 0x61, 0x70, 0x69, 0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2f,
-	0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2f, 0x76, 0x31, 0x3b, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63,
-	0x76, 0x31, 0xa2, 0x02, 0x03, 0x4f, 0x50, 0x58, 0xaa, 0x02, 0x0e, 0x4f, 0x73, 0x61, 0x63, 0x2e,
-	0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x56, 0x31, 0xca, 0x02, 0x0f, 0x4f, 0x73, 0x61, 0x63,
-	0x5c, 0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x5f, 0x5c, 0x56, 0x31, 0xe2, 0x02, 0x1b, 0x4f, 0x73,
-	0x61, 0x63, 0x5c, 0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x5f, 0x5c, 0x56, 0x31, 0x5c, 0x47, 0x50,
-	0x42, 0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0xea, 0x02, 0x10, 0x4f, 0x73, 0x61, 0x63,
-	0x3a, 0x3a, 0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x3a, 0x3a, 0x56, 0x31, 0x62, 0x06, 0x70, 0x72,
-	0x6f, 0x74, 0x6f, 0x33,
+	0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x53, 0x70, 0x65, 0x63, 0x44, 0x65, 0x66, 0x61, 0x75, 0x6c,
+	0x74, 0x73, 0x52, 0x0c, 0x73, 0x70, 0x65, 0x63, 0x44, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73,
+	0x22, 0xd8, 0x01, 0x0a, 0x2a, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74,
+	0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61,
+	0x6d, 0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x12,
+	0x12, 0x0a, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x6e,
+	0x61, 0x6d, 0x65, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x18, 0x02, 0x20, 0x01,
+	0x28, 0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a, 0x0b, 0x64, 0x65, 0x73,
+	0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b,
+	0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x1a, 0x0a, 0x08, 0x72,
+	0x65, 0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x18, 0x04, 0x20, 0x01, 0x28, 0x08, 0x52, 0x08, 0x72,
+	0x65, 0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x12, 0x12, 0x0a, 0x04, 0x74, 0x79, 0x70, 0x65, 0x18,
+	0x05, 0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x74, 0x79, 0x70, 0x65, 0x12, 0x2e, 0x0a, 0x07, 0x64,
+	0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x18, 0x06, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x14, 0x2e, 0x67,
+	0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x62, 0x75, 0x66, 0x2e, 0x41,
+	0x6e, 0x79, 0x52, 0x07, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x22, 0xd6, 0x02, 0x0a, 0x23,
+	0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54,
+	0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x53, 0x70, 0x65, 0x63, 0x44, 0x65, 0x66, 0x61, 0x75,
+	0x6c, 0x74, 0x73, 0x12, 0x19, 0x0a, 0x05, 0x63, 0x6f, 0x72, 0x65, 0x73, 0x18, 0x01, 0x20, 0x01,
+	0x28, 0x05, 0x48, 0x00, 0x52, 0x05, 0x63, 0x6f, 0x72, 0x65, 0x73, 0x88, 0x01, 0x01, 0x12, 0x22,
+	0x0a, 0x0a, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x5f, 0x67, 0x69, 0x62, 0x18, 0x02, 0x20, 0x01,
+	0x28, 0x05, 0x48, 0x01, 0x52, 0x09, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x47, 0x69, 0x62, 0x88,
+	0x01, 0x01, 0x12, 0x3f, 0x0a, 0x05, 0x69, 0x6d, 0x61, 0x67, 0x65, 0x18, 0x03, 0x20, 0x01, 0x28,
+	0x0b, 0x32, 0x24, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e,
+	0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e,
+	0x63, 0x65, 0x49, 0x6d, 0x61, 0x67, 0x65, 0x48, 0x02, 0x52, 0x05, 0x69, 0x6d, 0x61, 0x67, 0x65,
+	0x88, 0x01, 0x01, 0x12, 0x45, 0x0a, 0x09, 0x62, 0x6f, 0x6f, 0x74, 0x5f, 0x64, 0x69, 0x73, 0x6b,
+	0x18, 0x04, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x23, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75,
+	0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49,
+	0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x44, 0x69, 0x73, 0x6b, 0x48, 0x03, 0x52, 0x08, 0x62,
+	0x6f, 0x6f, 0x74, 0x44, 0x69, 0x73, 0x6b, 0x88, 0x01, 0x01, 0x12, 0x26, 0x0a, 0x0c, 0x72, 0x75,
+	0x6e, 0x5f, 0x73, 0x74, 0x72, 0x61, 0x74, 0x65, 0x67, 0x79, 0x18, 0x05, 0x20, 0x01, 0x28, 0x09,
+	0x48, 0x04, 0x52, 0x0b, 0x72, 0x75, 0x6e, 0x53, 0x74, 0x72, 0x61, 0x74, 0x65, 0x67, 0x79, 0x88,
+	0x01, 0x01, 0x42, 0x08, 0x0a, 0x06, 0x5f, 0x63, 0x6f, 0x72, 0x65, 0x73, 0x42, 0x0d, 0x0a, 0x0b,
+	0x5f, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x5f, 0x67, 0x69, 0x62, 0x42, 0x08, 0x0a, 0x06, 0x5f,
+	0x69, 0x6d, 0x61, 0x67, 0x65, 0x42, 0x0c, 0x0a, 0x0a, 0x5f, 0x62, 0x6f, 0x6f, 0x74, 0x5f, 0x64,
+	0x69, 0x73, 0x6b, 0x42, 0x0f, 0x0a, 0x0d, 0x5f, 0x72, 0x75, 0x6e, 0x5f, 0x73, 0x74, 0x72, 0x61,
+	0x74, 0x65, 0x67, 0x79, 0x42, 0xe4, 0x01, 0x0a, 0x12, 0x63, 0x6f, 0x6d, 0x2e, 0x6f, 0x73, 0x61,
+	0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x42, 0x20, 0x43, 0x6f, 0x6d,
+	0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70,
+	0x6c, 0x61, 0x74, 0x65, 0x54, 0x79, 0x70, 0x65, 0x50, 0x72, 0x6f, 0x74, 0x6f, 0x50, 0x01, 0x5a,
+	0x50, 0x67, 0x69, 0x74, 0x68, 0x75, 0x62, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x6f, 0x73, 0x61, 0x63,
+	0x2d, 0x70, 0x72, 0x6f, 0x6a, 0x65, 0x63, 0x74, 0x2f, 0x66, 0x75, 0x6c, 0x66, 0x69, 0x6c, 0x6c,
+	0x6d, 0x65, 0x6e, 0x74, 0x2d, 0x73, 0x65, 0x72, 0x76, 0x69, 0x63, 0x65, 0x2f, 0x69, 0x6e, 0x74,
+	0x65, 0x72, 0x6e, 0x61, 0x6c, 0x2f, 0x61, 0x70, 0x69, 0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70,
+	0x75, 0x62, 0x6c, 0x69, 0x63, 0x2f, 0x76, 0x31, 0x3b, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x76,
+	0x31, 0xa2, 0x02, 0x03, 0x4f, 0x50, 0x58, 0xaa, 0x02, 0x0e, 0x4f, 0x73, 0x61, 0x63, 0x2e, 0x50,
+	0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x56, 0x31, 0xca, 0x02, 0x0f, 0x4f, 0x73, 0x61, 0x63, 0x5c,
+	0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x5f, 0x5c, 0x56, 0x31, 0xe2, 0x02, 0x1b, 0x4f, 0x73, 0x61,
+	0x63, 0x5c, 0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x5f, 0x5c, 0x56, 0x31, 0x5c, 0x47, 0x50, 0x42,
+	0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0xea, 0x02, 0x10, 0x4f, 0x73, 0x61, 0x63, 0x3a,
+	0x3a, 0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x3a, 0x3a, 0x56, 0x31, 0x62, 0x06, 0x70, 0x72, 0x6f,
+	0x74, 0x6f, 0x33,
 })
 
-var file_osac_public_v1_compute_instance_template_type_proto_msgTypes = make([]protoimpl.MessageInfo, 2)
+var file_osac_public_v1_compute_instance_template_type_proto_msgTypes = make([]protoimpl.MessageInfo, 3)
 var file_osac_public_v1_compute_instance_template_type_proto_goTypes = []any{
 	(*ComputeInstanceTemplate)(nil),                    // 0: osac.public.v1.ComputeInstanceTemplate
 	(*ComputeInstanceTemplateParameterDefinition)(nil), // 1: osac.public.v1.ComputeInstanceTemplateParameterDefinition
-	(*Metadata)(nil),                                   // 2: osac.public.v1.Metadata
-	(*anypb.Any)(nil),                                  // 3: google.protobuf.Any
+	(*ComputeInstanceTemplateSpecDefaults)(nil),        // 2: osac.public.v1.ComputeInstanceTemplateSpecDefaults
+	(*Metadata)(nil),             // 3: osac.public.v1.Metadata
+	(*anypb.Any)(nil),            // 4: google.protobuf.Any
+	(*ComputeInstanceImage)(nil), // 5: osac.public.v1.ComputeInstanceImage
+	(*ComputeInstanceDisk)(nil),  // 6: osac.public.v1.ComputeInstanceDisk
 }
 var file_osac_public_v1_compute_instance_template_type_proto_depIdxs = []int32{
-	2, // 0: osac.public.v1.ComputeInstanceTemplate.metadata:type_name -> osac.public.v1.Metadata
+	3, // 0: osac.public.v1.ComputeInstanceTemplate.metadata:type_name -> osac.public.v1.Metadata
 	1, // 1: osac.public.v1.ComputeInstanceTemplate.parameters:type_name -> osac.public.v1.ComputeInstanceTemplateParameterDefinition
-	3, // 2: osac.public.v1.ComputeInstanceTemplateParameterDefinition.default:type_name -> google.protobuf.Any
-	3, // [3:3] is the sub-list for method output_type
-	3, // [3:3] is the sub-list for method input_type
-	3, // [3:3] is the sub-list for extension type_name
-	3, // [3:3] is the sub-list for extension extendee
-	0, // [0:3] is the sub-list for field type_name
+	2, // 2: osac.public.v1.ComputeInstanceTemplate.spec_defaults:type_name -> osac.public.v1.ComputeInstanceTemplateSpecDefaults
+	4, // 3: osac.public.v1.ComputeInstanceTemplateParameterDefinition.default:type_name -> google.protobuf.Any
+	5, // 4: osac.public.v1.ComputeInstanceTemplateSpecDefaults.image:type_name -> osac.public.v1.ComputeInstanceImage
+	6, // 5: osac.public.v1.ComputeInstanceTemplateSpecDefaults.boot_disk:type_name -> osac.public.v1.ComputeInstanceDisk
+	6, // [6:6] is the sub-list for method output_type
+	6, // [6:6] is the sub-list for method input_type
+	6, // [6:6] is the sub-list for extension type_name
+	6, // [6:6] is the sub-list for extension extendee
+	0, // [0:6] is the sub-list for field type_name
 }
 
 func init() { file_osac_public_v1_compute_instance_template_type_proto_init() }
@@ -466,14 +714,16 @@ func file_osac_public_v1_compute_instance_template_type_proto_init() {
 	if File_osac_public_v1_compute_instance_template_type_proto != nil {
 		return
 	}
+	file_osac_public_v1_compute_instance_type_proto_init()
 	file_osac_public_v1_metadata_type_proto_init()
+	file_osac_public_v1_compute_instance_template_type_proto_msgTypes[2].OneofWrappers = []any{}
 	type x struct{}
 	out := protoimpl.TypeBuilder{
 		File: protoimpl.DescBuilder{
 			GoPackagePath: reflect.TypeOf(x{}).PkgPath(),
 			RawDescriptor: unsafe.Slice(unsafe.StringData(file_osac_public_v1_compute_instance_template_type_proto_rawDesc), len(file_osac_public_v1_compute_instance_template_type_proto_rawDesc)),
 			NumEnums:      0,
-			NumMessages:   2,
+			NumMessages:   3,
 			NumExtensions: 0,
 			NumServices:   0,
 		},
diff --git a/internal/api/osac/public/v1/compute_instance_template_type_protoopaque.pb.go b/internal/api/osac/public/v1/compute_instance_template_type_protoopaque.pb.go
index 3dd530bf..ff37e2ff 100644
--- a/internal/api/osac/public/v1/compute_instance_template_type_protoopaque.pb.go
+++ b/internal/api/osac/public/v1/compute_instance_template_type_protoopaque.pb.go
@@ -39,14 +39,15 @@ const (
 // A compute instance template defines a type of compute instance that can be created by the user. Note that the user doesn't create these
 // templates: the system provides a collection of them, and the user chooses one.
 type ComputeInstanceTemplate struct {
-	state                  protoimpl.MessageState                         `protogen:"opaque.v1"`
-	xxx_hidden_Id          string                                         `protobuf:"bytes,1,opt,name=id,proto3"`
-	xxx_hidden_Metadata    *Metadata                                      `protobuf:"bytes,2,opt,name=metadata,proto3"`
-	xxx_hidden_Title       string                                         `protobuf:"bytes,3,opt,name=title,proto3"`
-	xxx_hidden_Description string                                         `protobuf:"bytes,4,opt,name=description,proto3"`
-	xxx_hidden_Parameters  *[]*ComputeInstanceTemplateParameterDefinition `protobuf:"bytes,5,rep,name=parameters,proto3"`
-	unknownFields          protoimpl.UnknownFields
-	sizeCache              protoimpl.SizeCache
+	state                   protoimpl.MessageState                         `protogen:"opaque.v1"`
+	xxx_hidden_Id           string                                         `protobuf:"bytes,1,opt,name=id,proto3"`
+	xxx_hidden_Metadata     *Metadata                                      `protobuf:"bytes,2,opt,name=metadata,proto3"`
+	xxx_hidden_Title        string                                         `protobuf:"bytes,3,opt,name=title,proto3"`
+	xxx_hidden_Description  string                                         `protobuf:"bytes,4,opt,name=description,proto3"`
+	xxx_hidden_Parameters   *[]*ComputeInstanceTemplateParameterDefinition `protobuf:"bytes,5,rep,name=parameters,proto3"`
+	xxx_hidden_SpecDefaults *ComputeInstanceTemplateSpecDefaults           `protobuf:"bytes,6,opt,name=spec_defaults,json=specDefaults,proto3"`
+	unknownFields           protoimpl.UnknownFields
+	sizeCache               protoimpl.SizeCache
 }
 
 func (x *ComputeInstanceTemplate) Reset() {
@@ -111,6 +112,13 @@ func (x *ComputeInstanceTemplate) GetParameters() []*ComputeInstanceTemplatePara
 	return nil
 }
 
+func (x *ComputeInstanceTemplate) GetSpecDefaults() *ComputeInstanceTemplateSpecDefaults {
+	if x != nil {
+		return x.xxx_hidden_SpecDefaults
+	}
+	return nil
+}
+
 func (x *ComputeInstanceTemplate) SetId(v string) {
 	x.xxx_hidden_Id = v
 }
@@ -131,6 +139,10 @@ func (x *ComputeInstanceTemplate) SetParameters(v []*ComputeInstanceTemplatePara
 	x.xxx_hidden_Parameters = &v
 }
 
+func (x *ComputeInstanceTemplate) SetSpecDefaults(v *ComputeInstanceTemplateSpecDefaults) {
+	x.xxx_hidden_SpecDefaults = v
+}
+
 func (x *ComputeInstanceTemplate) HasMetadata() bool {
 	if x == nil {
 		return false
@@ -138,10 +150,21 @@ func (x *ComputeInstanceTemplate) HasMetadata() bool {
 	return x.xxx_hidden_Metadata != nil
 }
 
+func (x *ComputeInstanceTemplate) HasSpecDefaults() bool {
+	if x == nil {
+		return false
+	}
+	return x.xxx_hidden_SpecDefaults != nil
+}
+
 func (x *ComputeInstanceTemplate) ClearMetadata() {
 	x.xxx_hidden_Metadata = nil
 }
 
+func (x *ComputeInstanceTemplate) ClearSpecDefaults() {
+	x.xxx_hidden_SpecDefaults = nil
+}
+
 type ComputeInstanceTemplate_builder struct {
 	_ [0]func() // Prevents comparability and use of unkeyed literals for the builder.
 
@@ -158,6 +181,11 @@ type ComputeInstanceTemplate_builder struct {
 	// Note that these are only the *definitions* of the parameters, not the actual values. The actual values are in the
 	// `spec.template_parameters` field of the compute instance.
 	Parameters []*ComputeInstanceTemplateParameterDefinition
+	// Default values for compute instance spec fields. When a user creates a
+	// compute instance without setting these fields, these values are applied.
+	//
+	// User-provided spec field values always override these defaults.
+	SpecDefaults *ComputeInstanceTemplateSpecDefaults
 }
 
 func (b0 ComputeInstanceTemplate_builder) Build() *ComputeInstanceTemplate {
@@ -169,6 +197,7 @@ func (b0 ComputeInstanceTemplate_builder) Build() *ComputeInstanceTemplate {
 	x.xxx_hidden_Title = b.Title
 	x.xxx_hidden_Description = b.Description
 	x.xxx_hidden_Parameters = &b.Parameters
+	x.xxx_hidden_SpecDefaults = b.SpecDefaults
 	return m0
 }
 
@@ -345,6 +374,200 @@ func (b0 ComputeInstanceTemplateParameterDefinition_builder) Build() *ComputeIns
 	return m0
 }
 
+// Default values for compute instance spec fields.
+type ComputeInstanceTemplateSpecDefaults struct {
+	state                  protoimpl.MessageState `protogen:"opaque.v1"`
+	xxx_hidden_Cores       int32                  `protobuf:"varint,1,opt,name=cores,proto3,oneof"`
+	xxx_hidden_MemoryGib   int32                  `protobuf:"varint,2,opt,name=memory_gib,json=memoryGib,proto3,oneof"`
+	xxx_hidden_Image       *ComputeInstanceImage  `protobuf:"bytes,3,opt,name=image,proto3,oneof"`
+	xxx_hidden_BootDisk    *ComputeInstanceDisk   `protobuf:"bytes,4,opt,name=boot_disk,json=bootDisk,proto3,oneof"`
+	xxx_hidden_RunStrategy *string                `protobuf:"bytes,5,opt,name=run_strategy,json=runStrategy,proto3,oneof"`
+	XXX_raceDetectHookData protoimpl.RaceDetectHookData
+	XXX_presence           [1]uint32
+	unknownFields          protoimpl.UnknownFields
+	sizeCache              protoimpl.SizeCache
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) Reset() {
+	*x = ComputeInstanceTemplateSpecDefaults{}
+	mi := &file_osac_public_v1_compute_instance_template_type_proto_msgTypes[2]
+	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
+	ms.StoreMessageInfo(mi)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) String() string {
+	return protoimpl.X.MessageStringOf(x)
+}
+
+func (*ComputeInstanceTemplateSpecDefaults) ProtoMessage() {}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ProtoReflect() protoreflect.Message {
+	mi := &file_osac_public_v1_compute_instance_template_type_proto_msgTypes[2]
+	if x != nil {
+		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
+		if ms.LoadMessageInfo() == nil {
+			ms.StoreMessageInfo(mi)
+		}
+		return ms
+	}
+	return mi.MessageOf(x)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetCores() int32 {
+	if x != nil {
+		return x.xxx_hidden_Cores
+	}
+	return 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetMemoryGib() int32 {
+	if x != nil {
+		return x.xxx_hidden_MemoryGib
+	}
+	return 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetImage() *ComputeInstanceImage {
+	if x != nil {
+		return x.xxx_hidden_Image
+	}
+	return nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetBootDisk() *ComputeInstanceDisk {
+	if x != nil {
+		return x.xxx_hidden_BootDisk
+	}
+	return nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) GetRunStrategy() string {
+	if x != nil {
+		if x.xxx_hidden_RunStrategy != nil {
+			return *x.xxx_hidden_RunStrategy
+		}
+		return ""
+	}
+	return ""
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetCores(v int32) {
+	x.xxx_hidden_Cores = v
+	protoimpl.X.SetPresent(&(x.XXX_presence[0]), 0, 5)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetMemoryGib(v int32) {
+	x.xxx_hidden_MemoryGib = v
+	protoimpl.X.SetPresent(&(x.XXX_presence[0]), 1, 5)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetImage(v *ComputeInstanceImage) {
+	x.xxx_hidden_Image = v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetBootDisk(v *ComputeInstanceDisk) {
+	x.xxx_hidden_BootDisk = v
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) SetRunStrategy(v string) {
+	x.xxx_hidden_RunStrategy = &v
+	protoimpl.X.SetPresent(&(x.XXX_presence[0]), 4, 5)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasCores() bool {
+	if x == nil {
+		return false
+	}
+	return protoimpl.X.Present(&(x.XXX_presence[0]), 0)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasMemoryGib() bool {
+	if x == nil {
+		return false
+	}
+	return protoimpl.X.Present(&(x.XXX_presence[0]), 1)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasImage() bool {
+	if x == nil {
+		return false
+	}
+	return x.xxx_hidden_Image != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasBootDisk() bool {
+	if x == nil {
+		return false
+	}
+	return x.xxx_hidden_BootDisk != nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) HasRunStrategy() bool {
+	if x == nil {
+		return false
+	}
+	return protoimpl.X.Present(&(x.XXX_presence[0]), 4)
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearCores() {
+	protoimpl.X.ClearPresent(&(x.XXX_presence[0]), 0)
+	x.xxx_hidden_Cores = 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearMemoryGib() {
+	protoimpl.X.ClearPresent(&(x.XXX_presence[0]), 1)
+	x.xxx_hidden_MemoryGib = 0
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearImage() {
+	x.xxx_hidden_Image = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearBootDisk() {
+	x.xxx_hidden_BootDisk = nil
+}
+
+func (x *ComputeInstanceTemplateSpecDefaults) ClearRunStrategy() {
+	protoimpl.X.ClearPresent(&(x.XXX_presence[0]), 4)
+	x.xxx_hidden_RunStrategy = nil
+}
+
+type ComputeInstanceTemplateSpecDefaults_builder struct {
+	_ [0]func() // Prevents comparability and use of unkeyed literals for the builder.
+
+	// Default number of CPU cores.
+	Cores *int32
+	// Default memory size in GiB.
+	MemoryGib *int32
+	// Default image configuration.
+	Image *ComputeInstanceImage
+	// Default boot disk configuration.
+	BootDisk *ComputeInstanceDisk
+	// Default run strategy.
+	RunStrategy *string
+}
+
+func (b0 ComputeInstanceTemplateSpecDefaults_builder) Build() *ComputeInstanceTemplateSpecDefaults {
+	m0 := &ComputeInstanceTemplateSpecDefaults{}
+	b, x := &b0, m0
+	_, _ = b, x
+	if b.Cores != nil {
+		protoimpl.X.SetPresentNonAtomic(&(x.XXX_presence[0]), 0, 5)
+		x.xxx_hidden_Cores = *b.Cores
+	}
+	if b.MemoryGib != nil {
+		protoimpl.X.SetPresentNonAtomic(&(x.XXX_presence[0]), 1, 5)
+		x.xxx_hidden_MemoryGib = *b.MemoryGib
+	}
+	x.xxx_hidden_Image = b.Image
+	x.xxx_hidden_BootDisk = b.BootDisk
+	if b.RunStrategy != nil {
+		protoimpl.X.SetPresentNonAtomic(&(x.XXX_presence[0]), 4, 5)
+		x.xxx_hidden_RunStrategy = b.RunStrategy
+	}
+	return m0
+}
+
 var File_osac_public_v1_compute_instance_template_type_proto protoreflect.FileDescriptor
 
 var file_osac_public_v1_compute_instance_template_type_proto_rawDesc = string([]byte{
@@ -354,71 +577,107 @@ var file_osac_public_v1_compute_instance_template_type_proto_rawDesc = string([]
 	0x70, 0x72, 0x6f, 0x74, 0x6f, 0x12, 0x0e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c,
 	0x69, 0x63, 0x2e, 0x76, 0x31, 0x1a, 0x19, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x2f, 0x70, 0x72,
 	0x6f, 0x74, 0x6f, 0x62, 0x75, 0x66, 0x2f, 0x61, 0x6e, 0x79, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f,
-	0x1a, 0x22, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2f, 0x76, 0x31,
-	0x2f, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x5f, 0x74, 0x79, 0x70, 0x65, 0x2e, 0x70,
-	0x72, 0x6f, 0x74, 0x6f, 0x22, 0xf3, 0x01, 0x0a, 0x17, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65,
-	0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65,
-	0x12, 0x0e, 0x0a, 0x02, 0x69, 0x64, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x02, 0x69, 0x64,
-	0x12, 0x34, 0x0a, 0x08, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x18, 0x02, 0x20, 0x01,
-	0x28, 0x0b, 0x32, 0x18, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63,
-	0x2e, 0x76, 0x31, 0x2e, 0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x52, 0x08, 0x6d, 0x65,
-	0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x18,
-	0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a, 0x0b,
-	0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x04, 0x20, 0x01, 0x28,
-	0x09, 0x52, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x5a,
-	0x0a, 0x0a, 0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x18, 0x05, 0x20, 0x03,
-	0x28, 0x0b, 0x32, 0x3a, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63,
-	0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61,
-	0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61, 0x6d,
-	0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x52, 0x0a,
-	0x70, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x22, 0xd8, 0x01, 0x0a, 0x2a, 0x43,
+	0x1a, 0x2a, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2f, 0x76, 0x31,
+	0x2f, 0x63, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x5f, 0x69, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63,
+	0x65, 0x5f, 0x74, 0x79, 0x70, 0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x1a, 0x22, 0x6f, 0x73,
+	0x61, 0x63, 0x2f, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2f, 0x76, 0x31, 0x2f, 0x6d, 0x65, 0x74,
+	0x61, 0x64, 0x61, 0x74, 0x61, 0x5f, 0x74, 0x79, 0x70, 0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f,
+	0x22, 0xcd, 0x02, 0x0a, 0x17, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74,
+	0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x12, 0x0e, 0x0a, 0x02,
+	0x69, 0x64, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x02, 0x69, 0x64, 0x12, 0x34, 0x0a, 0x08,
+	0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x18, 0x02, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x18,
+	0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x2e,
+	0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x52, 0x08, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61,
+	0x74, 0x61, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x18, 0x03, 0x20, 0x01, 0x28,
+	0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a, 0x0b, 0x64, 0x65, 0x73, 0x63,
+	0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x04, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b, 0x64,
+	0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x5a, 0x0a, 0x0a, 0x70, 0x61,
+	0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x18, 0x05, 0x20, 0x03, 0x28, 0x0b, 0x32, 0x3a,
+	0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x2e,
+	0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54,
+	0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72,
+	0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x52, 0x0a, 0x70, 0x61, 0x72, 0x61,
+	0x6d, 0x65, 0x74, 0x65, 0x72, 0x73, 0x12, 0x58, 0x0a, 0x0d, 0x73, 0x70, 0x65, 0x63, 0x5f, 0x64,
+	0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73, 0x18, 0x06, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x33, 0x2e,
+	0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x2e, 0x43,
 	0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65,
-	0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61, 0x6d, 0x65, 0x74, 0x65, 0x72, 0x44,
-	0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x12, 0x0a, 0x04, 0x6e, 0x61, 0x6d,
-	0x65, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x12, 0x14, 0x0a,
-	0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x18, 0x02, 0x20, 0x01, 0x28, 0x09, 0x52, 0x05, 0x74, 0x69,
-	0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69,
-	0x6f, 0x6e, 0x18, 0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b, 0x64, 0x65, 0x73, 0x63, 0x72, 0x69,
-	0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x1a, 0x0a, 0x08, 0x72, 0x65, 0x71, 0x75, 0x69, 0x72, 0x65,
-	0x64, 0x18, 0x04, 0x20, 0x01, 0x28, 0x08, 0x52, 0x08, 0x72, 0x65, 0x71, 0x75, 0x69, 0x72, 0x65,
-	0x64, 0x12, 0x12, 0x0a, 0x04, 0x74, 0x79, 0x70, 0x65, 0x18, 0x05, 0x20, 0x01, 0x28, 0x09, 0x52,
-	0x04, 0x74, 0x79, 0x70, 0x65, 0x12, 0x2e, 0x0a, 0x07, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74,
-	0x18, 0x06, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x14, 0x2e, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x2e,
-	0x70, 0x72, 0x6f, 0x74, 0x6f, 0x62, 0x75, 0x66, 0x2e, 0x41, 0x6e, 0x79, 0x52, 0x07, 0x64, 0x65,
-	0x66, 0x61, 0x75, 0x6c, 0x74, 0x42, 0xe4, 0x01, 0x0a, 0x12, 0x63, 0x6f, 0x6d, 0x2e, 0x6f, 0x73,
-	0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x42, 0x20, 0x43, 0x6f,
-	0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d,
-	0x70, 0x6c, 0x61, 0x74, 0x65, 0x54, 0x79, 0x70, 0x65, 0x50, 0x72, 0x6f, 0x74, 0x6f, 0x50, 0x01,
-	0x5a, 0x50, 0x67, 0x69, 0x74, 0x68, 0x75, 0x62, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x6f, 0x73, 0x61,
-	0x63, 0x2d, 0x70, 0x72, 0x6f, 0x6a, 0x65, 0x63, 0x74, 0x2f, 0x66, 0x75, 0x6c, 0x66, 0x69, 0x6c,
-	0x6c, 0x6d, 0x65, 0x6e, 0x74, 0x2d, 0x73, 0x65, 0x72, 0x76, 0x69, 0x63, 0x65, 0x2f, 0x69, 0x6e,
-	0x74, 0x65, 0x72, 0x6e, 0x61, 0x6c, 0x2f, 0x61, 0x70, 0x69, 0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2f,
-	0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2f, 0x76, 0x31, 0x3b, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63,
-	0x76, 0x31, 0xa2, 0x02, 0x03, 0x4f, 0x50, 0x58, 0xaa, 0x02, 0x0e, 0x4f, 0x73, 0x61, 0x63, 0x2e,
-	0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x56, 0x31, 0xca, 0x02, 0x0f, 0x4f, 0x73, 0x61, 0x63,
-	0x5c, 0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x5f, 0x5c, 0x56, 0x31, 0xe2, 0x02, 0x1b, 0x4f, 0x73,
-	0x61, 0x63, 0x5c, 0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x5f, 0x5c, 0x56, 0x31, 0x5c, 0x47, 0x50,
-	0x42, 0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0xea, 0x02, 0x10, 0x4f, 0x73, 0x61, 0x63,
-	0x3a, 0x3a, 0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x3a, 0x3a, 0x56, 0x31, 0x62, 0x06, 0x70, 0x72,
-	0x6f, 0x74, 0x6f, 0x33,
+	0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x53, 0x70, 0x65, 0x63, 0x44, 0x65, 0x66, 0x61, 0x75, 0x6c,
+	0x74, 0x73, 0x52, 0x0c, 0x73, 0x70, 0x65, 0x63, 0x44, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x73,
+	0x22, 0xd8, 0x01, 0x0a, 0x2a, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74,
+	0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x50, 0x61, 0x72, 0x61,
+	0x6d, 0x65, 0x74, 0x65, 0x72, 0x44, 0x65, 0x66, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x6f, 0x6e, 0x12,
+	0x12, 0x0a, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x6e,
+	0x61, 0x6d, 0x65, 0x12, 0x14, 0x0a, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x18, 0x02, 0x20, 0x01,
+	0x28, 0x09, 0x52, 0x05, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x12, 0x20, 0x0a, 0x0b, 0x64, 0x65, 0x73,
+	0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b,
+	0x64, 0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x1a, 0x0a, 0x08, 0x72,
+	0x65, 0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x18, 0x04, 0x20, 0x01, 0x28, 0x08, 0x52, 0x08, 0x72,
+	0x65, 0x71, 0x75, 0x69, 0x72, 0x65, 0x64, 0x12, 0x12, 0x0a, 0x04, 0x74, 0x79, 0x70, 0x65, 0x18,
+	0x05, 0x20, 0x01, 0x28, 0x09, 0x52, 0x04, 0x74, 0x79, 0x70, 0x65, 0x12, 0x2e, 0x0a, 0x07, 0x64,
+	0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x18, 0x06, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x14, 0x2e, 0x67,
+	0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x62, 0x75, 0x66, 0x2e, 0x41,
+	0x6e, 0x79, 0x52, 0x07, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x22, 0xd6, 0x02, 0x0a, 0x23,
+	0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54,
+	0x65, 0x6d, 0x70, 0x6c, 0x61, 0x74, 0x65, 0x53, 0x70, 0x65, 0x63, 0x44, 0x65, 0x66, 0x61, 0x75,
+	0x6c, 0x74, 0x73, 0x12, 0x19, 0x0a, 0x05, 0x63, 0x6f, 0x72, 0x65, 0x73, 0x18, 0x01, 0x20, 0x01,
+	0x28, 0x05, 0x48, 0x00, 0x52, 0x05, 0x63, 0x6f, 0x72, 0x65, 0x73, 0x88, 0x01, 0x01, 0x12, 0x22,
+	0x0a, 0x0a, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x5f, 0x67, 0x69, 0x62, 0x18, 0x02, 0x20, 0x01,
+	0x28, 0x05, 0x48, 0x01, 0x52, 0x09, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x47, 0x69, 0x62, 0x88,
+	0x01, 0x01, 0x12, 0x3f, 0x0a, 0x05, 0x69, 0x6d, 0x61, 0x67, 0x65, 0x18, 0x03, 0x20, 0x01, 0x28,
+	0x0b, 0x32, 0x24, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e,
+	0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e,
+	0x63, 0x65, 0x49, 0x6d, 0x61, 0x67, 0x65, 0x48, 0x02, 0x52, 0x05, 0x69, 0x6d, 0x61, 0x67, 0x65,
+	0x88, 0x01, 0x01, 0x12, 0x45, 0x0a, 0x09, 0x62, 0x6f, 0x6f, 0x74, 0x5f, 0x64, 0x69, 0x73, 0x6b,
+	0x18, 0x04, 0x20, 0x01, 0x28, 0x0b, 0x32, 0x23, 0x2e, 0x6f, 0x73, 0x61, 0x63, 0x2e, 0x70, 0x75,
+	0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x2e, 0x43, 0x6f, 0x6d, 0x70, 0x75, 0x74, 0x65, 0x49,
+	0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x44, 0x69, 0x73, 0x6b, 0x48, 0x03, 0x52, 0x08, 0x62,
+	0x6f, 0x6f, 0x74, 0x44, 0x69, 0x73, 0x6b, 0x88, 0x01, 0x01, 0x12, 0x26, 0x0a, 0x0c, 0x72, 0x75,
+	0x6e, 0x5f, 0x73, 0x74, 0x72, 0x61, 0x74, 0x65, 0x67, 0x79, 0x18, 0x05, 0x20, 0x01, 0x28, 0x09,
+	0x48, 0x04, 0x52, 0x0b, 0x72, 0x75, 0x6e, 0x53, 0x74, 0x72, 0x61, 0x74, 0x65, 0x67, 0x79, 0x88,
+	0x01, 0x01, 0x42, 0x08, 0x0a, 0x06, 0x5f, 0x63, 0x6f, 0x72, 0x65, 0x73, 0x42, 0x0d, 0x0a, 0x0b,
+	0x5f, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x5f, 0x67, 0x69, 0x62, 0x42, 0x08, 0x0a, 0x06, 0x5f,
+	0x69, 0x6d, 0x61, 0x67, 0x65, 0x42, 0x0c, 0x0a, 0x0a, 0x5f, 0x62, 0x6f, 0x6f, 0x74, 0x5f, 0x64,
+	0x69, 0x73, 0x6b, 0x42, 0x0f, 0x0a, 0x0d, 0x5f, 0x72, 0x75, 0x6e, 0x5f, 0x73, 0x74, 0x72, 0x61,
+	0x74, 0x65, 0x67, 0x79, 0x42, 0xe4, 0x01, 0x0a, 0x12, 0x63, 0x6f, 0x6d, 0x2e, 0x6f, 0x73, 0x61,
+	0x63, 0x2e, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x76, 0x31, 0x42, 0x20, 0x43, 0x6f, 0x6d,
+	0x70, 0x75, 0x74, 0x65, 0x49, 0x6e, 0x73, 0x74, 0x61, 0x6e, 0x63, 0x65, 0x54, 0x65, 0x6d, 0x70,
+	0x6c, 0x61, 0x74, 0x65, 0x54, 0x79, 0x70, 0x65, 0x50, 0x72, 0x6f, 0x74, 0x6f, 0x50, 0x01, 0x5a,
+	0x50, 0x67, 0x69, 0x74, 0x68, 0x75, 0x62, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x6f, 0x73, 0x61, 0x63,
+	0x2d, 0x70, 0x72, 0x6f, 0x6a, 0x65, 0x63, 0x74, 0x2f, 0x66, 0x75, 0x6c, 0x66, 0x69, 0x6c, 0x6c,
+	0x6d, 0x65, 0x6e, 0x74, 0x2d, 0x73, 0x65, 0x72, 0x76, 0x69, 0x63, 0x65, 0x2f, 0x69, 0x6e, 0x74,
+	0x65, 0x72, 0x6e, 0x61, 0x6c, 0x2f, 0x61, 0x70, 0x69, 0x2f, 0x6f, 0x73, 0x61, 0x63, 0x2f, 0x70,
+	0x75, 0x62, 0x6c, 0x69, 0x63, 0x2f, 0x76, 0x31, 0x3b, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x76,
+	0x31, 0xa2, 0x02, 0x03, 0x4f, 0x50, 0x58, 0xaa, 0x02, 0x0e, 0x4f, 0x73, 0x61, 0x63, 0x2e, 0x50,
+	0x75, 0x62, 0x6c, 0x69, 0x63, 0x2e, 0x56, 0x31, 0xca, 0x02, 0x0f, 0x4f, 0x73, 0x61, 0x63, 0x5c,
+	0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x5f, 0x5c, 0x56, 0x31, 0xe2, 0x02, 0x1b, 0x4f, 0x73, 0x61,
+	0x63, 0x5c, 0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x5f, 0x5c, 0x56, 0x31, 0x5c, 0x47, 0x50, 0x42,
+	0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0xea, 0x02, 0x10, 0x4f, 0x73, 0x61, 0x63, 0x3a,
+	0x3a, 0x50, 0x75, 0x62, 0x6c, 0x69, 0x63, 0x3a, 0x3a, 0x56, 0x31, 0x62, 0x06, 0x70, 0x72, 0x6f,
+	0x74, 0x6f, 0x33,
 })
 
-var file_osac_public_v1_compute_instance_template_type_proto_msgTypes = make([]protoimpl.MessageInfo, 2)
+var file_osac_public_v1_compute_instance_template_type_proto_msgTypes = make([]protoimpl.MessageInfo, 3)
 var file_osac_public_v1_compute_instance_template_type_proto_goTypes = []any{
 	(*ComputeInstanceTemplate)(nil),                    // 0: osac.public.v1.ComputeInstanceTemplate
 	(*ComputeInstanceTemplateParameterDefinition)(nil), // 1: osac.public.v1.ComputeInstanceTemplateParameterDefinition
-	(*Metadata)(nil),                                   // 2: osac.public.v1.Metadata
-	(*anypb.Any)(nil),                                  // 3: google.protobuf.Any
+	(*ComputeInstanceTemplateSpecDefaults)(nil),        // 2: osac.public.v1.ComputeInstanceTemplateSpecDefaults
+	(*Metadata)(nil),             // 3: osac.public.v1.Metadata
+	(*anypb.Any)(nil),            // 4: google.protobuf.Any
+	(*ComputeInstanceImage)(nil), // 5: osac.public.v1.ComputeInstanceImage
+	(*ComputeInstanceDisk)(nil),  // 6: osac.public.v1.ComputeInstanceDisk
 }
 var file_osac_public_v1_compute_instance_template_type_proto_depIdxs = []int32{
-	2, // 0: osac.public.v1.ComputeInstanceTemplate.metadata:type_name -> osac.public.v1.Metadata
+	3, // 0: osac.public.v1.ComputeInstanceTemplate.metadata:type_name -> osac.public.v1.Metadata
 	1, // 1: osac.public.v1.ComputeInstanceTemplate.parameters:type_name -> osac.public.v1.ComputeInstanceTemplateParameterDefinition
-	3, // 2: osac.public.v1.ComputeInstanceTemplateParameterDefinition.default:type_name -> google.protobuf.Any
-	3, // [3:3] is the sub-list for method output_type
-	3, // [3:3] is the sub-list for method input_type
-	3, // [3:3] is the sub-list for extension type_name
-	3, // [3:3] is the sub-list for extension extendee
-	0, // [0:3] is the sub-list for field type_name
+	2, // 2: osac.public.v1.ComputeInstanceTemplate.spec_defaults:type_name -> osac.public.v1.ComputeInstanceTemplateSpecDefaults
+	4, // 3: osac.public.v1.ComputeInstanceTemplateParameterDefinition.default:type_name -> google.protobuf.Any
+	5, // 4: osac.public.v1.ComputeInstanceTemplateSpecDefaults.image:type_name -> osac.public.v1.ComputeInstanceImage
+	6, // 5: osac.public.v1.ComputeInstanceTemplateSpecDefaults.boot_disk:type_name -> osac.public.v1.ComputeInstanceDisk
+	6, // [6:6] is the sub-list for method output_type
+	6, // [6:6] is the sub-list for method input_type
+	6, // [6:6] is the sub-list for extension type_name
+	6, // [6:6] is the sub-list for extension extendee
+	0, // [0:6] is the sub-list for field type_name
 }
 
 func init() { file_osac_public_v1_compute_instance_template_type_proto_init() }
@@ -426,14 +685,16 @@ func file_osac_public_v1_compute_instance_template_type_proto_init() {
 	if File_osac_public_v1_compute_instance_template_type_proto != nil {
 		return
 	}
+	file_osac_public_v1_compute_instance_type_proto_init()
 	file_osac_public_v1_metadata_type_proto_init()
+	file_osac_public_v1_compute_instance_template_type_proto_msgTypes[2].OneofWrappers = []any{}
 	type x struct{}
 	out := protoimpl.TypeBuilder{
 		File: protoimpl.DescBuilder{
 			GoPackagePath: reflect.TypeOf(x{}).PkgPath(),
 			RawDescriptor: unsafe.Slice(unsafe.StringData(file_osac_public_v1_compute_instance_template_type_proto_rawDesc), len(file_osac_public_v1_compute_instance_template_type_proto_rawDesc)),
 			NumEnums:      0,
-			NumMessages:   2,
+			NumMessages:   3,
 			NumExtensions: 0,
 			NumServices:   0,
 		},
diff --git a/internal/servers/compute_instances_server_test.go b/internal/servers/compute_instances_server_test.go
index 456ba914..db362476 100644
--- a/internal/servers/compute_instances_server_test.go
+++ b/internal/servers/compute_instances_server_test.go
@@ -172,6 +172,18 @@ var _ = Describe("Compute instances server", func() {
 						Default:     memoryDefault,
 					},
 				},
+				SpecDefaults: privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+					Cores:     proto.Int32(2),
+					MemoryGib: proto.Int32(2),
+					Image: privatev1.ComputeInstanceImage_builder{
+						SourceType: "registry",
+						SourceRef:  "quay.io/containerdisks/fedora:latest",
+					}.Build(),
+					BootDisk: privatev1.ComputeInstanceDisk_builder{
+						SizeGib: 10,
+					}.Build(),
+					RunStrategy: proto.String("Always"),
+				}.Build(),
 			}.Build()
 
 			_, err = templatesDao.Create().SetObject(template).Do(ctx)
@@ -480,5 +492,33 @@ var _ = Describe("Compute instances server", func() {
 			Expect(err).To(HaveOccurred())
 			Expect(response).To(BeNil())
 		})
+
+		It("User-provided values survive public-to-private mapping, missing fields filled from template", func() {
+			createTemplate("mapping-template")
+
+			// Create with some user-provided fields and let template cover the rest for validation:
+			response, err := server.Create(ctx, publicv1.ComputeInstancesCreateRequest_builder{
+				Object: publicv1.ComputeInstance_builder{
+					Spec: publicv1.ComputeInstanceSpec_builder{
+						Template:    "mapping-template",
+						Cores:       proto.Int32(8),
+						MemoryGib:   proto.Int32(16),
+						RunStrategy: proto.String("Halted"),
+					}.Build(),
+				}.Build(),
+			}.Build())
+			Expect(err).ToNot(HaveOccurred())
+			Expect(response).ToNot(BeNil())
+
+			spec := response.GetObject().GetSpec()
+			// User-provided values preserved through mapping:
+			Expect(spec.GetCores()).To(Equal(int32(8)))
+			Expect(spec.GetMemoryGib()).To(Equal(int32(16)))
+			Expect(spec.GetRunStrategy()).To(Equal("Halted"))
+			// Template defaults should be stored:
+			Expect(spec.GetImage().GetSourceType()).To(Equal("registry"))
+			Expect(spec.GetImage().GetSourceRef()).To(Equal("quay.io/containerdisks/fedora:latest"))
+			Expect(spec.GetBootDisk().GetSizeGib()).To(Equal(int32(10)))
+		})
 	})
 })
diff --git a/internal/servers/private_compute_instances_server.go b/internal/servers/private_compute_instances_server.go
index 2edd61e0..d0997fd7 100644
--- a/internal/servers/private_compute_instances_server.go
+++ b/internal/servers/private_compute_instances_server.go
@@ -19,9 +19,14 @@ import (
 	"log/slog"
 	"strings"
 
+	"maps"
+
 	"github.com/prometheus/client_golang/prometheus"
+
 	grpccodes "google.golang.org/grpc/codes"
 	grpcstatus "google.golang.org/grpc/status"
+	"google.golang.org/protobuf/proto"
+	"google.golang.org/protobuf/types/known/anypb"
 	"google.golang.org/protobuf/types/known/fieldmaskpb"
 
 	privatev1 "github.com/osac-project/fulfillment-service/internal/api/osac/private/v1"
@@ -167,8 +172,14 @@ func (s *PrivateComputeInstancesServer) Create(ctx context.Context,
 		return
 	}
 
-	// Validate template:
-	err = s.validateTemplate(ctx, request.GetObject())
+	// Fetch and validate template:
+	template, err := s.fetchAndValidateTemplate(ctx, request.GetObject())
+	if err != nil {
+		return
+	}
+
+	// Apply template spec defaults and validate that all required spec fields are present.
+	err = s.applySpecDefaults(request.GetObject().GetSpec(), template)
 	if err != nil {
 		return
 	}
@@ -188,11 +199,9 @@ func (s *PrivateComputeInstancesServer) Update(ctx context.Context,
 			return
 		}
 	}
-	if hasMaskPrefix(mask, "spec.template", "spec.template_parameters") {
-		err = s.validateTemplate(ctx, request.GetObject())
-		if err != nil {
-			return
-		}
+	err = s.validateTemplateImmutability(ctx, request)
+	if err != nil {
+		return
 	}
 
 	err = s.generic.Update(ctx, request, &response)
@@ -211,61 +220,139 @@ func (s *PrivateComputeInstancesServer) Signal(ctx context.Context,
 	return
 }
 
-// validateTemplate validates the template ID and parameters in the compute instance spec.
-func (s *PrivateComputeInstancesServer) validateTemplate(ctx context.Context, vm *privatev1.ComputeInstance) error {
+// fetchAndValidateTemplate fetches the template, validates parameters in the compute instance spec,
+// applies template parameter defaults, and returns the template.
+func (s *PrivateComputeInstancesServer) fetchAndValidateTemplate(ctx context.Context, vm *privatev1.ComputeInstance) (*privatev1.ComputeInstanceTemplate, error) {
 	if vm == nil {
-		return grpcstatus.Errorf(grpccodes.InvalidArgument, "compute instance is mandatory")
+		return nil, grpcstatus.Errorf(grpccodes.InvalidArgument, "compute instance is mandatory")
 	}
 
 	spec := vm.GetSpec()
 	if spec == nil {
-		return grpcstatus.Errorf(grpccodes.InvalidArgument, "compute instance spec is mandatory")
+		return nil, grpcstatus.Errorf(grpccodes.InvalidArgument, "compute instance spec is mandatory")
+	}
+
+	template, err := s.fetchTemplate(ctx, spec.GetTemplate())
+	if err != nil {
+		return nil, err
 	}
 
-	templateID := spec.GetTemplate()
+	// Validate template parameters:
+	vmParameters := spec.GetTemplateParameters()
+	err = utils.ValidateComputeInstanceTemplateParameters(template, vmParameters)
+	if err != nil {
+		return nil, err
+	}
+
+	// Set default values for template parameters:
+	actualVmParameters := utils.ProcessTemplateParametersWithDefaults(
+		utils.ComputeInstanceTemplateAdapter{ComputeInstanceTemplate: template},
+		vmParameters,
+	)
+	spec.SetTemplateParameters(actualVmParameters)
+
+	return template, nil
+}
+
+// fetchTemplate fetches a compute instance template
+func (s *PrivateComputeInstancesServer) fetchTemplate(ctx context.Context, templateID string) (*privatev1.ComputeInstanceTemplate, error) {
 	if templateID == "" {
-		return grpcstatus.Errorf(grpccodes.InvalidArgument, "template ID is mandatory")
+		return nil, grpcstatus.Errorf(grpccodes.InvalidArgument, "template ID is mandatory")
 	}
 
-	// Get the template:
 	getTemplateResponse, err := s.templatesDao.Get().
 		SetId(templateID).
 		Do(ctx)
 	if err != nil {
+		var notFoundErr *dao.ErrNotFound
+		if errors.As(err, &notFoundErr) {
+			return nil, grpcstatus.Errorf(grpccodes.InvalidArgument,
+				"template '%s' does not exist", templateID)
+		}
 		s.logger.ErrorContext(
 			ctx,
 			"Template retrieval failed",
 			slog.String("template_id", templateID),
 			slog.Any("error", err),
 		)
-		return grpcstatus.Errorf(
+		return nil, grpcstatus.Errorf(
 			grpccodes.Internal,
 			"failed to retrieve template '%s'",
 			templateID,
 		)
 	}
+
 	template := getTemplateResponse.GetObject()
 	if template == nil {
-		return grpcstatus.Errorf(
+		return nil, grpcstatus.Errorf(
 			grpccodes.InvalidArgument,
 			"template '%s' does not exist",
 			templateID,
 		)
 	}
+	return template, nil
+}
 
-	// Validate template parameters:
-	vmParameters := spec.GetTemplateParameters()
-	err = utils.ValidateComputeInstanceTemplateParameters(template, vmParameters)
+// applySpecDefaults applies template spec defaults to the spec in place and validates
+// that all required fields are present. User-provided values are never overridden.
+func (s *PrivateComputeInstancesServer) applySpecDefaults(
+	spec *privatev1.ComputeInstanceSpec,
+	template *privatev1.ComputeInstanceTemplate,
+) error {
+	utils.ApplySpecDefaults(spec, template.GetSpecDefaults())
+	return utils.ValidateRequiredSpecFields(spec)
+}
+
+// validateTemplateImmutability ensures that the template and template_parameters fields
+// cannot be changed after compute instance creation.
+func (s *PrivateComputeInstancesServer) validateTemplateImmutability(ctx context.Context,
+	request *privatev1.ComputeInstancesUpdateRequest) error {
+	updateMask := request.GetUpdateMask()
+	updatingTemplate := hasMaskPrefix(updateMask, "spec.template")
+	updatingTemplateParams := hasMaskPrefix(updateMask, "spec.template_parameters")
+
+	if !updatingTemplate && !updatingTemplateParams {
+		return nil
+	}
+
+	ci := request.GetObject()
+	if ci == nil {
+		return grpcstatus.Errorf(grpccodes.InvalidArgument, "compute instance is mandatory")
+	}
+	id := ci.GetId()
+	if id == "" {
+		return grpcstatus.Errorf(grpccodes.InvalidArgument, "compute instance id is mandatory")
+	}
+
+	getResponse, err := s.generic.dao.Get().SetId(id).Do(ctx)
 	if err != nil {
 		return err
 	}
+	existingCI := getResponse.GetObject()
 
-	// Set default values for template parameters:
-	actualVmParameters := utils.ProcessTemplateParametersWithDefaults(
-		utils.ComputeInstanceTemplateAdapter{ComputeInstanceTemplate: template},
-		vmParameters,
-	)
-	spec.SetTemplateParameters(actualVmParameters)
+	existingSpec := existingCI.GetSpec()
+	newSpec := request.GetObject().GetSpec()
+
+	if updatingTemplate && existingSpec.GetTemplate() != newSpec.GetTemplate() {
+		return grpcstatus.Errorf(
+			grpccodes.InvalidArgument,
+			"cannot change spec.template from '%s' to '%s': template is immutable",
+			existingSpec.GetTemplate(),
+			newSpec.GetTemplate(),
+		)
+	}
+
+	if updatingTemplateParams {
+		templateParamsEqual := func(first, second *anypb.Any) bool {
+			return proto.Equal(first, second)
+		}
+		if !maps.EqualFunc(existingSpec.GetTemplateParameters(), newSpec.GetTemplateParameters(), templateParamsEqual) {
+			return grpcstatus.Errorf(
+				grpccodes.InvalidArgument,
+				"cannot change spec.template_parameters: template parameters are immutable",
+			)
+		}
+	}
 
 	return nil
 }
diff --git a/internal/servers/private_compute_instances_server_test.go b/internal/servers/private_compute_instances_server_test.go
index 3701d001..d41cbea8 100644
--- a/internal/servers/private_compute_instances_server_test.go
+++ b/internal/servers/private_compute_instances_server_test.go
@@ -281,6 +281,18 @@ var _ = Describe("Private compute instances server", func() {
 						Default:     memoryDefault,
 					},
 				},
+				SpecDefaults: privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+					Cores:     proto.Int32(2),
+					MemoryGib: proto.Int32(2),
+					Image: privatev1.ComputeInstanceImage_builder{
+						SourceType: "registry",
+						SourceRef:  "quay.io/containerdisks/fedora:latest",
+					}.Build(),
+					BootDisk: privatev1.ComputeInstanceDisk_builder{
+						SizeGib: 10,
+					}.Build(),
+					RunStrategy: proto.String("Always"),
+				}.Build(),
 			}.Build()
 
 			_, err = templatesDao.Create().SetObject(template).Do(ctx)
@@ -445,9 +457,8 @@ var _ = Describe("Private compute instances server", func() {
 		})
 
 		It("Updates object", func() {
-			// Create templates first
+			// Create a template first
 			createTemplate("general.small")
-			createTemplate("general.large")
 
 			// Create an object:
 			createResponse, err := server.Create(ctx, privatev1.ComputeInstancesCreateRequest_builder{
@@ -467,19 +478,16 @@ var _ = Describe("Private compute instances server", func() {
 			id := createdObject.GetId()
 			Expect(id).ToNot(BeEmpty())
 
-			// Update the object:
+			// Update the object (only status, template is immutable):
 			updateResponse, err := server.Update(ctx, privatev1.ComputeInstancesUpdateRequest_builder{
 				Object: privatev1.ComputeInstance_builder{
 					Id: id,
-					Spec: privatev1.ComputeInstanceSpec_builder{
-						Template: "general.large",
-					}.Build(),
 					Status: privatev1.ComputeInstanceStatus_builder{
 						State: privatev1.ComputeInstanceState_COMPUTE_INSTANCE_STATE_RUNNING,
 					}.Build(),
 				}.Build(),
 				UpdateMask: &fieldmaskpb.FieldMask{
-					Paths: []string{"spec.template", "status.state"},
+					Paths: []string{"status.state"},
 				},
 			}.Build())
 			Expect(err).ToNot(HaveOccurred())
@@ -487,7 +495,7 @@ var _ = Describe("Private compute instances server", func() {
 			object := updateResponse.GetObject()
 			Expect(object).ToNot(BeNil())
 			Expect(object.GetId()).To(Equal(id))
-			Expect(object.GetSpec().GetTemplate()).To(Equal("general.large"))
+			Expect(object.GetSpec().GetTemplate()).To(Equal("general.small"))
 			Expect(object.GetStatus().GetState()).To(Equal(privatev1.ComputeInstanceState_COMPUTE_INSTANCE_STATE_RUNNING))
 		})
 
@@ -581,8 +589,7 @@ var _ = Describe("Private compute instances server", func() {
 			Expect(response).To(BeNil())
 		})
 
-		It("Validates template exists on update", func() {
-			// Create a template and compute instance first:
+		It("Rejects changing template on update", func() {
 			createTemplate("existing-template")
 
 			createResponse, err := server.Create(ctx, privatev1.ComputeInstancesCreateRequest_builder{
@@ -600,15 +607,12 @@ var _ = Describe("Private compute instances server", func() {
 
 			id := createResponse.GetObject().GetId()
 
-			// Try to update with non-existent template:
+			// Try to change the template:
 			updateResponse, err := server.Update(ctx, privatev1.ComputeInstancesUpdateRequest_builder{
 				Object: privatev1.ComputeInstance_builder{
 					Id: id,
 					Spec: privatev1.ComputeInstanceSpec_builder{
-						Template: "non-existent-template",
-					}.Build(),
-					Status: privatev1.ComputeInstanceStatus_builder{
-						State: privatev1.ComputeInstanceState_COMPUTE_INSTANCE_STATE_STARTING,
+						Template: "different-template",
 					}.Build(),
 				}.Build(),
 				UpdateMask: &fieldmaskpb.FieldMask{
@@ -617,6 +621,93 @@ var _ = Describe("Private compute instances server", func() {
 			}.Build())
 			Expect(err).To(HaveOccurred())
 			Expect(updateResponse).To(BeNil())
+			status, ok := grpcstatus.FromError(err)
+			Expect(ok).To(BeTrue())
+			Expect(status.Code()).To(Equal(grpccodes.InvalidArgument))
+			Expect(status.Message()).To(ContainSubstring("template is immutable"))
+		})
+
+		It("Rejects changing template_parameters on update", func() {
+			createTemplate("params-template")
+
+			// Create with initial parameters:
+			cpuParam, err := anypb.New(wrapperspb.Int32(2))
+			Expect(err).ToNot(HaveOccurred())
+
+			createResponse, err := server.Create(ctx, privatev1.ComputeInstancesCreateRequest_builder{
+				Object: privatev1.ComputeInstance_builder{
+					Spec: privatev1.ComputeInstanceSpec_builder{
+						Template:           "params-template",
+						TemplateParameters: map[string]*anypb.Any{"cpu_count": cpuParam},
+					}.Build(),
+				}.Build(),
+			}.Build())
+			Expect(err).ToNot(HaveOccurred())
+			Expect(createResponse).ToNot(BeNil())
+
+			id := createResponse.GetObject().GetId()
+
+			// Try to change template_parameters:
+			newCpuParam, err := anypb.New(wrapperspb.Int32(8))
+			Expect(err).ToNot(HaveOccurred())
+
+			updateResponse, err := server.Update(ctx, privatev1.ComputeInstancesUpdateRequest_builder{
+				Object: privatev1.ComputeInstance_builder{
+					Id: id,
+					Spec: privatev1.ComputeInstanceSpec_builder{
+						Template:           "params-template",
+						TemplateParameters: map[string]*anypb.Any{"cpu_count": newCpuParam},
+					}.Build(),
+				}.Build(),
+				UpdateMask: &fieldmaskpb.FieldMask{
+					Paths: []string{"spec.template_parameters"},
+				},
+			}.Build())
+			Expect(err).To(HaveOccurred())
+			Expect(updateResponse).To(BeNil())
+			status, ok := grpcstatus.FromError(err)
+			Expect(ok).To(BeTrue())
+			Expect(status.Code()).To(Equal(grpccodes.InvalidArgument))
+			Expect(status.Message()).To(ContainSubstring("template parameters are immutable"))
+		})
+
+		It("Allows update when template in mask but unchanged", func() {
+			createTemplate("same-template")
+
+			createResponse, err := server.Create(ctx, privatev1.ComputeInstancesCreateRequest_builder{
+				Object: privatev1.ComputeInstance_builder{
+					Spec: privatev1.ComputeInstanceSpec_builder{
+						Template: "same-template",
+					}.Build(),
+					Status: privatev1.ComputeInstanceStatus_builder{
+						State: privatev1.ComputeInstanceState_COMPUTE_INSTANCE_STATE_STARTING,
+					}.Build(),
+				}.Build(),
+			}.Build())
+			Expect(err).ToNot(HaveOccurred())
+			Expect(createResponse).ToNot(BeNil())
+
+			id := createResponse.GetObject().GetId()
+
+			// Update with template in mask but same value:
+			updateResponse, err := server.Update(ctx, privatev1.ComputeInstancesUpdateRequest_builder{
+				Object: privatev1.ComputeInstance_builder{
+					Id: id,
+					Spec: privatev1.ComputeInstanceSpec_builder{
+						Template: "same-template",
+					}.Build(),
+					Status: privatev1.ComputeInstanceStatus_builder{
+						State: privatev1.ComputeInstanceState_COMPUTE_INSTANCE_STATE_RUNNING,
+					}.Build(),
+				}.Build(),
+				UpdateMask: &fieldmaskpb.FieldMask{
+					Paths: []string{"spec.template", "status.state"},
+				},
+			}.Build())
+			Expect(err).ToNot(HaveOccurred())
+			Expect(updateResponse).ToNot(BeNil())
+			Expect(updateResponse.GetObject().GetSpec().GetTemplate()).To(Equal("same-template"))
+			Expect(updateResponse.GetObject().GetStatus().GetState()).To(Equal(privatev1.ComputeInstanceState_COMPUTE_INSTANCE_STATE_RUNNING))
 		})
 
 		It("Validates template ID is not empty", func() {
@@ -634,6 +725,195 @@ var _ = Describe("Private compute instances server", func() {
 			Expect(err).To(HaveOccurred())
 			Expect(response).To(BeNil())
 		})
+
+		It("Applies template spec defaults when user omits spec fields", func() {
+			createTemplate("defaults-template")
+
+			// Create a compute instance without any spec fields — validation should pass
+			// because template defaults cover all required fields.
+			response, err := server.Create(ctx, privatev1.ComputeInstancesCreateRequest_builder{
+				Object: privatev1.ComputeInstance_builder{
+					Spec: privatev1.ComputeInstanceSpec_builder{
+						Template: "defaults-template",
+					}.Build(),
+				}.Build(),
+			}.Build())
+			Expect(err).ToNot(HaveOccurred())
+			Expect(response).ToNot(BeNil())
+
+			spec := response.GetObject().GetSpec()
+			// Template defaults should be stored:
+			Expect(spec.GetCores()).To(Equal(int32(2)))
+			Expect(spec.GetMemoryGib()).To(Equal(int32(2)))
+			Expect(spec.GetRunStrategy()).To(Equal("Always"))
+			Expect(spec.GetImage().GetSourceType()).To(Equal("registry"))
+			Expect(spec.GetImage().GetSourceRef()).To(Equal("quay.io/containerdisks/fedora:latest"))
+			Expect(spec.GetBootDisk().GetSizeGib()).To(Equal(int32(10)))
+			// Template reference should be preserved:
+			Expect(spec.GetTemplate()).To(Equal("defaults-template"))
+		})
+
+		It("User-provided spec fields override template defaults", func() {
+			createTemplate("override-template")
+
+			// Create with user-provided cores and memory:
+			response, err := server.Create(ctx, privatev1.ComputeInstancesCreateRequest_builder{
+				Object: privatev1.ComputeInstance_builder{
+					Spec: privatev1.ComputeInstanceSpec_builder{
+						Template:    "override-template",
+						Cores:       proto.Int32(8),
+						MemoryGib:   proto.Int32(16),
+						RunStrategy: proto.String("Halted"),
+					}.Build(),
+				}.Build(),
+			}.Build())
+			Expect(err).ToNot(HaveOccurred())
+			Expect(response).ToNot(BeNil())
+
+			spec := response.GetObject().GetSpec()
+			// User-provided values should be stored:
+			Expect(spec.GetCores()).To(Equal(int32(8)))
+			Expect(spec.GetMemoryGib()).To(Equal(int32(16)))
+			Expect(spec.GetRunStrategy()).To(Equal("Halted"))
+			// Template defaults should be stored:
+			Expect(spec.GetImage().GetSourceType()).To(Equal("registry"))
+			Expect(spec.GetImage().GetSourceRef()).To(Equal("quay.io/containerdisks/fedora:latest"))
+			Expect(spec.GetBootDisk().GetSizeGib()).To(Equal(int32(10)))
+		})
+
+		It("Rejects creation when required spec fields are missing", func() {
+			// Create a template WITHOUT spec defaults:
+			templatesDao, err := dao.NewGenericDAO[*privatev1.ComputeInstanceTemplate]().
+				SetLogger(logger).
+				SetTenancyLogic(tenancy).
+				Build()
+			Expect(err).ToNot(HaveOccurred())
+
+			template := privatev1.ComputeInstanceTemplate_builder{
+				Id:          "no-defaults-template",
+				Title:       "No Defaults Template",
+				Description: "Template without spec defaults",
+				Metadata: privatev1.Metadata_builder{
+					Tenants: []string{"shared"},
+				}.Build(),
+			}.Build()
+			_, err = templatesDao.Create().SetObject(template).Do(ctx)
+			Expect(err).ToNot(HaveOccurred())
+
+			// Create a compute instance without user-provided spec fields:
+			response, err := server.Create(ctx, privatev1.ComputeInstancesCreateRequest_builder{
+				Object: privatev1.ComputeInstance_builder{
+					Spec: privatev1.ComputeInstanceSpec_builder{
+						Template: "no-defaults-template",
+					}.Build(),
+				}.Build(),
+			}.Build())
+			Expect(err).To(HaveOccurred())
+			Expect(response).To(BeNil())
+
+			status, ok := grpcstatus.FromError(err)
+			Expect(ok).To(BeTrue())
+			Expect(status.Code()).To(Equal(grpccodes.InvalidArgument))
+			Expect(status.Message()).To(ContainSubstring("boot_disk"))
+			Expect(status.Message()).To(ContainSubstring("cores"))
+			Expect(status.Message()).To(ContainSubstring("image"))
+			Expect(status.Message()).To(ContainSubstring("memory_gib"))
+			Expect(status.Message()).To(ContainSubstring("run_strategy"))
+		})
+
+		It("Accepts creation when user provides all required fields without template defaults", func() {
+			// Create a template WITHOUT spec defaults:
+			templatesDao, err := dao.NewGenericDAO[*privatev1.ComputeInstanceTemplate]().
+				SetLogger(logger).
+				SetTenancyLogic(tenancy).
+				Build()
+			Expect(err).ToNot(HaveOccurred())
+
+			template := privatev1.ComputeInstanceTemplate_builder{
+				Id:          "bare-template",
+				Title:       "Bare Template",
+				Description: "Template without defaults",
+				Metadata: privatev1.Metadata_builder{
+					Tenants: []string{"shared"},
+				}.Build(),
+			}.Build()
+			_, err = templatesDao.Create().SetObject(template).Do(ctx)
+			Expect(err).ToNot(HaveOccurred())
+
+			// Create with all required fields provided by user:
+			response, err := server.Create(ctx, privatev1.ComputeInstancesCreateRequest_builder{
+				Object: privatev1.ComputeInstance_builder{
+					Spec: privatev1.ComputeInstanceSpec_builder{
+						Template:  "bare-template",
+						Cores:     proto.Int32(4),
+						MemoryGib: proto.Int32(8),
+						Image: privatev1.ComputeInstanceImage_builder{
+							SourceType: "registry",
+							SourceRef:  "quay.io/containerdisks/fedora:latest",
+						}.Build(),
+						BootDisk: privatev1.ComputeInstanceDisk_builder{
+							SizeGib: 20,
+						}.Build(),
+						RunStrategy: proto.String("Always"),
+					}.Build(),
+				}.Build(),
+			}.Build())
+			Expect(err).ToNot(HaveOccurred())
+			Expect(response).ToNot(BeNil())
+			Expect(response.GetObject().GetSpec().GetCores()).To(Equal(int32(4)))
+		})
+
+		It("Partial defaults plus partial user input satisfies validation", func() {
+			// Create a template with only some spec defaults:
+			templatesDao, err := dao.NewGenericDAO[*privatev1.ComputeInstanceTemplate]().
+				SetLogger(logger).
+				SetTenancyLogic(tenancy).
+				Build()
+			Expect(err).ToNot(HaveOccurred())
+
+			template := privatev1.ComputeInstanceTemplate_builder{
+				Id:          "partial-defaults-template",
+				Title:       "Partial Defaults Template",
+				Description: "Template with partial spec defaults",
+				Metadata: privatev1.Metadata_builder{
+					Tenants: []string{"shared"},
+				}.Build(),
+				SpecDefaults: privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+					Cores:       proto.Int32(2),
+					MemoryGib:   proto.Int32(4),
+					RunStrategy: proto.String("Always"),
+				}.Build(),
+			}.Build()
+			_, err = templatesDao.Create().SetObject(template).Do(ctx)
+			Expect(err).ToNot(HaveOccurred())
+
+			// User provides the remaining required fields:
+			response, err := server.Create(ctx, privatev1.ComputeInstancesCreateRequest_builder{
+				Object: privatev1.ComputeInstance_builder{
+					Spec: privatev1.ComputeInstanceSpec_builder{
+						Template: "partial-defaults-template",
+						Image: privatev1.ComputeInstanceImage_builder{
+							SourceType: "registry",
+							SourceRef:  "quay.io/containerdisks/fedora:latest",
+						}.Build(),
+						BootDisk: privatev1.ComputeInstanceDisk_builder{
+							SizeGib: 20,
+						}.Build(),
+					}.Build(),
+				}.Build(),
+			}.Build())
+			Expect(err).ToNot(HaveOccurred())
+			Expect(response).ToNot(BeNil())
+
+			spec := response.GetObject().GetSpec()
+			// Template defaults should be stored:
+			Expect(spec.GetCores()).To(Equal(int32(2)))
+			Expect(spec.GetMemoryGib()).To(Equal(int32(4)))
+			Expect(spec.GetRunStrategy()).To(Equal("Always"))
+			// User-provided fields should be stored:
+			Expect(spec.GetImage().GetSourceRef()).To(Equal("quay.io/containerdisks/fedora:latest"))
+			Expect(spec.GetBootDisk().GetSizeGib()).To(Equal(int32(20)))
+		})
 	})
 
 	Describe("Network validation", func() {
@@ -688,6 +968,18 @@ var _ = Describe("Private compute instances server", func() {
 						Default:     memoryDefault,
 					},
 				},
+				SpecDefaults: privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+					Cores:     proto.Int32(2),
+					MemoryGib: proto.Int32(2),
+					Image: privatev1.ComputeInstanceImage_builder{
+						SourceType: "registry",
+						SourceRef:  "quay.io/containerdisks/fedora:latest",
+					}.Build(),
+					BootDisk: privatev1.ComputeInstanceDisk_builder{
+						SizeGib: 10,
+					}.Build(),
+					RunStrategy: proto.String("Always"),
+				}.Build(),
 			}.Build()
 
 			_, err = templatesDao.Create().SetObject(template).Do(ctx)
diff --git a/internal/testing/database.go b/internal/testing/database.go
index 8ecf1351..0f2d672e 100644
--- a/internal/testing/database.go
+++ b/internal/testing/database.go
@@ -119,7 +119,7 @@ func MakeDatabaseServer() *DatabaseServer {
 	)
 	handle, err := sql.Open("pgx", url)
 	Expect(err).ToNot(HaveOccurred())
-	Eventually(handle.Ping, 10, 1).ShouldNot(HaveOccurred())
+	Eventually(handle.Ping, 30, 1).ShouldNot(HaveOccurred())
 
 	// Create and populate the object:
 	return &DatabaseServer{
diff --git a/internal/utils/spec_defaults.go b/internal/utils/spec_defaults.go
new file mode 100644
index 00000000..435cf370
--- /dev/null
+++ b/internal/utils/spec_defaults.go
@@ -0,0 +1,175 @@
+/*
+Copyright (c) 2026 Red Hat, Inc.
+
+Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the
+License. You may obtain a copy of the License at
+
+  http://www.apache.org/licenses/LICENSE-2.0
+
+Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an
+"AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific
+language governing permissions and limitations under the License.
+*/
+
+package utils
+
+import (
+	"slices"
+	"sort"
+	"strings"
+
+	grpccodes "google.golang.org/grpc/codes"
+	grpcstatus "google.golang.org/grpc/status"
+	"google.golang.org/protobuf/proto"
+
+	privatev1 "github.com/osac-project/fulfillment-service/internal/api/osac/private/v1"
+)
+
+// validRunStrategies contains the run strategy values accepted by the Kubernetes ComputeInstance CRD.
+// Note: these values are case-sensitive as currently no normalization is performed.
+var validRunStrategies = []string{"Always", "Halted"}
+
+// ApplySpecDefaults applies default values from a template's spec_defaults to a compute instance spec.
+//
+// User-provided values have precedence over defaults, and should never be overridden by defaults.
+func ApplySpecDefaults(spec *privatev1.ComputeInstanceSpec, defaults *privatev1.ComputeInstanceTemplateSpecDefaults) {
+	if spec == nil || defaults == nil {
+		return
+	}
+	if !spec.HasCores() && defaults.HasCores() {
+		spec.SetCores(defaults.GetCores())
+	}
+	if !spec.HasMemoryGib() && defaults.HasMemoryGib() {
+		spec.SetMemoryGib(defaults.GetMemoryGib())
+	}
+	if !spec.HasRunStrategy() && defaults.HasRunStrategy() {
+		spec.SetRunStrategy(defaults.GetRunStrategy())
+	}
+	mergeImageDefaults(spec, defaults)
+	mergeBootDiskDefaults(spec, defaults)
+}
+
+func mergeImageDefaults(spec *privatev1.ComputeInstanceSpec, defaults *privatev1.ComputeInstanceTemplateSpecDefaults) {
+	if !defaults.HasImage() {
+		return
+	}
+	if !spec.HasImage() {
+		spec.SetImage(proto.Clone(defaults.GetImage()).(*privatev1.ComputeInstanceImage))
+		return
+	}
+	img := spec.GetImage()
+	defImg := defaults.GetImage()
+	if img.GetSourceType() == "" && defImg.GetSourceType() != "" {
+		img.SetSourceType(defImg.GetSourceType())
+	}
+	if img.GetSourceRef() == "" && defImg.GetSourceRef() != "" {
+		img.SetSourceRef(defImg.GetSourceRef())
+	}
+}
+
+func mergeBootDiskDefaults(spec *privatev1.ComputeInstanceSpec, defaults *privatev1.ComputeInstanceTemplateSpecDefaults) {
+	if !defaults.HasBootDisk() {
+		return
+	}
+	if !spec.HasBootDisk() {
+		spec.SetBootDisk(proto.Clone(defaults.GetBootDisk()).(*privatev1.ComputeInstanceDisk))
+		return
+	}
+	disk := spec.GetBootDisk()
+	defDisk := defaults.GetBootDisk()
+	if disk.GetSizeGib() <= 0 && defDisk.GetSizeGib() > 0 {
+		disk.SetSizeGib(defDisk.GetSizeGib())
+	}
+}
+
+// ValidateRequiredSpecFields checks that all fields required by the Kubernetes ComputeInstance CRD
+// are present in the spec.
+func ValidateRequiredSpecFields(spec *privatev1.ComputeInstanceSpec) error {
+	if spec == nil {
+		return grpcstatus.Errorf(
+			grpccodes.InvalidArgument,
+			"compute instance spec is required",
+		)
+	}
+	var missing []string
+	if !spec.HasCores() {
+		missing = append(missing, "cores")
+	}
+	if !spec.HasMemoryGib() {
+		missing = append(missing, "memory_gib")
+	}
+	if !spec.HasImage() {
+		missing = append(missing, "image")
+	}
+	if !spec.HasBootDisk() {
+		missing = append(missing, "boot_disk")
+	}
+	if !spec.HasRunStrategy() {
+		missing = append(missing, "run_strategy")
+	}
+	if len(missing) > 0 {
+		sort.Strings(missing)
+		return grpcstatus.Errorf(
+			grpccodes.InvalidArgument,
+			"the following required spec fields are missing: %s",
+			strings.Join(missing, ", "),
+		)
+	}
+
+	if err := validateRunStrategy(spec.GetRunStrategy()); err != nil {
+		return err
+	}
+	if err := validateImage(spec.GetImage()); err != nil {
+		return err
+	}
+	if err := validateBootDisk(spec.GetBootDisk()); err != nil {
+		return err
+	}
+
+	return nil
+}
+
+func validateRunStrategy(value string) error {
+	if slices.Contains(validRunStrategies, value) {
+		return nil
+	}
+	return grpcstatus.Errorf(
+		grpccodes.InvalidArgument,
+		"invalid run_strategy %q: must be one of %s",
+		value, strings.Join(validRunStrategies, ", "),
+	)
+}
+
+func validateImage(image *privatev1.ComputeInstanceImage) error {
+	if image == nil {
+		return nil
+	}
+	var missing []string
+	if image.GetSourceType() == "" {
+		missing = append(missing, "image.source_type")
+	}
+	if image.GetSourceRef() == "" {
+		missing = append(missing, "image.source_ref")
+	}
+	if len(missing) > 0 {
+		return grpcstatus.Errorf(
+			grpccodes.InvalidArgument,
+			"the following required image fields are missing: %s",
+			strings.Join(missing, ", "),
+		)
+	}
+	return nil
+}
+
+func validateBootDisk(disk *privatev1.ComputeInstanceDisk) error {
+	if disk == nil {
+		return nil
+	}
+	if disk.GetSizeGib() <= 0 {
+		return grpcstatus.Errorf(
+			grpccodes.InvalidArgument,
+			"boot_disk.size_gib must be greater than 0",
+		)
+	}
+	return nil
+}
diff --git a/internal/utils/spec_defaults_test.go b/internal/utils/spec_defaults_test.go
new file mode 100644
index 00000000..17c0ec6d
--- /dev/null
+++ b/internal/utils/spec_defaults_test.go
@@ -0,0 +1,368 @@
+/*
+Copyright (c) 2026 Red Hat, Inc.
+
+Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the
+License. You may obtain a copy of the License at
+
+  http://www.apache.org/licenses/LICENSE-2.0
+
+Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an
+"AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific
+language governing permissions and limitations under the License.
+*/
+
+package utils
+
+import (
+	. "github.com/onsi/ginkgo/v2/dsl/core"
+	. "github.com/onsi/gomega"
+	"google.golang.org/grpc/codes"
+	"google.golang.org/grpc/status"
+	"google.golang.org/protobuf/proto"
+
+	privatev1 "github.com/osac-project/fulfillment-service/internal/api/osac/private/v1"
+)
+
+var _ = Describe("ApplySpecDefaults", func() {
+	It("Does nothing when defaults are nil", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template: "test.template",
+		}.Build()
+
+		ApplySpecDefaults(spec, nil)
+
+		Expect(spec.HasCores()).To(BeFalse())
+		Expect(spec.HasMemoryGib()).To(BeFalse())
+	})
+
+	It("Does nothing when spec is nil", func() {
+		defaults := privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+			Cores: proto.Int32(4),
+		}.Build()
+
+		ApplySpecDefaults(nil, defaults)
+	})
+
+	It("Applies all defaults to empty spec", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template: "test.template",
+		}.Build()
+
+		defaults := privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+			Cores:     proto.Int32(2),
+			MemoryGib: proto.Int32(4),
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceType: "registry",
+				SourceRef:  "quay.io/containerdisks/fedora:latest",
+			}.Build(),
+			BootDisk: privatev1.ComputeInstanceDisk_builder{
+				SizeGib: 10,
+			}.Build(),
+			RunStrategy: proto.String("Always"),
+		}.Build()
+
+		ApplySpecDefaults(spec, defaults)
+
+		Expect(spec.GetCores()).To(Equal(int32(2)))
+		Expect(spec.GetMemoryGib()).To(Equal(int32(4)))
+		Expect(spec.GetImage().GetSourceType()).To(Equal("registry"))
+		Expect(spec.GetImage().GetSourceRef()).To(Equal("quay.io/containerdisks/fedora:latest"))
+		Expect(spec.GetBootDisk().GetSizeGib()).To(Equal(int32(10)))
+		Expect(spec.GetRunStrategy()).To(Equal("Always"))
+	})
+
+	It("Does not override user-provided values", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template:    "test.template",
+			Cores:       proto.Int32(8),
+			MemoryGib:   proto.Int32(16),
+			RunStrategy: proto.String("Halted"),
+		}.Build()
+
+		defaults := privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+			Cores:     proto.Int32(2),
+			MemoryGib: proto.Int32(4),
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceType: "registry",
+				SourceRef:  "quay.io/containerdisks/fedora:latest",
+			}.Build(),
+			BootDisk: privatev1.ComputeInstanceDisk_builder{
+				SizeGib: 10,
+			}.Build(),
+			RunStrategy: proto.String("Always"),
+		}.Build()
+
+		ApplySpecDefaults(spec, defaults)
+
+		// User-provided values preserved:
+		Expect(spec.GetCores()).To(Equal(int32(8)))
+		Expect(spec.GetMemoryGib()).To(Equal(int32(16)))
+		Expect(spec.GetRunStrategy()).To(Equal("Halted"))
+		// Defaults fill the rest:
+		Expect(spec.GetImage().GetSourceRef()).To(Equal("quay.io/containerdisks/fedora:latest"))
+		Expect(spec.GetBootDisk().GetSizeGib()).To(Equal(int32(10)))
+	})
+
+	It("Applies partial defaults", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template: "test.template",
+		}.Build()
+
+		defaults := privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+			Cores:       proto.Int32(2),
+			RunStrategy: proto.String("Always"),
+		}.Build()
+
+		ApplySpecDefaults(spec, defaults)
+
+		Expect(spec.GetCores()).To(Equal(int32(2)))
+		Expect(spec.GetRunStrategy()).To(Equal("Always"))
+		Expect(spec.HasMemoryGib()).To(BeFalse())
+		Expect(spec.HasImage()).To(BeFalse())
+		Expect(spec.HasBootDisk()).To(BeFalse())
+	})
+
+	It("Merges default source_type into user-provided partial image", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template: "test.template",
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceRef: "quay.io/my-image:latest",
+			}.Build(),
+		}.Build()
+
+		defaults := privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceType: "registry",
+				SourceRef:  "quay.io/containerdisks/fedora:latest",
+			}.Build(),
+		}.Build()
+
+		ApplySpecDefaults(spec, defaults)
+
+		Expect(spec.GetImage().GetSourceType()).To(Equal("registry"))
+		Expect(spec.GetImage().GetSourceRef()).To(Equal("quay.io/my-image:latest"))
+	})
+
+	It("Merges default source_ref into user-provided partial image", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template: "test.template",
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceType: "registry",
+			}.Build(),
+		}.Build()
+
+		defaults := privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceType: "registry",
+				SourceRef:  "quay.io/containerdisks/fedora:latest",
+			}.Build(),
+		}.Build()
+
+		ApplySpecDefaults(spec, defaults)
+
+		Expect(spec.GetImage().GetSourceType()).To(Equal("registry"))
+		Expect(spec.GetImage().GetSourceRef()).To(Equal("quay.io/containerdisks/fedora:latest"))
+	})
+
+	It("Does not override user-provided image fields with defaults", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template: "test.template",
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceType: "registry",
+				SourceRef:  "quay.io/my-image:latest",
+			}.Build(),
+		}.Build()
+
+		defaults := privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceType: "registry",
+				SourceRef:  "quay.io/containerdisks/fedora:latest",
+			}.Build(),
+		}.Build()
+
+		ApplySpecDefaults(spec, defaults)
+
+		Expect(spec.GetImage().GetSourceType()).To(Equal("registry"))
+		Expect(spec.GetImage().GetSourceRef()).To(Equal("quay.io/my-image:latest"))
+	})
+
+	It("Merges default boot_disk size_gib when user provides empty boot_disk", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template: "test.template",
+			BootDisk: privatev1.ComputeInstanceDisk_builder{}.Build(),
+		}.Build()
+
+		defaults := privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+			BootDisk: privatev1.ComputeInstanceDisk_builder{
+				SizeGib: 20,
+			}.Build(),
+		}.Build()
+
+		ApplySpecDefaults(spec, defaults)
+
+		Expect(spec.GetBootDisk().GetSizeGib()).To(Equal(int32(20)))
+	})
+
+	It("Clones message-type defaults to prevent shared state", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template: "test.template",
+		}.Build()
+
+		defaultImage := privatev1.ComputeInstanceImage_builder{
+			SourceType: "registry",
+			SourceRef:  "quay.io/containerdisks/fedora:latest",
+		}.Build()
+
+		defaults := privatev1.ComputeInstanceTemplateSpecDefaults_builder{
+			Image: defaultImage,
+		}.Build()
+
+		ApplySpecDefaults(spec, defaults)
+
+		// Mutating the default should not affect the spec:
+		defaultImage.SetSourceRef("changed")
+		Expect(spec.GetImage().GetSourceRef()).To(Equal("quay.io/containerdisks/fedora:latest"))
+	})
+})
+
+var _ = Describe("ValidateRequiredSpecFields", func() {
+	It("Returns error when spec is nil", func() {
+		err := ValidateRequiredSpecFields(nil)
+		Expect(err).To(HaveOccurred())
+		Expect(status.Code(err)).To(Equal(codes.InvalidArgument))
+	})
+
+	It("Returns error listing all missing fields", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template: "test.template",
+		}.Build()
+
+		err := ValidateRequiredSpecFields(spec)
+		Expect(err).To(HaveOccurred())
+		Expect(status.Code(err)).To(Equal(codes.InvalidArgument))
+		Expect(err.Error()).To(ContainSubstring("boot_disk"))
+		Expect(err.Error()).To(ContainSubstring("cores"))
+		Expect(err.Error()).To(ContainSubstring("image"))
+		Expect(err.Error()).To(ContainSubstring("memory_gib"))
+		Expect(err.Error()).To(ContainSubstring("run_strategy"))
+	})
+
+	It("Returns error for partially missing fields", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template:    "test.template",
+			Cores:       proto.Int32(4),
+			MemoryGib:   proto.Int32(8),
+			RunStrategy: proto.String("Always"),
+		}.Build()
+
+		err := ValidateRequiredSpecFields(spec)
+		Expect(err).To(HaveOccurred())
+		Expect(status.Code(err)).To(Equal(codes.InvalidArgument))
+		Expect(err.Error()).To(ContainSubstring("boot_disk"))
+		Expect(err.Error()).To(ContainSubstring("image"))
+		Expect(err.Error()).ToNot(ContainSubstring("cores"))
+		Expect(err.Error()).ToNot(ContainSubstring("memory_gib"))
+		Expect(err.Error()).ToNot(ContainSubstring("run_strategy"))
+	})
+
+	It("Passes when all required fields are set", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template:  "test.template",
+			Cores:     proto.Int32(4),
+			MemoryGib: proto.Int32(8),
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceType: "registry",
+				SourceRef:  "quay.io/containerdisks/fedora:latest",
+			}.Build(),
+			BootDisk: privatev1.ComputeInstanceDisk_builder{
+				SizeGib: 20,
+			}.Build(),
+			RunStrategy: proto.String("Always"),
+		}.Build()
+
+		err := ValidateRequiredSpecFields(spec)
+		Expect(err).ToNot(HaveOccurred())
+	})
+
+	It("Rejects invalid run_strategy value", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template:  "test.template",
+			Cores:     proto.Int32(4),
+			MemoryGib: proto.Int32(8),
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceType: "registry",
+				SourceRef:  "quay.io/containerdisks/fedora:latest",
+			}.Build(),
+			BootDisk: privatev1.ComputeInstanceDisk_builder{
+				SizeGib: 20,
+			}.Build(),
+			RunStrategy: proto.String("always"),
+		}.Build()
+
+		err := ValidateRequiredSpecFields(spec)
+		Expect(err).To(HaveOccurred())
+		Expect(status.Code(err)).To(Equal(codes.InvalidArgument))
+		Expect(err.Error()).To(ContainSubstring("invalid run_strategy"))
+		Expect(err.Error()).To(ContainSubstring("Always"))
+		Expect(err.Error()).To(ContainSubstring("Halted"))
+	})
+
+	It("Rejects empty image fields", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template:  "test.template",
+			Cores:     proto.Int32(4),
+			MemoryGib: proto.Int32(8),
+			Image:     privatev1.ComputeInstanceImage_builder{}.Build(),
+			BootDisk: privatev1.ComputeInstanceDisk_builder{
+				SizeGib: 20,
+			}.Build(),
+			RunStrategy: proto.String("Always"),
+		}.Build()
+
+		err := ValidateRequiredSpecFields(spec)
+		Expect(err).To(HaveOccurred())
+		Expect(status.Code(err)).To(Equal(codes.InvalidArgument))
+		Expect(err.Error()).To(ContainSubstring("image.source_type"))
+		Expect(err.Error()).To(ContainSubstring("image.source_ref"))
+	})
+
+	It("Rejects image with partial fields", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template:  "test.template",
+			Cores:     proto.Int32(4),
+			MemoryGib: proto.Int32(8),
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceType: "registry",
+			}.Build(),
+			BootDisk: privatev1.ComputeInstanceDisk_builder{
+				SizeGib: 20,
+			}.Build(),
+			RunStrategy: proto.String("Always"),
+		}.Build()
+
+		err := ValidateRequiredSpecFields(spec)
+		Expect(err).To(HaveOccurred())
+		Expect(status.Code(err)).To(Equal(codes.InvalidArgument))
+		Expect(err.Error()).To(ContainSubstring("image.source_ref"))
+		Expect(err.Error()).ToNot(ContainSubstring("image.source_type"))
+	})
+
+	It("Rejects boot_disk with zero size", func() {
+		spec := privatev1.ComputeInstanceSpec_builder{
+			Template:  "test.template",
+			Cores:     proto.Int32(4),
+			MemoryGib: proto.Int32(8),
+			Image: privatev1.ComputeInstanceImage_builder{
+				SourceType: "registry",
+				SourceRef:  "quay.io/containerdisks/fedora:latest",
+			}.Build(),
+			BootDisk:    privatev1.ComputeInstanceDisk_builder{}.Build(),
+			RunStrategy: proto.String("Always"),
+		}.Build()
+
+		err := ValidateRequiredSpecFields(spec)
+		Expect(err).To(HaveOccurred())
+		Expect(status.Code(err)).To(Equal(codes.InvalidArgument))
+		Expect(err.Error()).To(ContainSubstring("boot_disk.size_gib"))
+	})
+})
diff --git a/it/it_compute_subnet_test.go b/it/it_compute_subnet_test.go
index 7b7cac9c..316275da 100644
--- a/it/it_compute_subnet_test.go
+++ b/it/it_compute_subnet_test.go
@@ -177,14 +177,16 @@ var _ = Describe("ComputeInstance with Subnet attachment", func() {
 			Object: publicv1.ComputeInstance_builder{
 				Id: computeInstanceId,
 				Spec: publicv1.ComputeInstanceSpec_builder{
-					Template:  computeInstanceTemplateId,
-					Cores:     proto.Int32(2),
-					MemoryGib: proto.Int32(4),
+					Template:    computeInstanceTemplateId,
+					Cores:       proto.Int32(2),
+					MemoryGib:   proto.Int32(4),
+					RunStrategy: proto.String("Always"),
 					BootDisk: publicv1.ComputeInstanceDisk_builder{
 						SizeGib: 20,
 					}.Build(),
 					Image: publicv1.ComputeInstanceImage_builder{
-						SourceRef: "quay.io/containerdisks/fedora:latest",
+						SourceType: "registry",
+						SourceRef:  "quay.io/containerdisks/fedora:latest",
 					}.Build(),
 					Subnet: proto.String(subnetId),
 				}.Build(),
@@ -208,14 +210,16 @@ var _ = Describe("ComputeInstance with Subnet attachment", func() {
 			Object: publicv1.ComputeInstance_builder{
 				Id: computeInstanceId,
 				Spec: publicv1.ComputeInstanceSpec_builder{
-					Template:  computeInstanceTemplateId,
-					Cores:     proto.Int32(2),
-					MemoryGib: proto.Int32(4),
+					Template:    computeInstanceTemplateId,
+					Cores:       proto.Int32(2),
+					MemoryGib:   proto.Int32(4),
+					RunStrategy: proto.String("Always"),
 					BootDisk: publicv1.ComputeInstanceDisk_builder{
 						SizeGib: 20,
 					}.Build(),
 					Image: publicv1.ComputeInstanceImage_builder{
-						SourceRef: "quay.io/containerdisks/fedora:latest",
+						SourceType: "registry",
+						SourceRef:  "quay.io/containerdisks/fedora:latest",
 					}.Build(),
 					Subnet: proto.String("non-existent-subnet"),
 				}.Build(),
diff --git a/proto/private/osac/private/v1/compute_instance_template_type.proto b/proto/private/osac/private/v1/compute_instance_template_type.proto
index 3ad2a049..3cac1ec9 100644
--- a/proto/private/osac/private/v1/compute_instance_template_type.proto
+++ b/proto/private/osac/private/v1/compute_instance_template_type.proto
@@ -16,6 +16,7 @@ syntax = "proto3";
 package osac.private.v1;
 
 import "google/protobuf/any.proto";
+import "osac/private/v1/compute_instance_type.proto";
 import "osac/private/v1/metadata_type.proto";
 
 message ComputeInstanceTemplate {
@@ -25,6 +26,12 @@ message ComputeInstanceTemplate {
   string title = 3;
   string description = 4;
   repeated ComputeInstanceTemplateParameterDefinition parameters = 5;
+
+  // Default values for compute instance spec fields. When a user creates a
+  // compute instance without setting these fields, these values are applied.
+  //
+  // User-provided spec field values always override these defaults.
+  ComputeInstanceTemplateSpecDefaults spec_defaults = 6;
 }
 
 message ComputeInstanceTemplateParameterDefinition {
@@ -35,3 +42,21 @@ message ComputeInstanceTemplateParameterDefinition {
   string type = 5;
   google.protobuf.Any default = 6;
 }
+
+// Default values for compute instance spec fields.
+message ComputeInstanceTemplateSpecDefaults {
+  // Default number of CPU cores.
+  optional int32 cores = 1;
+
+  // Default memory size in GiB.
+  optional int32 memory_gib = 2;
+
+  // Default image configuration.
+  optional ComputeInstanceImage image = 3;
+
+  // Default boot disk configuration.
+  optional ComputeInstanceDisk boot_disk = 4;
+
+  // Default run strategy.
+  optional string run_strategy = 5;
+}
diff --git a/proto/public/osac/public/v1/compute_instance_template_type.proto b/proto/public/osac/public/v1/compute_instance_template_type.proto
index e1056c52..1b9679cc 100644
--- a/proto/public/osac/public/v1/compute_instance_template_type.proto
+++ b/proto/public/osac/public/v1/compute_instance_template_type.proto
@@ -16,6 +16,7 @@ syntax = "proto3";
 package osac.public.v1;
 
 import "google/protobuf/any.proto";
+import "osac/public/v1/compute_instance_type.proto";
 import "osac/public/v1/metadata_type.proto";
 
 // A compute instance template defines a type of compute instance that can be created by the user. Note that the user doesn't create these
@@ -38,6 +39,12 @@ message ComputeInstanceTemplate {
   // Note that these are only the *definitions* of the parameters, not the actual values. The actual values are in the
   // `spec.template_parameters` field of the compute instance.
   repeated ComputeInstanceTemplateParameterDefinition parameters = 5;
+
+  // Default values for compute instance spec fields. When a user creates a
+  // compute instance without setting these fields, these values are applied.
+  //
+  // User-provided spec field values always override these defaults.
+  ComputeInstanceTemplateSpecDefaults spec_defaults = 6;
 }
 
 // Contains type and documentation of a template parameter.
@@ -88,3 +95,21 @@ message ComputeInstanceTemplateParameterDefinition {
   // Default value for optional parameters.
   google.protobuf.Any default = 6;
 }
+
+// Default values for compute instance spec fields.
+message ComputeInstanceTemplateSpecDefaults {
+  // Default number of CPU cores.
+  optional int32 cores = 1;
+
+  // Default memory size in GiB.
+  optional int32 memory_gib = 2;
+
+  // Default image configuration.
+  optional ComputeInstanceImage image = 3;
+
+  // Default boot disk configuration.
+  optional ComputeInstanceDisk boot_disk = 4;
+
+  // Default run strategy.
+  optional string run_strategy = 5;
+}
```

---

# Additional Fix: osac-aap PR #246

## Title
MGMT-23769: Add default value serialization for compute instances

## Diff
```diff
diff --git a/Makefile b/Makefile
index 137f46ad5..0e2a4591c 100644
--- a/Makefile
+++ b/Makefile
@@ -1,7 +1,7 @@
 # Integration tests for osac.workflows collection
 # Note: Must be run from repository root directory
 
-.PHONY: test
+.PHONY: test lint
 
 test:
 	@echo "=== Setting up test environment ==="
@@ -12,3 +12,6 @@ test:
 	@echo ""
 	@echo "=== Tearing down test environment ==="
 	cd tests/integration && ./teardown_test_env.sh
+
+lint:
+	uv run ansible-lint
diff --git a/collections/ansible_collections/osac/service/plugins/filter/find_template_roles.py b/collections/ansible_collections/osac/service/plugins/filter/find_template_roles.py
index 4801be0bc..42dd33bb1 100644
--- a/collections/ansible_collections/osac/service/plugins/filter/find_template_roles.py
+++ b/collections/ansible_collections/osac/service/plugins/filter/find_template_roles.py
@@ -88,6 +88,7 @@ class ProtobufType(StrEnum):
     float: ProtobufType.FLOAT,
     "path": ProtobufType.STRING,
     "json": ProtobufType.STRING,
+    "string": ProtobufType.STRING,
     "bytes": ProtobufType.BYTEARRAY,
 }
 
@@ -121,7 +122,6 @@ class TemplateParameter(Base):
     required: bool = False
     type: ProtobufType = ProtobufType.STRING
     default: ProtobufAnyValue | None = None
-    choices: list[Any] | None = None
 
     @classmethod
     def from_argspec(cls, name: str, spec: AnsibleArgumentSpecEntry) -> Self:
@@ -135,6 +135,18 @@ def from_argspec(cls, name: str, spec: AnsibleArgumentSpecEntry) -> Self:
             type=TypeMapping[spec.get("type", "str")],
         )
 
+    @classmethod
+    def from_definition(cls, defn: "TemplateParameterDefinition") -> Self:
+        """Create a TemplateParameter from a TemplateParameterDefinition (osac.yaml)."""
+        return cls(
+            name=defn.name,
+            title=defn.title,
+            description=defn.description,
+            required=defn.required,
+            default=defn.default,
+            type=TypeMapping.get(defn.type, ProtobufType.STRING),
+        )
+
     @pydantic.field_validator("default", mode="before")
     @classmethod
     def validate_default(cls, value: Any) -> ProtobufAnyValue | None:
@@ -180,6 +192,74 @@ class NodeSet(Base):
     size: int
 
 
+class ComputeInstanceImage(Base):
+    """Image configuration for compute instance spec defaults."""
+
+    source_type: str = pydantic.Field(
+        default="registry",
+        validation_alias=pydantic.AliasChoices("sourceType", "source_type"),
+        serialization_alias="source_type",
+    )
+    source_ref: str = pydantic.Field(
+        ...,
+        validation_alias=pydantic.AliasChoices("sourceRef", "source_ref"),
+        serialization_alias="source_ref",
+    )
+
+
+class ComputeInstanceDisk(Base):
+    """Disk configuration for compute instance spec defaults."""
+
+    size_gib: int = pydantic.Field(
+        ...,
+        validation_alias=pydantic.AliasChoices("sizeGiB", "sizeGib", "size_gib"),
+        serialization_alias="size_gib",
+    )
+
+
+class ComputeInstanceTemplateSpecDefaults(Base):
+    """Default values for compute instance spec fields.
+
+    Maps from Ansible camelCase (defaults/main.yaml) to proto snake_case.
+    """
+
+    cores: int | None = None
+    memory_gib: int | None = pydantic.Field(
+        default=None,
+        validation_alias=pydantic.AliasChoices("memoryGiB", "memoryGib", "memory_gib"),
+        serialization_alias="memory_gib",
+    )
+    image: ComputeInstanceImage | None = None
+    boot_disk: ComputeInstanceDisk | None = pydantic.Field(
+        default=None,
+        validation_alias=pydantic.AliasChoices("bootDisk", "boot_disk"),
+        serialization_alias="boot_disk",
+    )
+    run_strategy: str | None = pydantic.Field(
+        default=None,
+        validation_alias=pydantic.AliasChoices("runStrategy", "run_strategy"),
+        serialization_alias="run_strategy",
+    )
+
+
+class ParameterValidation(Base):
+    """Validation rules for a template parameter."""
+
+    pattern: str | None = None
+
+
+class TemplateParameterDefinition(Base):
+    """A parameter definition as written in osac.yaml."""
+
+    name: str
+    title: str | None = None
+    description: str | None = None
+    type: str = "string"
+    required: bool = False
+    default: str | int | float | bool | None = None
+    validation: ParameterValidation | None = None
+
+
 class TemplateTypeEnum(StrEnum):
     cluster = "cluster"
     compute_instance = "compute_instance"
@@ -207,6 +287,14 @@ class Metadata(Base):
     # Network-specific fields
     implementation_strategy: str | None = None
     capabilities: NetworkClassCapabilities | None = None
+    parameters: list[TemplateParameterDefinition] = pydantic.Field(default_factory=list)
+
+    # spec_defaults is used to set optional default values for the related spec fields associated
+    # with the template type.
+    #
+    # For now, spec_defaults is only used for ComputeInstance templates.
+    # This can be extended/generalized in the future with union type support for other template types.
+    spec_defaults: ComputeInstanceTemplateSpecDefaults | None = None
 
 
 class BaseTemplate(Base):
@@ -255,6 +343,7 @@ class ComputeInstanceTemplate(BaseTemplate):
     template_type: Literal[TemplateTypeEnum.compute_instance] = pydantic.Field(
         default=TemplateTypeEnum.compute_instance, exclude=True
     )
+    spec_defaults: ComputeInstanceTemplateSpecDefaults | None = None
 
 
 class NetworkClassTemplate(Base):
@@ -303,69 +392,59 @@ class Collection(Base):
     parent_path: Path
     name: str
 
-    def read_metadata_for_role(self, path: Path) -> Metadata | None:
-        """Read metadata for a role from osac.yaml/yml file.
+    def _read_yaml(self, path: Path, subdir: str, name: str) -> dict[str, Any] | None:
+        """Find and load a YAML file from a role subdirectory.
+
+        Tries .yaml then .yml extensions, returning the parsed contents of
+        the first file found, or None if no file exists or parsing fails.
 
         Args:
             path: Path to the role directory
+            subdir: Subdirectory within the role (e.g. "meta", "defaults")
+            name: Filename without extension (e.g. "main", "osac")
 
         Returns:
-            Metadata object if found and valid, None otherwise
+            Parsed YAML dict if found and valid, None otherwise
         """
-        for filename in ["osac.yaml", "osac.yml"]:
-            metadata_file: Path = path / "meta" / filename
-            if metadata_file.exists():
+        for ext in (".yaml", ".yml"):
+            filepath = path / subdir / f"{name}{ext}"
+            if filepath.exists():
                 break
         else:
-            display.vvv(f"No metadata file found for role at {path}")
             return None
 
         try:
-            with metadata_file.open("r", encoding="utf-8") as fd:
-                metadata = yaml.safe_load(fd)
+            with filepath.open("r", encoding="utf-8") as fd:
+                data = yaml.safe_load(fd)
         except yaml.YAMLError as e:
-            display.warning(f"Failed to parse metadata file {metadata_file}: {e}")
+            display.warning(f"Failed to parse {filepath}: {e}")
             return None
         except (PermissionError, OSError) as e:
-            display.warning(f"Error reading metadata file {metadata_file}: {e}")
+            display.warning(f"Error reading {filepath}: {e}")
             return None
 
-        if metadata:
-            try:
-                return Metadata.model_validate(metadata)
-            except Exception as e:
-                display.warning(f"Invalid metadata in {metadata_file}: {e}")
-                return None
+        if data and isinstance(data, dict):
+            return data
 
         return None
 
-    def read_params_for_role(self, path: Path) -> list[TemplateParameter]:
-        """Read template parameters for a role from argument_specs.yaml/yml file.
-
-        Args:
-            path: Path to the role directory
-
-        Returns:
-            List of TemplateParameter objects, empty list if none found or on error.
-            An empty list is valid - it means the role has no exposed parameters.
-        """
-        for filename in ["argument_specs.yaml", "argument_specs.yml"]:
-            argspec_file = path / "meta" / filename
-            if argspec_file.exists():
-                break
-        else:
-            # No argument_specs file is valid - role may have no parameters
-            return []
+    def read_metadata_for_role(self, path: Path) -> Metadata | None:
+        """Read metadata for a role from osac.yaml/yml file."""
+        data = self._read_yaml(path, "meta", "osac")
+        if data is None:
+            display.vvv(f"No metadata file found for role at {path}")
+            return None
 
         try:
-            with argspec_file.open("r", encoding="utf-8") as fd:
-                argspec: AnsibleArgumentSpec = cast(
-                    AnsibleArgumentSpec, yaml.safe_load(fd))
-        except yaml.YAMLError as e:
-            display.warning(f"Failed to parse argument_specs file {argspec_file}: {e}")
-            return []
-        except (PermissionError, OSError) as e:
-            display.warning(f"Error reading argument_specs file {argspec_file}: {e}")
+            return Metadata.model_validate(data)
+        except Exception as e:
+            display.warning(f"Invalid metadata for role at {path}: {e}")
+            return None
+
+    def read_params_for_role(self, path: Path) -> list[TemplateParameter]:
+        """Read template parameters for a role from argument_specs.yaml/yml file."""
+        data = self._read_yaml(path, "meta", "argument_specs")
+        if data is None:
             return []
 
         template_params: list[TemplateParameter] = []
@@ -373,7 +452,7 @@ def read_params_for_role(self, path: Path) -> list[TemplateParameter]:
         # Navigate the nested structure to find template_parameters
         # Missing keys at any level are valid - just means no parameters defined
         for name, spec in (
-            argspec.get("argument_specs", {})
+            data.get("argument_specs", {})
             .get("main", {})
             .get("options", {})
             .get("template_parameters", {})
@@ -384,9 +463,8 @@ def read_params_for_role(self, path: Path) -> list[TemplateParameter]:
                 template_params.append(TemplateParameter.from_argspec(name, spec))
             except Exception as e:
                 display.warning(
-                    f"Failed to parse template parameter '{name}' in {argspec_file}: {e}"
+                    f"Failed to parse template parameter '{name}' in {path}: {e}"
                 )
-                # Continue processing other parameters
                 continue
 
         return template_params
@@ -415,9 +493,16 @@ def templates(self) -> Generator[BaseTemplate | NetworkClassTemplate, None, None
                 continue
 
             metadata = self.read_metadata_for_role(path)
-            params = self.read_params_for_role(path)
             if metadata is not None:
                 try:
+                    if metadata.parameters:
+                        params = [
+                            TemplateParameter.from_definition(d)
+                            for d in metadata.parameters
+                        ]
+                    else:
+                        params = self.read_params_for_role(path)
+
                     common = {
                         "collection": self.name,
                         "path": path,
@@ -450,7 +535,7 @@ def templates(self) -> Generator[BaseTemplate | NetworkClassTemplate, None, None
                             capabilities=metadata.capabilities or NetworkClassCapabilities(),
                         )
                     else:
-                        yield ComputeInstanceTemplate(**common)
+                        yield ComputeInstanceTemplate(**common, spec_defaults=metadata.spec_defaults)
                 except Exception as e:
                     display.warning(
                         f"Failed to create template for role '{path.name}' in collection '{self.name}': {e}"
diff --git a/collections/ansible_collections/osac/templates/README.md b/collections/ansible_collections/osac/templates/README.md
index a84e96160..1837a2364 100644
--- a/collections/ansible_collections/osac/templates/README.md
+++ b/collections/ansible_collections/osac/templates/README.md
@@ -126,12 +126,47 @@ validation, and lifecycle management.
 4. Implement provisioning tasks in `roles/my_cluster_template/tasks/install.yaml`
 5. Implement cleanup tasks in `roles/my_cluster_template/tasks/delete.yaml`
 
-### Creating a New VM Template
+### Creating a New ComputeInstance Template
 
-1. Create role structure as above
-2. Set `template_type: vm` in `meta/osac.yaml`
-3. Use `create.yaml` and `delete.yaml` instead of `install.yaml`
-4. Implement VM creation using `kubernetes.core.k8s` modules
+ComputeInstance templates define all metadata, spec defaults, and parameters in a
+single file: `meta/osac.yaml`.
+
+1. Create a new role directory under `roles/`:
+   ```bash
+   mkdir -p roles/my_vm_template/{tasks,meta}
+   ```
+
+2. Define template metadata, spec defaults, and parameters in `roles/my_vm_template/meta/osac.yaml`:
+   ```yaml
+   title: My VM Template
+   description: Description of what this template provides
+   template_type: compute_instance
+
+   spec_defaults:
+     cores: 2
+     memory_gib: 2
+     boot_disk:
+       size_gib: 10
+     image:
+       source_type: registry
+       source_ref: "quay.io/containerdisks/fedora:latest"
+     run_strategy: "Always"
+
+   parameters:
+     - name: my_param
+       title: My Parameter
+       description: What this parameter controls
+       type: string
+       required: false
+       default: "some_default"
+       validation:
+         pattern: '^[a-z]+$'
+   ```
+
+3. Implement provisioning tasks in `roles/my_vm_template/tasks/create.yaml`
+4. Implement cleanup tasks in `roles/my_vm_template/tasks/delete.yaml`
+
+See `roles/ocp_virt_vm` for a complete example.
 
 ## Architecture
 
@@ -167,7 +202,7 @@ Templates integrate with OSAC through a well-defined interface:
 
 Contributions are welcome! Please ensure all templates:
 - Include comprehensive `meta/osac.yaml` metadata
-- Define all parameters in `meta/argument_specs.yaml`
+- Define parameters in `meta/osac.yaml` (ComputeInstance templates) or `meta/argument_specs.yaml` (cluster templates)
 - Implement both create and delete operations
 - Follow Ansible best practices
 - Include descriptive variable names and comments
diff --git a/collections/ansible_collections/osac/templates/plugins/filter/template_validate.py b/collections/ansible_collections/osac/templates/plugins/filter/template_validate.py
new file mode 100644
index 000000000..8d10c8ddc
--- /dev/null
+++ b/collections/ansible_collections/osac/templates/plugins/filter/template_validate.py
@@ -0,0 +1,125 @@
+import re
+import yaml
+
+from pathlib import Path
+from typing import Any
+
+from ansible.errors import AnsibleFilterError
+
+
+def _load_osac_metadata(role_path: str) -> dict[str, Any]:
+    """Load and return the parsed meta/osac.yaml for a role."""
+    path = Path(role_path) / "meta" / "osac.yaml"
+    if not path.exists():
+        path = Path(role_path) / "meta" / "osac.yml"
+    if not path.exists():
+        raise AnsibleFilterError(
+            f"No osac.yaml found at {role_path}/meta/"
+        )
+    with path.open("r", encoding="utf-8") as fd:
+        data = yaml.safe_load(fd)
+    if not isinstance(data, dict):
+        raise AnsibleFilterError(
+            f"Invalid osac.yaml at {path}: expected a YAML mapping"
+        )
+    return data
+
+
+def template_spec_defaults(role_path: str) -> dict[str, Any]:
+    """Load spec_defaults from osac.yaml and return in camelCase for CRD merging.
+
+    Usage in Ansible:
+        {{ role_path | osac.templates.template_spec_defaults }}
+    """
+    metadata = _load_osac_metadata(role_path)
+    spec_defaults = metadata.get("spec_defaults")
+    if not spec_defaults or not isinstance(spec_defaults, dict):
+        return {}
+
+    camel_map = {
+        "memory_gib": "memoryGiB",
+        "boot_disk": "bootDisk",
+        "size_gib": "sizeGiB",
+        "source_type": "sourceType",
+        "source_ref": "sourceRef",
+        "run_strategy": "runStrategy",
+    }
+
+    def to_camel(d: dict[str, Any]) -> dict[str, Any]:
+        result: dict[str, Any] = {}
+        for key, value in d.items():
+            camel_key = camel_map.get(key, key)
+            if isinstance(value, dict):
+                result[camel_key] = to_camel(value)
+            else:
+                result[camel_key] = value
+        return result
+
+    return to_camel(spec_defaults)
+
+
+def template_validate_params(
+    user_params: dict[str, Any], role_path: str
+) -> dict[str, Any]:
+    """Validate and merge template parameters against osac.yaml definitions.
+
+    1. Load parameter definitions from meta/osac.yaml
+    2. Build defaults dict from parameter definitions
+    3. Merge: defaults <- user-provided params
+    4. Validate required fields are present
+    5. Validate patterns where specified
+    6. Return merged+validated params dict
+
+    Usage in Ansible:
+        {{ (template_parameters | default({})) | osac.templates.template_validate_params(role_path) }}
+    """
+    metadata = _load_osac_metadata(role_path)
+    param_defs = metadata.get("parameters", [])
+    if not isinstance(param_defs, list):
+        raise AnsibleFilterError(
+            f"'parameters' in osac.yaml must be a list, got {type(param_defs).__name__}"
+        )
+
+    defaults: dict[str, Any] = {}
+    for defn in param_defs:
+        if not isinstance(defn, dict):
+            continue
+        name = defn.get("name")
+        if not name:
+            continue
+        if "default" in defn:
+            defaults[name] = defn["default"]
+
+    merged = {**defaults, **user_params}
+
+    for defn in param_defs:
+        if not isinstance(defn, dict):
+            continue
+        name = defn.get("name")
+        if not name:
+            continue
+
+        if defn.get("required", False) and name not in merged:
+            raise AnsibleFilterError(
+                f"Required template parameter '{name}' is missing"
+            )
+
+        validation = defn.get("validation")
+        if validation and isinstance(validation, dict) and name in merged:
+            pattern = validation.get("pattern")
+            if pattern and isinstance(merged[name], str):
+                if not re.match(pattern, merged[name]):
+                    raise AnsibleFilterError(
+                        f"Template parameter '{name}' value '{merged[name]}' "
+                        f"does not match pattern: {pattern}"
+                    )
+
+    return merged
+
+
+class FilterModule:
+    def filters(self) -> dict[str, Any]:
+        return {
+            "template_spec_defaults": template_spec_defaults,
+            "template_validate_params": template_validate_params,
+        }
diff --git a/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/defaults/main.yaml b/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/defaults/main.yaml
index c553e4b35..07ee6e9a2 100644
--- a/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/defaults/main.yaml
+++ b/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/defaults/main.yaml
@@ -2,17 +2,3 @@
 default_vm_internal_network: "hypershift"
 default_vm_storage_class: "nfs-client"
 default_vm_labels: "{{ {compute_instance_label: compute_instance_name} }}"
-
-# Setup the defaults described in the arg_specs.
-default_arg_specs:
-  exposed_ports: "22/tcp"
-
-# Defaults for ComputeInstance spec fields.
-default_spec:
-  cores: 2
-  memoryGiB: 2
-  bootDisk:
-    sizeGiB: 10
-  image:
-    sourceRef: "quay.io/containerdisks/fedora:latest"
-  runStrategy: "Always"
diff --git a/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/meta/argument_specs.yaml b/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/meta/argument_specs.yaml
index 54c6407c0..74f4f77ad 100644
--- a/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/meta/argument_specs.yaml
+++ b/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/meta/argument_specs.yaml
@@ -32,13 +32,5 @@ argument_specs:
           `lspci -nn | grep -i nvidia` on a node that has the device.
       template_parameters:
         type: dict
-        description: VM configuration parameters
-        options:
-          exposed_ports:
-            description: >
-              Ports to expose on the VM for ingress traffic.
-              The syntax is a comma-separated list of `<port>/<protocol>` pairs, where `<protocol>` is either `tcp` or `udp`.
-              For example, `22/tcp,80/tcp` will expose tcp ports 22 and 80 on the VM.
-            type: str
-            required: false
-            default: "22/tcp"
+        required: false
+        description: Template parameters for the VM.
diff --git a/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/meta/osac.yaml b/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/meta/osac.yaml
index cb73f53e8..ffb08172c 100644
--- a/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/meta/osac.yaml
+++ b/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/meta/osac.yaml
@@ -5,3 +5,27 @@ description: >
 
 # Specify this is a ComputeInstance template (not a cluster template)
 template_type: compute_instance
+
+spec_defaults:
+  cores: 2
+  memory_gib: 2
+  boot_disk:
+    size_gib: 10
+  image:
+    source_type: registry
+    source_ref: "quay.io/containerdisks/fedora:latest"
+  run_strategy: "Always"
+
+parameters:
+  - name: exposed_ports
+    title: Exposed Ports
+    description: >
+      Ports to expose on the VM for ingress traffic.
+      The syntax is a comma-separated list of `<port>/<protocol>` pairs,
+      where `<protocol>` is either `tcp` or `udp`.
+      For example, `22/tcp,80/tcp` will expose tcp ports 22 and 80 on the VM.
+    type: string
+    required: false
+    default: "22/tcp"
+    validation:
+      pattern: '^([0-9]+/(tcp|udp))(,[0-9]+/(tcp|udp))*$'
diff --git a/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/tasks/create.yaml b/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/tasks/create.yaml
index 1a6b75d35..50e320951 100644
--- a/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/tasks/create.yaml
+++ b/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/tasks/create.yaml
@@ -2,7 +2,7 @@
 # Override points: secrets, modify_vm_spec, pre_create_hook, resources, post_create_hook, wait_annotate
 # NOT overrideable: validate, build_spec (CRITICAL steps for correct operation)
 # Variables: compute_instance, compute_instance_name, tenant_target_namespace,
-# template_id, template_parameters, default_arg_specs, default_vm_labels, default_spec.
+# template_id, template_parameters, default_vm_labels.
 ---
 - name: Include get remote cluster kubeconfig
   ansible.builtin.include_role:
diff --git a/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/tasks/create_validate.yaml b/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/tasks/create_validate.yaml
index e43984420..15582507b 100644
--- a/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/tasks/create_validate.yaml
+++ b/collections/ansible_collections/osac/templates/roles/ocp_virt_vm/tasks/create_validate.yaml
@@ -1,21 +1,23 @@
 ---
-- name: Merge template defaults into template_parameters
+- name: Merge spec defaults into compute instance
   ansible.builtin.set_fact:
-    params: "{{ default_arg_specs | combine(template_parameters) }}"
+    compute_instance: >-
+      {{ compute_instance | combine({
+           'spec': (role_path | osac.templates.template_spec_defaults)
+                   | combine(compute_instance.spec | default({}), recursive=True)
+         }, recursive=True) }}
+
+- name: Validate and merge template parameters
+  ansible.builtin.set_fact:
+    params: "{{ (template_parameters | default({})) | osac.templates.template_validate_params(role_path) }}"
 
 - name: Extract VM configuration from ComputeInstance spec
   ansible.builtin.set_fact:
-    vm_cpu_cores: "{{ (compute_instance.spec.cores | default(default_spec.cores)) | int }}"
-    vm_memory: "{{ (compute_instance.spec.memoryGiB | default(default_spec.memoryGiB)) | string + 'Gi' }}"
-    vm_boot_disk_size: "{{ (compute_instance.spec.bootDisk.sizeGiB | default(default_spec.bootDisk.sizeGiB)) | string + 'Gi' }}"
-    vm_image_source: "{{ compute_instance.spec.image.sourceRef | default(default_spec.image.sourceRef) }}"
-    vm_run_strategy: "{{ compute_instance.spec.runStrategy | default(default_spec.runStrategy) }}"
+    vm_cpu_cores: "{{ compute_instance.spec.cores | int }}"
+    vm_memory: "{{ compute_instance.spec.memoryGiB | string + 'Gi' }}"
+    vm_boot_disk_size: "{{ compute_instance.spec.bootDisk.sizeGiB | string + 'Gi' }}"
+    vm_image_source: "{{ compute_instance.spec.image.sourceRef }}"
+    vm_run_strategy: "{{ compute_instance.spec.runStrategy }}"
     vm_ssh_key: "{{ compute_instance.spec.sshKey | default('') }}"
     vm_user_data_secret_ref: "{{ (compute_instance.spec.userDataSecretRef | default({})).name | default('') }}"
     vm_additional_disks: "{{ compute_instance.spec.additionalDisks | default([]) }}"
-
-- name: Validate exposed_ports format
-  ansible.builtin.assert:
-    that:
-      - params.exposed_ports is match('^([0-9]+/(tcp|udp))(,[0-9]+/(tcp|udp))*$')
-    fail_msg: "exposed_ports must be in format 'port/protocol' (e.g., '22/tcp,80/tcp') where protocol is 'tcp' or 'udp'"
diff --git a/tests/integration/fixtures/computeinstance-defaults-test.yaml b/tests/integration/fixtures/computeinstance-defaults-test.yaml
new file mode 100644
index 000000000..ac013b01e
--- /dev/null
+++ b/tests/integration/fixtures/computeinstance-defaults-test.yaml
@@ -0,0 +1,10 @@
+---
+apiVersion: osac.openshift.io/v1alpha1
+kind: ComputeInstance
+metadata:
+  name: test-vm-defaults
+  namespace: osac-system
+spec:
+  templateID: osac.templates.ocp_virt_vm
+status:
+  desiredConfigVersion: "1"
diff --git a/tests/integration/run_tests.sh b/tests/integration/run_tests.sh
index be046309a..9433ebae7 100755
--- a/tests/integration/run_tests.sh
+++ b/tests/integration/run_tests.sh
@@ -29,6 +29,8 @@ WORKFLOWS=(
   "cluster_post_install"
   "compute_instance_create"
   "compute_instance_with_gpu_create"
+  "compute_instance_create_defaults"
+  "compute_instance_create_validation"
   "compute_instance_delete"
   "cluster_status_reporting"
 )
diff --git a/tests/integration/setup_test_env.sh b/tests/integration/setup_test_env.sh
index 24fdac78b..2729c2add 100755
--- a/tests/integration/setup_test_env.sh
+++ b/tests/integration/setup_test_env.sh
@@ -84,7 +84,11 @@ kubectl create namespace cluster-test-cluster-work || true
 kubectl create namespace computeinstance-test-vm-work || true
 
 # 5. Apply test fixtures
+# Note: computeinstance-defaults-test.yaml is intentionally omitted — it has no required
+# spec fields (tests defaults merging) and is read from file by tests via lookup().
 echo "Applying test fixtures..."
-kubectl apply -f "${SCRIPT_DIR}/fixtures/"
+kubectl apply -f "${SCRIPT_DIR}/fixtures/clusterorder-test.yaml"
+kubectl apply -f "${SCRIPT_DIR}/fixtures/computeinstance-test.yaml"
+kubectl apply -f "${SCRIPT_DIR}/fixtures/computeinstance-with-gpu-test.yaml"
 
 echo "=== Test environment ready ==="
diff --git a/tests/integration/targets/compute_instance_create/tasks/baseline.yml b/tests/integration/targets/compute_instance_create/tasks/baseline.yml
index 5709016a4..c9dc4d376 100644
--- a/tests/integration/targets/compute_instance_create/tasks/baseline.yml
+++ b/tests/integration/targets/compute_instance_create/tasks/baseline.yml
@@ -55,3 +55,10 @@
           - template_id is defined
           - template_id == "osac.templates.ocp_virt_vm"
         fail_msg: "Template ID not extracted correctly"
+
+    - name: Verify user-specified spec values override template defaults
+      ansible.builtin.assert:
+        that:
+          - vm_memory == "4Gi"
+          - vm_boot_disk_size == "20Gi"
+        fail_msg: "User spec values should override template defaults."
diff --git a/tests/integration/targets/compute_instance_create_defaults/meta/main.yml b/tests/integration/targets/compute_instance_create_defaults/meta/main.yml
new file mode 100644
index 000000000..23d65c7ef
--- /dev/null
+++ b/tests/integration/targets/compute_instance_create_defaults/meta/main.yml
@@ -0,0 +1,2 @@
+---
+dependencies: []
diff --git a/tests/integration/targets/compute_instance_create_defaults/tasks/baseline.yml b/tests/integration/targets/compute_instance_create_defaults/tasks/baseline.yml
new file mode 100644
index 000000000..0defb9da8
--- /dev/null
+++ b/tests/integration/targets/compute_instance_create_defaults/tasks/baseline.yml
@@ -0,0 +1,60 @@
+---
+- name: Compute Instance Create Defaults - Baseline Test
+  hosts: localhost
+  gather_facts: true
+  vars_files:
+    - ../../../common_vars.yml
+
+  collections:
+    - osac.templates
+
+  tasks:
+    - name: Read minimal ComputeInstance fixture (no spec fields)
+      ansible.builtin.set_fact:
+        compute_instance: "{{ lookup('file', '../../../fixtures/computeinstance-defaults-test.yaml') | from_yaml }}"
+
+    - name: Run create_validate to merge defaults and extract VM config
+      ansible.builtin.include_role:
+        name: osac.templates.ocp_virt_vm
+        tasks_from: create_validate.yaml
+
+    - name: Verify compute instance name
+      ansible.builtin.assert:
+        that:
+          - compute_instance.metadata.name == "test-vm-defaults"
+        fail_msg: "Compute instance name not extracted correctly"
+
+    - name: Verify default CPU cores applied
+      ansible.builtin.assert:
+        that:
+          - vm_cpu_cores is defined
+          - vm_cpu_cores | int == 2
+        fail_msg: "Expected default cpu cores of 2, got {{ vm_cpu_cores | default('undefined') }}"
+
+    - name: Verify default memory applied
+      ansible.builtin.assert:
+        that:
+          - vm_memory is defined
+          - vm_memory == "2Gi"
+        fail_msg: "Expected default memory of 2Gi, got {{ vm_memory | default('undefined') }}"
+
+    - name: Verify default boot disk size applied
+      ansible.builtin.assert:
+        that:
+          - vm_boot_disk_size is defined
+          - vm_boot_disk_size == "10Gi"
+        fail_msg: "Expected default boot disk size of 10Gi, got {{ vm_boot_disk_size | default('undefined') }}"
+
+    - name: Verify default image source applied
+      ansible.builtin.assert:
+        that:
+          - vm_image_source is defined
+          - vm_image_source == "quay.io/containerdisks/fedora:latest"
+        fail_msg: "Expected default image source, got {{ vm_image_source | default('undefined') }}"
+
+    - name: Verify default run strategy applied
+      ansible.builtin.assert:
+        that:
+          - vm_run_strategy is defined
+          - vm_run_strategy == "Always"
+        fail_msg: "Expected default run strategy of Always, got {{ vm_run_strategy | default('undefined') }}"
diff --git a/tests/integration/targets/compute_instance_create_validation/meta/main.yml b/tests/integration/targets/compute_instance_create_validation/meta/main.yml
new file mode 100644
index 000000000..23d65c7ef
--- /dev/null
+++ b/tests/integration/targets/compute_instance_create_validation/meta/main.yml
@@ -0,0 +1,2 @@
+---
+dependencies: []
diff --git a/tests/integration/targets/compute_instance_create_validation/tasks/baseline.yml b/tests/integration/targets/compute_instance_create_validation/tasks/baseline.yml
new file mode 100644
index 000000000..bb373631f
--- /dev/null
+++ b/tests/integration/targets/compute_instance_create_validation/tasks/baseline.yml
@@ -0,0 +1,58 @@
+---
+- name: Compute Instance Validation - Valid Parameters Test
+  hosts: localhost
+  gather_facts: true
+  vars_files:
+    - ../../../common_vars.yml
+
+  collections:
+    - osac.templates
+
+  tasks:
+    - name: Read minimal ComputeInstance fixture
+      ansible.builtin.set_fact:
+        compute_instance: "{{ lookup('file', '../../../fixtures/computeinstance-defaults-test.yaml') | from_yaml }}"
+
+    - name: Set template parameters with valid exposed_ports
+      ansible.builtin.set_fact:
+        template_parameters:
+          exposed_ports: "22/tcp,80/tcp,443/tcp"
+
+    - name: Run create_validate to merge defaults and validate params
+      ansible.builtin.include_role:
+        name: osac.templates.ocp_virt_vm
+        tasks_from: create_validate.yaml
+
+    - name: Verify custom exposed_ports value applied
+      ansible.builtin.assert:
+        that:
+          - params is defined
+          - params.exposed_ports == "22/tcp,80/tcp,443/tcp"
+        fail_msg: "Expected exposed_ports='22/tcp,80/tcp,443/tcp', got {{ (params | default({})).exposed_ports | default('undefined') }}"
+
+- name: Compute Instance Validation - Invalid Pattern Rejection
+  hosts: localhost
+  gather_facts: true
+  vars_files:
+    - ../../../common_vars.yml
+
+  collections:
+    - osac.templates
+
+  tasks:
+    - name: Set role path from collection
+      ansible.builtin.set_fact:
+        ocp_virt_vm_role_path: "{{ lookup('ansible.builtin.first_found', paths=lookup('ansible.builtin.config', 'COLLECTIONS_PATHS') | map('regex_replace', '$', '/ansible_collections/osac/templates/roles/ocp_virt_vm/meta') | list, files=['osac.yaml']) | dirname | dirname }}"
+
+    - name: Validate with invalid exposed_ports pattern
+      ansible.builtin.set_fact:
+        invalid_result: "{{ {'exposed_ports': 'not-a-valid-port'} | osac.templates.template_validate_params(ocp_virt_vm_role_path) }}"
+      register: validation_result
+      ignore_errors: true
+
+    - name: Verify validation rejected invalid pattern
+      ansible.builtin.assert:
+        that:
+          - validation_result is failed
+          - "'does not match pattern' in validation_result.msg"
+        fail_msg: "Expected validation to reject 'not-a-valid-port' but it {{ 'passed' if validation_result is success else 'failed with: ' + (validation_result.msg | default('unknown error')) }}"
```
