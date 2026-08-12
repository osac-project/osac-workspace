# Step 3 File Classification

Per-component production/test/excluded path rules for `create-pr` Step 3's
test coverage advisory. For `osac`, only apply the row(s) matching
`$TOUCHED_COMPONENTS` (path patterns below already carry the mono-repo
subdirectory prefix).

| Component | Production files | Test files | Excluded (skip) |
|------|-----------------|------------|-----------------|
| **fulfillment-service** | `fulfillment-service/**/*.go` not `_test.go` | `fulfillment-service/**/*_test.go` | `fulfillment-service/internal/api/`, `fulfillment-service/**/*.pb.go`, `fulfillment-service/**/migrations/` |
| **osac-operator** | `osac-operator/**/*.go` not `_test.go` | `osac-operator/**/*_test.go` | `osac-operator/api/v1alpha1/zz_generated*`, `osac-operator/config/` |
| **osac-aap** | `osac-aap/collections/ansible_collections/osac/**/roles/**/tasks/*.yml`, `osac-aap/collections/ansible_collections/osac/**/plugins/**/*.py` | `osac-aap/tests/unit/**`, `osac-aap/tests/integration/targets/**` | `osac-aap/collections/ansible_collections/osac/**/meta/`, `osac-aap/docs/` |
| **osac-installer** | Skip this check entirely — Helm charts/values, no unit-testable production/test file split | — | — |
| **bare-metal-fulfillment-operator** | `bare-metal-fulfillment-operator/**/*.go` not `_test.go` | `bare-metal-fulfillment-operator/**/*_test.go` | `bare-metal-fulfillment-operator/api/v1alpha1/zz_generated*`, `bare-metal-fulfillment-operator/config/` |
| **osac-csi-driver** | `osac-csi-driver/**/*.go` not `_test.go` | `osac-csi-driver/**/*_test.go` | None — no generated code |

For each production file in the diff, check if a corresponding test file also appears in the diff. Matching rules:

- **Go:** `foo.go` → `foo_test.go` in the same directory
- **Ansible:** `collections/ansible_collections/osac/<ns>/roles/<role>/tasks/*.yml` → `osac-aap/tests/integration/targets/<role>/` has changes
- **Python:** `osac-aap/collections/ansible_collections/osac/**/plugins/**/*.py` → `osac-aap/tests/unit/**` has changes
