# Tag, Monitor & Verify (Steps 1 -- 6)

## Step 1: Fetch Tags and Determine Current Versions

Only fetch tags for the components selected in Step 0.5.

For each component repo, fetch upstream tags and find the latest release tag:

```bash
cd "$REPO_PATH"
git fetch upstream --tags
# List tags from upstream remote, filter to semver releases only
git ls-remote upstream --tags 'v*' | sed 's|.*/||; s|\^{}||' | grep -v '^api/' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
```

Tag selection: latest tag matching `v[0-9]+.[0-9]+.[0-9]+` (strict semver, no
pre-release suffixes). Ignore `api/v*` tags (protobuf API versions in
fulfillment-service). Parse `MAJOR.MINOR.PATCH` from the latest tag.

**OCI registry fallback:** If no git tags are found for a component, check the
OCI registry for the latest published chart version:

```bash
# For each chart name published by the component:
helm show chart oci://ghcr.io/osac-project/charts/<chart-name> 2>/dev/null | grep '^version:' | awk '{print $2}'
```

Chart names to check per component (use the main chart -- CRDs charts share
the same version, so checking either one is sufficient):
- fulfillment-service: `fulfillment-service`
- osac-operator: `osac-operator` (CRDs chart `osac-operator-crds` shares same version)
- osac-aap: `osac-aap`
- bare-metal-fulfillment-operator: `bare-metal-fulfillment-operator` (CRDs chart shares same version)
- osac-ui: `osac-ui`
- osac (umbrella): `osac`

If an OCI version is found but no git tag exists, use the OCI version as the
current version for computing the next version (patch bump). The component will
be tagged with the new version in Step 4 -- there is no need to backfill the
old tag. Show the version source in the Source column of the plan table.

If neither git tags nor OCI charts are found, treat the component as
unpublished and propose `v0.0.1` as the first version.

## Step 2: Compute Next Versions

- Default: increment PATCH by 1 for each component
- Apply user-specified version overrides from Step 0
- Apply `--skip`/`--only` filters

Print the computed versions using a box-drawing ASCII table:

```text
┌─────────────────────────────────┬─────────────────┬─────────────┬─────────┐
│            Component            │     Current     │   Source    │  Next   │
├─────────────────────────────────┼─────────────────┼─────────────┼─────────┤
│ fulfillment-service             │ v0.0.69         │ git tag     │ v0.0.70 │
├─────────────────────────────────┼─────────────────┼─────────────┼─────────┤
│ osac-operator                   │ v0.0.2          │ git tag     │ v0.0.3  │
├─────────────────────────────────┼─────────────────┼─────────────┼─────────┤
│ osac-aap                        │ v0.0.4          │ git tag     │ v0.0.5  │
├─────────────────────────────────┼─────────────────┼─────────────┼─────────┤
│ bare-metal-fulfillment-operator │ (none)          │ unpublished │ v0.0.1  │
├─────────────────────────────────┼─────────────────┼─────────────┼─────────┤
│ osac-ui                         │ (none)          │ unpublished │ v0.0.1  │
├─────────────────────────────────┼─────────────────┼─────────────┼─────────┤
│ osac (umbrella)                 │ v0.0.2          │ OCI         │ v0.0.3  │
└─────────────────────────────────┴─────────────────┴─────────────┴─────────┘
```

## Step 3: Present Release Plan (AskUserQuestion)

Show the same table from Step 2 in the AskUserQuestion prompt, prefixed with
the release reason and suffixed with "All tags will be created on
upstream/main."

Options:
- A) Proceed with these versions
- B) Change versions (re-enter Step 2 with user edits)
- C) Cancel

If B, ask what to change, update the plan, and re-present.
If C, stop.

## Step 4: Tag and Push Components

For each selected component (fulfillment-service, osac-operator, osac-aap,
bare-metal-fulfillment-operator, osac-ui):

1. Check if tag already exists and compare SHAs:
   ```bash
   TAG_SHA=$(git ls-remote upstream --tags "v<VERSION>" | awk '{print $1}')
   MAIN_SHA=$(git rev-parse upstream/main)
   ```
2. If `TAG_SHA` is empty, tag does not exist -- proceed to step 5.
3. If `TAG_SHA == MAIN_SHA`, skip tagging (already tagged on the correct
   commit). Proceed to monitoring.
4. If `TAG_SHA != MAIN_SHA`, tag exists on a different commit. Ask:
   - A) Delete and re-tag
   - B) Skip this component (umbrella uses old version -- warn user)
   - C) Abort entire release
5. Tag `upstream/main`: `git tag v<VERSION> upstream/main`
6. Push tag: `git push upstream v<VERSION>`
7. If push fails after previous repos succeeded, offer:
   - A) Rollback all tags pushed so far in this release (for each previously
     tagged component: `git push upstream :refs/tags/v<THAT_COMPONENT_VERSION>`)
   - B) Retry this repo
   - C) Abort and investigate manually

**Important:** Always tag `upstream/main`, never a local branch.

## Step 5: Monitor Publish Workflows

After all tags are pushed, wait 10 seconds for GitHub to register the
workflows, then monitor each component:

1. Find the workflow run triggered by the tag:
   ```bash
   gh run list --repo osac-project/<repo> -w publish-charts.yaml --limit 5 \
     --json databaseId,status,conclusion,event,headBranch \
     --jq '.[] | select(.headBranch == "v<VERSION>")'
   ```
   Match by `headBranch == tag name` for reliable run identification.
   If no matching run is found after 30 seconds, warn the user and ask to retry
   or investigate.

2. Poll the specific run ID every 15 seconds:
   ```bash
   gh run view <RUN_ID> --repo osac-project/<repo> --json status,conclusion
   ```

3. Timeout: 5 minutes per workflow run, starting when polling begins for that
   specific run. Interactive steps do not eat into the timeout.

4. Show real-time status using a box-drawing ASCII table:

   ```text
   ┌─────────────────────────────────┬────────────────┬─────────────┐
   │ Component                       │ Workflow       │ Status      │
   ├─────────────────────────────────┼────────────────┼─────────────┤
   │ fulfillment-service             │ publish-charts │ completed   │
   │ osac-operator                   │ publish-charts │ in_progress │
   │ osac-aap                        │ publish-charts │ polling...  │
   │ bare-metal-fulfillment-operator │ publish-charts │ polling...  │
   │ osac-ui                         │ publish-charts │ polling...  │
   └─────────────────────────────────┴────────────────┴─────────────┘
   ```

**On failure:** If any workflow fails:
1. Fetch the failed workflow logs: `gh run view <RUN_ID> --repo osac-project/<repo> --log-failed`
2. Show the error to the user
3. Ask whether to:
   - A) Retry (delete tag, re-tag, re-push)
   - B) Skip this component and continue
   - C) Abort the entire release

## Step 6: Verify Chart Publication

For each published chart, verify it exists in the OCI registry:

```bash
helm show chart oci://ghcr.io/osac-project/charts/<chart-name> --version <VERSION>
```

Charts to verify per component:
- fulfillment-service: `fulfillment-service`
- osac-operator: `osac-operator` AND `osac-operator-crds` (both must exist)
- osac-aap: `osac-aap`
- bare-metal-fulfillment-operator: `bare-metal-fulfillment-operator` AND `bare-metal-fulfillment-operator-crds` (both must exist)
- osac-ui: `osac-ui`

If a chart is not found, wait 60 seconds and retry (up to 2 retries). For
osac-operator and bare-metal-fulfillment-operator: verify both charts exist. The
CRDs chart may publish slower from the same workflow. If still missing after
retries, ask user to investigate.
