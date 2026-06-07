# Real Fix: fulfillment-service PR #420

## Title
MGMT-23970: fix blank TEMPLATE and HUB columns in ComputeInstance table output

## Summary
## Summary

- `lookupName` in `table_renderer.go` falls back to the raw key in every error path (helper not found, gRPC error, no results), but was missing the fallback when an object IS found with an empty `metadata.name` — returning `""` and leaving the column blank
- Added `if result == "" { result = key }` after `GetName()` to close this gap
- Added two unit tests covering the regression (empty name → show key) and the happy path (non-empty name → show name)

## Test plan

- [ ] `go run github.com/onsi/ginkgo/v2/ginkgo run internal/rendering` — 2 new specs pass
- [ ] `fulfillment-cli get osac.public.v1.ComputeInstance` — TEMPLATE column now shows `osac.templates.ocp_virt_vm`
- [ ] `fulfillment-cli get osac.private.v1.ComputeInstance` — TEMPLATE and HUB columns now show `osac.templates.ocp_virt_vm` and `hypershift1`

Fixes [MGMT-23970](https://redhat.atlassian.net/browse/MGMT-23970).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

## Release Notes

* **Bug Fixes**
  * Fixed rendering of lookup columns when metadata names are empty; now displays the lookup key identifier instead.

* **Tests**
  * Added test suite for lookup column rendering with multiple scenarios.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->

## Diff
```diff
diff --git a/internal/rendering/table_renderer.go b/internal/rendering/table_renderer.go
index 30f81da5..cdcde502 100644
--- a/internal/rendering/table_renderer.go
+++ b/internal/rendering/table_renderer.go
@@ -477,10 +477,13 @@ func (r *TableRenderer) lookupName(ctx context.Context, messageFullName protoref
 		return
 	}
 
-	// Return the name of the first object:
+	// Return the name of the first object, falling back to the key if the name is empty:
 	object := listResult.Items[0]
 	metadata := helper.GetMetadata(object)
 	result = metadata.GetName()
+	if result == "" {
+		result = key
+	}
 	return
 }
 
diff --git a/internal/rendering/table_renderer_test.go b/internal/rendering/table_renderer_test.go
new file mode 100644
index 00000000..591b9132
--- /dev/null
+++ b/internal/rendering/table_renderer_test.go
@@ -0,0 +1,127 @@
+/*
+Copyright (c) 2025 Red Hat Inc.
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
+package rendering
+
+import (
+	"bytes"
+	"context"
+
+	. "github.com/onsi/ginkgo/v2/dsl/core"
+	. "github.com/onsi/ginkgo/v2/dsl/table"
+	. "github.com/onsi/gomega"
+	"google.golang.org/grpc"
+	"google.golang.org/grpc/credentials/insecure"
+
+	publicv1 "github.com/osac-project/fulfillment-service/internal/api/osac/public/v1"
+	"github.com/osac-project/fulfillment-service/internal/packages"
+	"github.com/osac-project/fulfillment-service/internal/reflection"
+	internaltesting "github.com/osac-project/fulfillment-service/internal/testing"
+)
+
+var _ = Describe("Table renderer", func() {
+	var (
+		ctx        context.Context
+		server     *internaltesting.Server
+		connection *grpc.ClientConn
+		helper     *reflection.Helper
+	)
+
+	BeforeEach(func() {
+		var err error
+		ctx = context.Background()
+
+		server = internaltesting.NewServer()
+		DeferCleanup(server.Stop)
+
+		connection, err = grpc.NewClient(
+			server.Address(),
+			grpc.WithTransportCredentials(insecure.NewCredentials()),
+		)
+		Expect(err).ToNot(HaveOccurred())
+		DeferCleanup(connection.Close)
+
+		helper, err = reflection.NewHelper().
+			SetLogger(logger).
+			SetConnection(connection).
+			AddPackage(packages.PublicV1, 1).
+			Build()
+		Expect(err).ToNot(HaveOccurred())
+	})
+
+	// registerTemplateAndRender registers a ComputeInstanceTemplates server that returns a single
+	// template with the given name (empty string means no name set), starts the server, renders one
+	// ComputeInstance via the table renderer, and returns the output.
+	registerTemplateAndRender := func(templateName string) string {
+		tmplBuilder := publicv1.ComputeInstanceTemplate_builder{
+			Id: "osac.templates.ocp_virt_vm",
+		}
+		if templateName != "" {
+			tmplBuilder.Metadata = publicv1.Metadata_builder{Name: templateName}.Build()
+		}
+		publicv1.RegisterComputeInstanceTemplatesServer(
+			server.Registrar(),
+			&internaltesting.ComputeInstanceTemplatesServerFuncs{
+				ListFunc: func(
+					_ context.Context,
+					_ *publicv1.ComputeInstanceTemplatesListRequest,
+				) (*publicv1.ComputeInstanceTemplatesListResponse, error) {
+					return publicv1.ComputeInstanceTemplatesListResponse_builder{
+						Size:  1,
+						Total: 1,
+						Items: []*publicv1.ComputeInstanceTemplate{tmplBuilder.Build()},
+					}.Build(), nil
+				},
+			},
+		)
+		server.Start()
+
+		var buf bytes.Buffer
+		renderer, err := NewTableRenderer().
+			SetLogger(logger).
+			SetHelper(helper).
+			SetWriter(&buf).
+			Build()
+		Expect(err).ToNot(HaveOccurred())
+
+		instance := publicv1.ComputeInstance_builder{
+			Id:       "019d53bd-42b4-7e23-b98e-6368490d3d83",
+			Metadata: publicv1.Metadata_builder{Name: "test"}.Build(),
+			Spec:     publicv1.ComputeInstanceSpec_builder{Template: "osac.templates.ocp_virt_vm"}.Build(),
+		}.Build()
+
+		err = renderer.Render(ctx, []*publicv1.ComputeInstance{instance})
+		Expect(err).ToNot(HaveOccurred())
+		return buf.String()
+	}
+
+	Describe("Lookup columns", func() {
+		DescribeTable(
+			"Resolves the TEMPLATE column",
+			func(templateName, expectedSubstring string) {
+				Expect(registerTemplateAndRender(templateName)).To(ContainSubstring(expectedSubstring))
+			},
+			Entry(
+				// Regression for MGMT-23970: TEMPLATE column was blank when metadata.name was empty.
+				"Falls back to the key when the looked-up object has no name",
+				"",
+				"osac.templates.ocp_virt_vm",
+			),
+			Entry(
+				"Shows the template name when the looked-up object has a name",
+				"OpenShift Virt VM",
+				"OpenShift Virt VM",
+			),
+		)
+	})
+})
```
