# Umbrella Chart & Summary (Steps 7 -- 9)

## Step 7: Publish Umbrella Chart

The osac-installer `publish-charts.yaml` workflow accepts `workflow_dispatch`
with explicit version inputs. Dispatch with the component versions just
published:

```bash
gh workflow run publish-charts.yaml \
  --repo osac-project/osac-installer \
  -f version=<UMBRELLA_VERSION> \
  -f operator_crds_version=<OPERATOR_VERSION> \
  -f operator_version=<OPERATOR_VERSION> \
  -f service_version=<SERVICE_VERSION> \
  -f aap_version=<AAP_VERSION> \
  -f bmf_crds_version=<BMF_VERSION> \
  -f bmf_version=<BMF_VERSION> \
  -f ui_version=<UI_VERSION>
```

The umbrella version is determined from osac-installer's latest tag + patch
bump. Using `workflow_dispatch` (not tag push) ensures the umbrella chart gets
the exact component versions just published, without needing to commit a
Chart.yaml update first.

Note: `operator_crds_version` uses the same version as `operator_version`
(both charts are published from the same osac-operator tag). Same applies to
`bmf_crds_version` and `bmf_version`.

**Skipped components:** For any component deselected in Step 0.5, use its
current published version (from the Step 1 git tag / OCI lookup) instead of a
newly computed version. The corresponding `-f` flag must still be included in
the dispatch command with the existing version.

## Step 8: Monitor and Verify Umbrella

Same polling pattern as Step 5 for the umbrella workflow. Since this is a
`workflow_dispatch` run (not a tag push), `headBranch` will be `main`, not a
tag name. Record a timestamp before dispatching, then find the run started
after that timestamp:

```bash
# Record dispatch time BEFORE running gh workflow run
DISPATCH_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# After dispatching, find the matching run
gh run list --repo osac-project/osac-installer -w publish-charts.yaml --limit 5 \
  --json databaseId,status,conclusion,event,createdAt \
  --jq "[.[] | select(.event == \"workflow_dispatch\" and .createdAt > \"$DISPATCH_TIME\")] | sort_by(.createdAt) | last"
```

If multiple `workflow_dispatch` runs are found after `DISPATCH_TIME`, use the
most recent one. Verify by polling the selected `databaseId` and confirming
its status progresses (queued -> in_progress -> completed).

After the workflow succeeds, verify:

```bash
helm show chart oci://ghcr.io/osac-project/charts/osac --version <UMBRELLA_VERSION>
```

Confirm the dependencies list shows the correct component versions.

**After successful verification**, tag osac-installer for version tracking:

```bash
cd "$OSAC_INSTALLER_PATH"
git fetch upstream --tags
git tag v<UMBRELLA_VERSION> upstream/main
git push upstream v<UMBRELLA_VERSION>
```

This creates a version record since `workflow_dispatch` does not create a tag
automatically.

## Step 9: Release Summary

Print a final summary using a box-drawing ASCII table:

```text
Release Complete! (Reason: <release reason from Step 0.5>)

┌────────────────────────────────────────┬─────────┬──────────────────────────────────────────────────────────────────────┐
│ Chart                                  │ Version │ Registry                                                           │
├────────────────────────────────────────┼─────────┼──────────────────────────────────────────────────────────────────────┤
│ fulfillment-service                    │ 0.0.70  │ oci://ghcr.io/osac-project/charts/fulfillment-service              │
│ osac-operator                          │ 0.0.3   │ oci://ghcr.io/osac-project/charts/osac-operator                    │
│ osac-operator-crds                     │ 0.0.3   │ oci://ghcr.io/osac-project/charts/osac-operator-crds               │
│ osac-aap                               │ 0.0.5   │ oci://ghcr.io/osac-project/charts/osac-aap                         │
│ bare-metal-fulfillment-operator        │ 0.0.2   │ oci://ghcr.io/osac-project/charts/bare-metal-fulfillment-operator  │
│ bare-metal-fulfillment-operator-crds   │ 0.0.2   │ oci://ghcr.io/osac-project/charts/bare-metal-fulfillment-operator… │
│ osac-ui                                │ 0.0.1   │ oci://ghcr.io/osac-project/charts/osac-ui                           │
│ osac (umbrella)                        │ 0.0.3   │ oci://ghcr.io/osac-project/charts/osac                             │
└────────────────────────────────────────┴─────────┴──────────────────────────────────────────────────────────────────────┘

To install:
  helm install osac oci://ghcr.io/osac-project/charts/osac --version <UMBRELLA_VERSION>
```

If any components were skipped, note which ones and what versions the umbrella
chart uses for them.
