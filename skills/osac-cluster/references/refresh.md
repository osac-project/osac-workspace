# Refresh the OSAC stack

**Read this when applying latest component images to a snapshot cluster** (after boot).

The snapshot contains a frozen version of OSAC. To apply the latest component images (operator, fulfillment-service, AAP), run the refresh script.

**Why refresh?** The flavor was built at a specific point in time. Your code (or `main`) has likely moved since then. Refresh does a `helm upgrade` with the latest image tags from the osac-installer repo, plus fixes stale routes, certificates, and Keycloak configuration.

## Prerequisites

You need the osac-installer repo cloned, submodules initialized, and up to date:

```bash
git clone https://github.com/osac-project/osac-installer.git
cd osac-installer
git submodule update --init --recursive
WORKSPACE_ROOT=$(cd .. && git rev-parse --show-toplevel 2>/dev/null || echo "$(pwd)")
eval "$("${WORKSPACE_ROOT}/tools/resolve-remotes.sh" .)" || { echo "Failed to resolve remotes"; exit 1; }
git fetch "$UPSTREAM_REMOTE" main && git rebase "$UPSTREAM_REMOTE/main"
```

The refresh script also requires:
- **Tools on your laptop:** `python3`, `oc`, `helm`, `curl`, `jq`, and the `osac` CLI
- **AAP license file** at `values/<env>/license.zip` (e.g., `values/vmaas-ci/license.zip`)
- **Quay pull secret** at `values/<env>/pull-secret.json` (e.g., `values/vmaas-ci/pull-secret.json`)

See [pull-secret-and-license.md](pull-secret-and-license.md) for how to get these files.

## Verify refresh parameters are current

Before running refresh, check the CI boot script to confirm the env vars below haven't changed:

```bash
curl -s https://raw.githubusercontent.com/openshift/release/master/ci-operator/step-registry/osac-project/cluster-tool/boot/osac-project-cluster-tool-boot-commands.sh | grep -A5 refresh-after-snapshot
```

Verify `VALUES_FILE`, `INSTALLER_NAMESPACE`, `INSTALLER_VM_TEMPLATE`, and `INSTALLER_CLUSTER_TEMPLATE` match what's documented below.

## Refresh for VMaaS

```bash
export KUBECONFIG=~/.kube/<name>.kubeconfig
cd <path-to-osac-installer>

env \
    VALUES_FILE=values/vmaas-ci/values.yaml \
    INSTALLER_NAMESPACE=osac-e2e-ci \
    INSTALLER_VM_TEMPLATE=osac.templates.ocp_virt_vm \
    python3 ./scripts/refresh-after-snapshot.py
```

## Refresh for CaaS

```bash
export KUBECONFIG=~/.kube/<name>.kubeconfig
cd <path-to-osac-installer>

env \
    VALUES_FILE=values/caas-ci/values.yaml \
    INSTALLER_NAMESPACE=osac-e2e-ci \
    INSTALLER_CLUSTER_TEMPLATE=osac.templates.ocp_ci_small \
    python3 ./scripts/refresh-after-snapshot.py
```

## What refresh does (4 phases, ~10-20 minutes)

| Phase | What |
|-------|------|
| 1. Fix identity | Patch stale routes, refresh certificates, configure MetalLB subnet |
| 2. Prepare | Sync Keycloak realm, create secrets, deploy fulfillment-db |
| 3. Deploy | `helm upgrade osac` with latest images, wait for rollouts, configure AAP |
| 4. Post-flight | Create AAP token, create hub, publish templates, create tenants |

## Environment variables reference

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `VALUES_FILE` | Yes | — | Helm values file path (relative to repo root) |
| `INSTALLER_NAMESPACE` | No | `osac-e2e-ci` | Kubernetes namespace where OSAC is deployed |
| `INSTALLER_VM_TEMPLATE` | VMaaS | `""` | Template name to wait for after publish |
| `INSTALLER_CLUSTER_TEMPLATE` | CaaS | `""` | Cluster template name to wait for after publish |
| `KUBECONFIG` | Yes | — | Path to the cluster's kubeconfig (set in your shell) |

## Testing PR changes with refresh

To test a PR's component image on a snapshot cluster, edit the values file before running refresh:

```bash
cd osac-installer

# Override the operator image to a PR build
sed -i 's|ghcr.io/osac-project/osac-operator:sha-.*|ghcr.io/osac-project/osac-operator:sha-YOURSHA|' values/vmaas-ci/values.yaml

# Then run refresh as normal
```

## CaaS: Additional agent setup

CaaS clusters need an agent VM for hosted cluster provisioning. After refresh:

```bash
# Get the server's SSH target from cluster-tool config
SERVER_HOST=$(python3 -c "import json; print(json.load(open('$HOME/.config/cluster-tool/servers.json'))['servers']['<alias>']['host'])")

# Get the libvirt network name for this clone
LIBVIRT_NETWORK=$(ssh -o StrictHostKeyChecking=no "$SERVER_HOST" \
    "virsh net-list --name | grep '<name>'" | head -1 | tr -d '[:space:]')

# Create SSH config for the script
SSH_CONFIG=$(mktemp)
cat > "$SSH_CONFIG" <<EOF
Host ci_machine
    HostName ${SERVER_HOST#*@}
    User ${SERVER_HOST%%@*}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF

# Run agent setup
env \
    LIBVIRT_NETWORK="$LIBVIRT_NETWORK" \
    SSH_CONFIG="$SSH_CONFIG" \
    INSTALLER_NAMESPACE=osac-e2e-ci \
    AGENT_VM_NAME="agent-<name>" \
    ./scripts/setup-caas-agents.sh

rm -f "$SSH_CONFIG"
```

This creates an InfraEnv, boots an agent VM, and approves it for hosted cluster provisioning.
