# Real Fix: fulfillment-service PR #364

## Title
MGMT-23402: add SecurityGroup to notification event type switch

## Summary
- Adds `SecurityGroup` case to the `setPayload` type switch in `generic_server.go`
- Without this, creating a SecurityGroup via the API returns HTTP 500 (`unknown object type '*privatev1.SecurityGroup'`)

## Test plan
- [x] Verified manually: SecurityGroup creation via REST API now succeeds
- [x] Full flow tested: SecurityGroup → AAP job → NetworkPolicy created in target namespace

🤖 Generated with [Claude Code](https://claude.com/claude-code)

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

* **Bug Fixes**
  * Enhanced handling of security group operations to ensure they are properly processed by the system.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->

## Diff
```diff
diff --git a/internal/servers/generic_server.go b/internal/servers/generic_server.go
index 31a44195..d1d92acc 100644
--- a/internal/servers/generic_server.go
+++ b/internal/servers/generic_server.go
@@ -718,6 +718,8 @@ func (s *GenericServer[O]) setPayload(event *privatev1.Event, object proto.Messa
 		event.SetVirtualNetwork(object)
 	case *privatev1.Subnet:
 		event.SetSubnet(object)
+	case *privatev1.SecurityGroup:
+		event.SetSecurityGroup(object)
 	default:
 		return fmt.Errorf("unknown object type '%T'", object)
 	}
```
