# Real Fix: osac-aap PR #234

## Title
MGMT-23770: fix publish_templates for empty API responses

## Summary
## Summary

- Fix `publish_templates` role failing when the fulfillment-service API returns empty responses (no `size` field)
- Replace `.json.size > 0` with `.json.get('items', []) | length > 0` in all 3 task files
- Add unit tests with a mock HTTP server covering empty, populated, and edge-case responses

## Root Cause

The fulfillment-service uses proto3 `optional int32` for the `size` field. When there are no items, proto3 JSON serialization omits zero-valued optional fields entirely, so the response is `{}` instead of `{"size": 0, "items": []}`. The Ansible conditional `.json.size` then fails with `'dict object' has no attribute 'size'`.

The fix uses `.json.get('items', [])` (Python dict method) rather than dot or bracket notation, because `items` is also a built-in dict method in Python — both `.json.items` and `.json['items']` resolve to `dict.items()` when the key is absent.

## Files Changed

**Bug fix** (3 files, 1 line each):
- `collections/.../publish_templates/tasks/clusters.yaml`
- `collections/.../publish_templates/tasks/compute_instances.yaml`
- `collections/.../publish_templates/tasks/network_classes.yaml`

**Unit tests** (2 new files):
- `collections/.../publish_templates/tests/test.yml` — 3 test scenarios
- `collections/.../publish_templates/tests/mock_api_server.py` — mock HTTP server

## Test plan

