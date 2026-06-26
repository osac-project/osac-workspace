# Real Fix: osac-aap PR #254

## Title
MGMT-24061: disable scm_update_on_launch to speed up job processing

## Summary
## Summary

- `scm_update_on_launch: true` on the AAP project caused an SCM sync before every job execution, adding unnecessary overhead to every provisioning/deprovisioning operation
- Set `scm_update_on_launch: false` — SCM updates are already handled by the periodic `{{ aap_prefix }}-sync` schedule (every 10 minutes)

## Test plan

- [x] Config-as-code applies cleanly with updated project definition
- [x] AAP jobs launch without triggering an SCM sync

Fixes: https://redhat.atlassian.net/browse/MGMT-24061

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

* **Chores**
  * Updated project configuration: SCM repository updates will no longer trigger automatically when projects launch.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->

## Diff
```diff
diff --git a/collections/ansible_collections/osac/config_as_code/roles/aap/vars/controller.yml b/collections/ansible_collections/osac/config_as_code/roles/aap/vars/controller.yml
index 0d30b4b5b..0333b831b 100644
--- a/collections/ansible_collections/osac/config_as_code/roles/aap/vars/controller.yml
+++ b/collections/ansible_collections/osac/config_as_code/roles/aap/vars/controller.yml
@@ -8,7 +8,7 @@ controller_projects: # noqa: var-naming[no-role-prefix]
     description: "{{ aap_project_name }}'s project"
     organization: "{{ aap_organization_name }}"
     scm_clean: true
-    scm_update_on_launch: true
+    scm_update_on_launch: false
     scm_credential: ""
     update_project: true
     wait: true
```
