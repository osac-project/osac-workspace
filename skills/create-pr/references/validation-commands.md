# Step 2 Validation Commands

Per-component build/lint/test commands for `create-pr` Step 2. Run every
block matching `$TOUCHED_COMPONENTS` — if it lists more than one, run
**every** matching block in the same pass; that's the point of one PR
covering multiple mono-repo components. Read the component's CLAUDE.md if
unsure which commands apply.

### fulfillment-service

```bash
cd "$REPO_DIR/fulfillment-service"
gofmt -s -w . && git diff --exit-code
buf generate && git diff --exit-code
go build ./...
ginkgo run -r internal
uv run dev.py lint
```

### osac-operator

```bash
cd "$REPO_DIR/osac-operator"
make fmt && git diff --exit-code
make lint
make build
make test
make manifests generate && git diff --exit-code
```

### osac-aap

```bash
cd "$REPO_DIR/osac-aap"
make test
uv run ansible-lint
```

### osac-installer

```bash
cd "$REPO_DIR/osac-installer"
helm dependency build charts/osac/
helm lint charts/osac-operators/
helm lint charts/osac-prereqs/
for f in values/*/values.yaml; do
  helm template osac charts/osac/ --values "$f" \
    --set service.externalHostname=fulfillment-api.example.com \
    --set service.internalHostname=fulfillment-internal-api.example.com \
    > /dev/null
done
```

Reproduces the environment-values templating step of the `helm-lint-installer` job in
`osac`'s `.github/workflows/helm-lint.yaml` — not full CI parity (that job also runs
`ct lint --all --config ct.yaml`, templates `charts/osac/ci/*-values.yaml`, and validates
`values.schema.json` is well-formed JSON; see the workflow for those). `charts/osac/`'s
values schema requires `service.externalHostname`/`internalHostname`, which every real
values file leaves blank for runtime injection, so linting/templating the umbrella chart
needs the same placeholder `--set` overrides CI uses — a bare `helm lint charts/osac/`
(e.g. via `make helm-lint`) fails on schema validation regardless of what the PR actually
changes.

Image tags in `values/*/values.yaml` are unpinned (`latest`) for every mono-repo
component, including `osac-csi-driver` — `scripts/sync-image-tags.sh` was removed
upstream (`OSAC-3367`); there is no sync step to run. Real release tags are set
automatically by `osac`'s own CI at release time, not by a feature PR.

### bare-metal-fulfillment-operator

```bash
cd "$REPO_DIR/bare-metal-fulfillment-operator"
make fmt && git diff --exit-code
make lint
make build
make test
make manifests generate && git diff --exit-code
```

### osac-csi-driver

```bash
cd "$REPO_DIR/osac-csi-driver"
make fmt && git diff --exit-code
make lint
make build
make test
```

No CRDs, so no `make manifests`/`generate` step (unlike `osac-operator` and
`bare-metal-fulfillment-operator`).

### Other repos

Read the component's CLAUDE.md or Makefile for the correct validation sequence.