- [x] `ansible-lint` passes (0 failures, 0 warnings)
- [x] `pre-commit run --all-files` passes
- [x] Unit test: empty API response (the [MGMT-23770](https://redhat.atlassian.net/browse/MGMT-23770) bug scenario)
- [x] Unit test: populated response (existing items PATCHed, new POSTed)
- [x] Unit test: no `items` key edge case
- [x] E2E on hypershift1 (osac-zszabo): publish_templates playbook against real fulfillment-service with empty network_classes and compute_instance_templates endpoints

🤖 Generated with [Claude Code](https://claude.com/claude-code)

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->
## Summary by CodeRabbit

* **Bug Fixes**
  * Improved template publication checks to reliably detect existing items across varied API JSON shapes, ensuring create vs update actions run correctly for clusters, compute instances, and network classes.

* **Tests**
  * Added an end-to-end test playbook and a local mock API server to validate populated, empty, and missing-items responses and expected POST vs PATCH behavior.
<!-- end of auto-generated comment: release notes by coderabbit.ai -->

## Diff
```diff
diff --git a/collections/ansible_collections/osac/service/roles/publish_templates/tasks/clusters.yaml b/collections/ansible_collections/osac/service/roles/publish_templates/tasks/clusters.yaml
index 5e8f39dce..156793759 100644
--- a/collections/ansible_collections/osac/service/roles/publish_templates/tasks/clusters.yaml
+++ b/collections/ansible_collections/osac/service/roles/publish_templates/tasks/clusters.yaml
@@ -12,7 +12,7 @@
       {{
       cluster_template_check | json_query("json.items[].id")
       }}
-  when: cluster_template_check is success and (cluster_template_check.json.size | default(0)) > 0
+  when: cluster_template_check is success and cluster_template_check.json.get('items', []) | length > 0
 
 - name: Update existing cluster template
   loop: "{{ osac_cluster_templates }}"
diff --git a/collections/ansible_collections/osac/service/roles/publish_templates/tasks/compute_instances.yaml b/collections/ansible_collections/osac/service/roles/publish_templates/tasks/compute_instances.yaml
index fba2b9b4b..172d2aceb 100644
--- a/collections/ansible_collections/osac/service/roles/publish_templates/tasks/compute_instances.yaml
+++ b/collections/ansible_collections/osac/service/roles/publish_templates/tasks/compute_instances.yaml
@@ -12,7 +12,7 @@
       {{
       compute_instance_template_check | json_query("json.items[].id")
       }}
-  when: compute_instance_template_check is success and (compute_instance_template_check.json.size | default(0)) > 0
+  when: compute_instance_template_check is success and compute_instance_template_check.json.get('items', []) | length > 0
 
 - name: Update existing ComputeInstance template
   loop: "{{ osac_compute_instance_templates }}"
diff --git a/collections/ansible_collections/osac/service/roles/publish_templates/tasks/network_classes.yaml b/collections/ansible_collections/osac/service/roles/publish_templates/tasks/network_classes.yaml
index a1b4ccd38..cf1fbdcc8 100644
--- a/collections/ansible_collections/osac/service/roles/publish_templates/tasks/network_classes.yaml
+++ b/collections/ansible_collections/osac/service/roles/publish_templates/tasks/network_classes.yaml
@@ -12,7 +12,7 @@
       {{
       network_class_check | json_query("json.items[].id")
       }}
-  when: network_class_check is success and (network_class_check.json.size | default(0)) > 0
+  when: network_class_check is success and network_class_check.json.get('items', []) | length > 0
 
 - name: Update existing NetworkClass
   loop: "{{ osac_network_classes }}"
diff --git a/collections/ansible_collections/osac/service/roles/publish_templates/tests/mock_api_server.py b/collections/ansible_collections/osac/service/roles/publish_templates/tests/mock_api_server.py
new file mode 100644
index 000000000..cc213eeb2
--- /dev/null
+++ b/collections/ansible_collections/osac/service/roles/publish_templates/tests/mock_api_server.py
@@ -0,0 +1,111 @@
+"""Minimal mock HTTP server for publish_templates role tests.
+
+Simulates the fulfillment-service private API list/create/update endpoints
+for cluster_templates, compute_instance_templates, and network_classes.
+
+Usage:
+    python mock_api_server.py [port] [scenario]
+
+Scenarios:
+    empty    - All endpoints return {"items": []} with no size field (proto3 omit)
+    populated - Endpoints return items with size field present
+    no_items_key - Response is {} (edge case: no items key at all)
+"""
+
+import json
+import sys
+from http.server import HTTPServer, BaseHTTPRequestHandler
+
+SCENARIO = "empty"
+# Track API calls for test verification
+CALL_LOG = []
+
+POPULATED_RESPONSES = {
+    "/api/private/v1/cluster_templates": {
+        "size": 1,
+        "total": 1,
+        "items": [{"id": "existing-cluster-template", "title": "Test Cluster"}],
+    },
+    "/api/private/v1/compute_instance_templates": {
+        "size": 1,
+        "total": 1,
+        "items": [{"id": "existing-ci-template", "title": "Test CI"}],
+    },
+    "/api/private/v1/network_classes": {
+        "size": 1,
+        "total": 1,
+        "items": [{"id": "existing-network-class", "title": "Test NC"}],
+    },
+}
+
+
+class MockHandler(BaseHTTPRequestHandler):
+    def do_GET(self):
+        path = self.path.split("?")[0]
+
+        if path == "/_calls":
+            self._respond(200, CALL_LOG)
+            return
+
+        if path == "/_reset":
+            CALL_LOG.clear()
+            self._respond(200, {"status": "reset"})
+            return
+
+        CALL_LOG.append({"method": "GET", "path": path})
+
+        if SCENARIO == "empty":
+            self._respond(200, {"items": []})
+        elif SCENARIO == "no_items_key":
+            self._respond(200, {})
+        elif SCENARIO == "populated":
+            base_path = path.rstrip("/")
+            # If path has an ID suffix (e.g. /api/.../templates/some-id), use base
+            for endpoint, data in POPULATED_RESPONSES.items():
+                if base_path == endpoint:
+                    self._respond(200, data)
+                    return
+            self._respond(200, {"items": []})
+        else:
+            self._respond(200, {"items": []})
+
+    def do_POST(self):
+        path = self.path.split("?")[0]
+        content_length = int(self.headers.get("Content-Length", 0))
+        body = self.rfile.read(content_length) if content_length else b""
+        CALL_LOG.append({
+            "method": "POST",
+            "path": path,
+            "body": json.loads(body) if body else None,
+        })
+        self._respond(200, {"id": "new-item", "status": "created"})
+
+    def do_PATCH(self):
+        path = self.path.split("?")[0]
+        content_length = int(self.headers.get("Content-Length", 0))
+        body = self.rfile.read(content_length) if content_length else b""
+        CALL_LOG.append({
+            "method": "PATCH",
+            "path": path,
+            "body": json.loads(body) if body else None,
+        })
+        self._respond(200, {"id": "updated-item", "status": "updated"})
+
+    def _respond(self, status, data):
+        self.send_response(status)
+        self.send_header("Content-Type", "application/json")
+        self.end_headers()
+        self.wfile.write(json.dumps(data).encode())
+
+    def log_message(self, format, *args):
+        pass  # Suppress request logging
+
+
+if __name__ == "__main__":
+    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
+    SCENARIO = sys.argv[2] if len(sys.argv) > 2 else "empty"
+    HTTPServer.allow_reuse_address = True
+    server = HTTPServer(("127.0.0.1", port), MockHandler)
+    print(f"Mock API server running on port {port} (scenario: {SCENARIO})")
+    sys.stdout.flush()
+    server.serve_forever()
diff --git a/collections/ansible_collections/osac/service/roles/publish_templates/tests/test.yml b/collections/ansible_collections/osac/service/roles/publish_templates/tests/test.yml
new file mode 100644
index 000000000..4302b92a2
--- /dev/null
+++ b/collections/ansible_collections/osac/service/roles/publish_templates/tests/test.yml
@@ -0,0 +1,255 @@
+---
+# Test playbook for osac.service.publish_templates role.
+# Each play is guarded by a `when` condition with bool coercion -- only the
+# play whose variable evaluates to true will run. Pass exactly one variable
+# per invocation.
+#
+# These tests use a Python mock HTTP server to simulate the fulfillment-service
+# API, so they can run without any external dependencies.
+#
+# Required variables for every test:
+#   test_mock_port:  Port for the mock HTTP server (default: 18081)
+#
+#   Test 1 (empty API responses -- the MGMT-23770 bug scenario):
+#     When no items exist, proto3 omits the `size` field entirely.
+#     The role must handle {"items": []} without a `size` key.
+#     Expected: All templates are created via POST, no PATCH calls.
+#     ansible-playbook ... -e test_empty=true
+#
+#   Test 2 (populated API responses -- existing items):
+#     When items already exist, the role should PATCH them.
+#     New items that don't exist should be POSTed.
+#     Expected: Existing templates updated via PATCH, new ones POSTed.
+#     ansible-playbook ... -e test_populated=true
+#
+#   Test 3 (no items key in response -- edge case):
+#     Some API responses might return {} without an items key.
+#     The role should treat this as empty and POST all templates.
+#     Expected: All templates created via POST.
+#     ansible-playbook ... -e test_no_items_key=true
+
+# ──────────────────────────────────────────────────────────────
+# Test 1: Empty API responses (the MGMT-23770 bug scenario)
+# Expected: role succeeds, all templates created via POST
+# ──────────────────────────────────────────────────────────────
+- name: "Test publish_templates -- empty API responses (MGMT-23770)"
+  hosts: localhost
+  gather_facts: false
+
+  vars:
+    test_mock_port: 18081
+
+  tasks:
+    - name: Kill any stale server on port
+      ansible.builtin.shell: "fuser -k {{ test_mock_port }}/tcp 2>/dev/null || true"
+      changed_when: false
+      when: test_empty | default(false) | bool
+
+    - name: Start mock API server (empty scenario)
+      ansible.builtin.command:
+        cmd: "python3 {{ playbook_dir }}/mock_api_server.py {{ test_mock_port }} empty"
+      changed_when: false
+      async: 30
+      poll: 0
+      register: mock_server
+      when: test_empty | default(false) | bool
+
+    - name: Wait for mock server to start
+      ansible.builtin.wait_for:
+        port: "{{ test_mock_port }}"
+        timeout: 5
+      when: test_empty | default(false) | bool
+
+    - name: Run publish_templates role against empty API
+      ansible.builtin.include_role:
+        name: osac.service.publish_templates
+      vars:
+        osac_fulfillment_service_uri: "http://127.0.0.1:{{ test_mock_port }}"
+        osac_fulfillment_service_token: "test-token"
+        publish_templates_validate_certs: false
+        osac_cluster_templates:
+          - id: "new-cluster-template"
+            title: "Test Cluster"
+        osac_compute_instance_templates:
+          - id: "new-ci-template"
+            title: "Test CI"
+        osac_network_classes:
+          - id: "new-network-class"
+            title: "Test NC"
+      when: test_empty | default(false) | bool
+
+    - name: Fetch API call log
+      ansible.builtin.uri:
+        url: "http://127.0.0.1:{{ test_mock_port }}/_calls"
+        return_content: true
+      register: call_log
+      when: test_empty | default(false) | bool
+
+    - name: Verify POST calls were made for all templates (empty = create new)
+      ansible.builtin.assert:
+        that:
+          - call_log.json | selectattr('method', 'equalto', 'POST') | list | length == 3
+          - call_log.json | selectattr('method', 'equalto', 'PATCH') | list | length == 0
+        fail_msg: >-
+          Expected 3 POSTs and 0 PATCHes for empty scenario.
+          Calls: {{ call_log.json }}
+        success_msg: "Empty scenario passed: all 3 templates created via POST"
+      when: test_empty | default(false) | bool
+
+    - name: Stop mock server
+      ansible.builtin.shell: "fuser -k {{ test_mock_port }}/tcp 2>/dev/null || true"
+      changed_when: false
+      when: test_empty | default(false) | bool
+
+# ──────────────────────────────────────────────────────────────
+# Test 2: Populated API responses (existing items)
+# Expected: existing templates PATCHed, new ones POSTed
+# ──────────────────────────────────────────────────────────────
+- name: "Test publish_templates -- populated API responses"
+  hosts: localhost
+  gather_facts: false
+
+  vars:
+    test_mock_port: 18081
+
+  tasks:
+    - name: Kill any stale server on port
+      ansible.builtin.shell: "fuser -k {{ test_mock_port }}/tcp 2>/dev/null || true"
+      changed_when: false
+      when: test_populated | default(false) | bool
+
+    - name: Start mock API server (populated scenario)
+      ansible.builtin.command:
+        cmd: "python3 {{ playbook_dir }}/mock_api_server.py {{ test_mock_port }} populated"
+      changed_when: false
+      async: 30
+      poll: 0
+      register: mock_server
+      when: test_populated | default(false) | bool
+
+    - name: Wait for mock server to start
+      ansible.builtin.wait_for:
+        port: "{{ test_mock_port }}"
+        timeout: 5
+      when: test_populated | default(false) | bool
+
+    - name: Run publish_templates role with existing item IDs
+      ansible.builtin.include_role:
+        name: osac.service.publish_templates
+      vars:
+        osac_fulfillment_service_uri: "http://127.0.0.1:{{ test_mock_port }}"
+        osac_fulfillment_service_token: "test-token"
+        publish_templates_validate_certs: false
+        osac_cluster_templates:
+          - id: "existing-cluster-template"
+            title: "Updated Cluster"
+          - id: "brand-new-cluster"
+            title: "New Cluster"
+        osac_compute_instance_templates:
+          - id: "existing-ci-template"
+            title: "Updated CI"
+        osac_network_classes:
+          - id: "existing-network-class"
+            title: "Updated NC"
+          - id: "brand-new-nc"
+            title: "New NC"
+      when: test_populated | default(false) | bool
+
+    - name: Fetch API call log
+      ansible.builtin.uri:
+        url: "http://127.0.0.1:{{ test_mock_port }}/_calls"
+        return_content: true
+      register: call_log
+      when: test_populated | default(false) | bool
+
+    - name: Verify PATCH calls for existing items and POST for new
+      ansible.builtin.assert:
+        that:
+          - call_log.json | selectattr('method', 'equalto', 'PATCH') | list | length == 3
+          - call_log.json | selectattr('method', 'equalto', 'POST') | list | length == 2
+          - call_log.json | selectattr('method', 'equalto', 'PATCH') | selectattr('path', 'contains', 'cluster_templates') | list | length == 1
+          - call_log.json | selectattr('method', 'equalto', 'PATCH') | selectattr('path', 'contains', 'compute_instance_templates') | list | length == 1
+          - call_log.json | selectattr('method', 'equalto', 'PATCH') | selectattr('path', 'contains', 'network_classes') | list | length == 1
+        fail_msg: >-
+          Expected 3 PATCHes (existing items) and 2 POSTs (new items).
+          Calls: {{ call_log.json }}
+        success_msg: "Populated scenario passed: 3 existing PATCHed, 2 new POSTed"
+      when: test_populated | default(false) | bool
+
+    - name: Stop mock server
+      ansible.builtin.shell: "fuser -k {{ test_mock_port }}/tcp 2>/dev/null || true"
+      changed_when: false
+      when: test_populated | default(false) | bool
+
+# ──────────────────────────────────────────────────────────────
+# Test 3: Edge case -- no items key at all in response
+# Expected: role succeeds, all templates created via POST
+# ──────────────────────────────────────────────────────────────
+- name: "Test publish_templates -- no items key edge case"
+  hosts: localhost
+  gather_facts: false
+
+  vars:
+    test_mock_port: 18081
+
+  tasks:
+    - name: Kill any stale server on port
+      ansible.builtin.shell: "fuser -k {{ test_mock_port }}/tcp 2>/dev/null || true"
+      changed_when: false
+      when: test_no_items_key | default(false) | bool
+
+    - name: Start mock API server (no_items_key scenario)
+      ansible.builtin.command:
+        cmd: "python3 {{ playbook_dir }}/mock_api_server.py {{ test_mock_port }} no_items_key"
+      changed_when: false
+      async: 30
+      poll: 0
+      register: mock_server
+      when: test_no_items_key | default(false) | bool
+
+    - name: Wait for mock server to start
+      ansible.builtin.wait_for:
+        port: "{{ test_mock_port }}"
+        timeout: 5
+      when: test_no_items_key | default(false) | bool
+
+    - name: Run publish_templates role against edge-case API
+      ansible.builtin.include_role:
+        name: osac.service.publish_templates
+      vars:
+        osac_fulfillment_service_uri: "http://127.0.0.1:{{ test_mock_port }}"
+        osac_fulfillment_service_token: "test-token"
+        publish_templates_validate_certs: false
+        osac_cluster_templates:
+          - id: "edge-case-cluster"
+            title: "Edge Cluster"
+        osac_compute_instance_templates:
+          - id: "edge-case-ci"
+            title: "Edge CI"
+        osac_network_classes:
+          - id: "edge-case-nc"
+            title: "Edge NC"
+      when: test_no_items_key | default(false) | bool
+
+    - name: Fetch API call log
+      ansible.builtin.uri:
+        url: "http://127.0.0.1:{{ test_mock_port }}/_calls"
+        return_content: true
+      register: call_log
+      when: test_no_items_key | default(false) | bool
+
+    - name: Verify all templates created via POST (no items = all new)
+      ansible.builtin.assert:
+        that:
+          - call_log.json | selectattr('method', 'equalto', 'POST') | list | length == 3
+          - call_log.json | selectattr('method', 'equalto', 'PATCH') | list | length == 0
+        fail_msg: >-
+          Expected 3 POSTs and 0 PATCHes for no-items-key scenario.
+          Calls: {{ call_log.json }}
+        success_msg: "No-items-key edge case passed: all 3 templates created via POST"
+      when: test_no_items_key | default(false) | bool
+
+    - name: Stop mock server
+      ansible.builtin.shell: "fuser -k {{ test_mock_port }}/tcp 2>/dev/null || true"
+      changed_when: false
+      when: test_no_items_key | default(false) | bool
```
