---
name: osac-cluster
description: Boot, manage, or troubleshoot OSAC development clusters using cluster-tool.
when_to_use: Use when the user needs an OSAC development cluster, wants to test locally, says "spawn a cluster", "boot a cluster", "I need a dev environment", asks about cluster-tool, or wants to run E2E tests on a real cluster. Also use when connecting to baremetal servers, pulling flavors, running refresh, or troubleshooting cluster issues.
---

# OSAC Cluster — From Zero to Running Cluster

Boot a fully working OSAC development cluster from a snapshot in ~30 minutes (first time) or ~20 minutes (flavor already pulled). Each cluster is an independent OpenShift SNO with all OSAC components pre-installed.

## When to Use

- "I need a cluster" / "spawn a cluster" / "boot a cluster"
- "How do I set up cluster-tool?" / "How do I get a dev environment?"
- "Run the E2E tests locally" / "Test my changes on a real cluster"
- "Connect to this machine" / "Add a server"
- "What flavors are available?" / "Pull the VMaaS flavor"
- "Destroy my clusters" / "Clean up"
- "Run refresh" / "Update the OSAC stack on my cluster"

## Overview

```
Developer laptop  --SSH-->  Baremetal server (VMs run here)
     |                           |
     | cluster-tool              | libvirt VM (OpenShift SNO)
     | (Python CLI)              | 64 GB RAM, 16 vCPUs
     |                           |
     | ~/.kube/<name>.kubeconfig | HAProxy (SNI routing)
     | /etc/NetworkManager/      | dnsmasq (DNS)
     |   dnsmasq.d/              |
```

cluster-tool runs on your laptop and manages VMs on remote baremetal servers over SSH. Flavors (pre-built snapshots) are distributed via OCI registries (Quay.io). Each clone gets a unique identity — new certs, IP, hostname — via the recert tool.

---

## Step 1: Install cluster-tool

cluster-tool is a single Python 3 file. No pip install, no build step.

```bash
git clone https://github.com/osac-project/cluster-tool.git
cd cluster-tool
./cluster-tool --help
```

Optionally symlink it to your PATH:

```bash
ln -sf "$(pwd)/cluster-tool" ~/.local/bin/cluster-tool
```

### Client prerequisites

| Requirement | Why |
|-------------|-----|
| Linux with NetworkManager | DNS resolution via dnsmasq. Fedora, RHEL, CentOS all work. No macOS/Windows — see [Mac/Windows users](#macwindows-users) below. |
| Python 3 | cluster-tool is a Python script (stdlib only, no pip packages) |
| `oc` CLI | Needed for refresh and tests. Install from [mirror.openshift.com](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/) |
| `helm` | Needed for refresh (OSAC deploys via Helm). Install from [helm.sh](https://helm.sh/docs/intro/install/) |

### One-time client DNS setup

This configures dnsmasq so your laptop can resolve cluster domains (e.g., `*.apps.sno-abc.redhat.com`):

```bash
sudo ./cluster-tool setup client
```

What it does:
1. Installs dnsmasq
2. Configures NetworkManager to use dnsmasq as DNS backend
3. Grants your user permission to reload NetworkManager without sudo (polkit rule)
4. Verifies `/etc/resolv.conf` points to `127.0.0.1`

**You only run this once per laptop.**

### Mac/Windows users

**Before proceeding, check the user's OS:**

```bash
uname -s   # Darwin = macOS, Linux = OK
```

If the user is on macOS or Windows, **stop** — the client-side DNS setup (`setup client`) requires Linux with NetworkManager. Instead, tell them to run cluster-tool directly on the baremetal server in **local mode**:

```bash
ssh root@server.example.com
git clone https://github.com/osac-project/cluster-tool.git
cd cluster-tool
./cluster-tool connect local --host local --data-path /home/cluster-tool
./cluster-tool pull quay.io/rh-ee-ovishlit/cluster-flavors:vmaas
./cluster-tool boot --flavor vmaas --name dev --pull-secret /path/to/pull-secret.json
export KUBECONFIG=~/.kube/dev.kubeconfig
```

In local mode, cluster-tool runs commands directly instead of over SSH. DNS and HAProxy are configured on the server itself. The user works on the baremetal machine directly (oc, helm, kubectl all run there).

---

## Step 2: Connect to a baremetal server

You need a Linux server with root SSH access and enough resources (see sizing below).

### Check server resources first

Before connecting, verify the server has enough RAM and disk:

```bash
ssh root@<server-hostname> "free -g | awk '/Mem:/{print \$2}'"
ssh root@<server-hostname> "df -h / /home /var /data 2>/dev/null"
```

### Server sizing

| Resource | Per cluster | Notes |
|----------|------------|-------|
| RAM | 64 GB | Each SNO VM uses 64 GB |
| vCPUs | 16 | Each SNO VM uses 16 cores |
| Disk | ~100 GB for the flavor + small overlay per clone | Use the largest partition |

**How many clusters can I run?** `floor(total_RAM / 64)`. A 256 GB server = 4 clusters max.

### Connect

```bash
cluster-tool connect <alias> --host root@<server-hostname> --data-path <path>
```

- **`<alias>`** — short name you'll use in commands (e.g., `myserver`)
- **`--host`** — SSH target with root access. Run `ssh-copy-id root@<server>` first if needed.
- **`--data-path`** — directory on the server for storing disk images (60-90 GB each). **Check which partition has the most space first** — the root partition (`/`) is usually too small:
  ```bash
  ssh root@<server-hostname> "df -h --output=avail,target | sort -rh | head -5"
  ```
  Use the largest partition (e.g., `/home/cluster-tool` if `/home` is biggest, `/data/cluster-tool` if `/data` is).

If you omit `--data-path`, cluster-tool auto-detects the largest partition.

**Example:**

```bash
cluster-tool connect myserver --host root@server.example.com --data-path /home/cluster-tool
```

What `connect` does on the server:
1. Installs libvirt, qemu-kvm, podman, pigz, haproxy, skopeo, zstd
2. Configures HAProxy with SNI-based routing (ports 6443, 443, 80)
3. Generates an ed25519 SSH keypair for VM access
4. Creates the data directory structure
5. Registers the server locally in `~/.config/cluster-tool/servers.json`

**connect is idempotent** — safe to run multiple times, never overwrites existing config.

### List and manage servers

```bash
cluster-tool servers             # List all connected servers
cluster-tool use <alias>         # Set default server (used when --server is omitted)
```

---

## Step 3: Pull a flavor

A flavor is a reusable snapshot — golden disk images with OpenShift + OSAC components pre-installed. You pull a flavor once per server, then boot clusters from it instantly.

### Which flavor do I need?

| OSAC deployment type | Flavor | OCI image |
|---------------------|--------|-----------|
| **VMaaS** (compute instances, VMs) | `vmaas` | `quay.io/rh-ee-ovishlit/cluster-flavors:vmaas` |
| **CaaS** (hosted clusters) | `caas` | `quay.io/rh-ee-ovishlit/cluster-flavors:caas` |

**VMaaS** includes: OpenShift SNO + LVMS + CNV + cert-manager + Keycloak + AAP + OSAC (VM provisioning).

**CaaS** includes: OpenShift SNO + LVMS + MetalLB + MCE + cert-manager + Keycloak + AAP + OSAC (cluster provisioning).

### Pull the flavor

```bash
cluster-tool pull quay.io/rh-ee-ovishlit/cluster-flavors:vmaas --server <alias>
```

This downloads ~60-90 GB from Quay.io. Takes ~10-15 minutes depending on network speed. You only need to do this once per server per flavor — the flavor is stored locally on the server.

### Check available flavors

```bash
cluster-tool flavors                      # On default server
cluster-tool flavors --server <alias>     # On specific server
```

---

## Step 4: Boot a cluster

```bash
cluster-tool boot --flavor vmaas --name <name> --pull-secret <path-to-pull-secret.json> --server <alias>
```

- **`--flavor`** — which snapshot to boot from (must be pulled first)
- **`--name`** — short identifier, **max 8 characters** (e.g., `dev`, `test1`, `pr-42`). Linux bridge names are `br-{name[:8]}`, so longer names cause collisions.
- **`--pull-secret`** — **(mandatory)** path to a pull secret JSON file for authenticated registry access. See [Obtaining a Pull Secret and AAP License](#obtaining-a-pull-secret-and-aap-license) below.
- **`--server`** — which server to boot on (omit to use default)

**Example:**

```bash
cluster-tool boot --flavor vmaas --name dev --pull-secret values/vmaas-ci/pull-secret.json --server myserver
```

Takes ~10 minutes. What happens:
1. Creates copy-on-write disk overlays from the golden snapshot
2. Creates an isolated libvirt network with unique subnet
3. Boots the VM
4. Runs recert to regenerate all certificates with new identity
5. Waits for the Kubernetes API and all ClusterOperators
6. Writes kubeconfig to `~/.kube/<name>.kubeconfig` and prints the path
7. Adds dnsmasq DNS entry on your laptop
8. Adds HAProxy SNI routes on the server

### Use the cluster

```bash
export KUBECONFIG=~/.kube/dev.kubeconfig   # boot prints this path when it finishes
oc get nodes
oc get co        # ClusterOperators — all should be Available
```

### Boot is transactional

If any step fails, all resources are rolled back automatically. No orphaned VMs or networks.

### Parallel boots

Multiple boot/destroy commands can run in parallel safely — cluster-tool uses file locking internally.

```bash
cluster-tool boot --flavor vmaas --name test1 --pull-secret values/vmaas-ci/pull-secret.json --server myserver &
cluster-tool boot --flavor vmaas --name test2 --pull-secret values/vmaas-ci/pull-secret.json --server myserver &
wait
```

---

## Obtaining a Pull Secret and AAP License

Both the `boot` command and the refresh script require a **pull secret** and an **AAP license**. Place these files in the osac-installer repo under the values directory for your deployment type:

| Deployment type | Pull secret path | AAP license path |
|----------------|-----------------|-----------------|
| VMaaS | `values/vmaas-ci/pull-secret.json` | `values/vmaas-ci/license.zip` |
| CaaS | `values/caas-ci/pull-secret.json` | `values/caas-ci/license.zip` |

### Pull secret

A pull secret provides credentials for authenticated container registries (Quay.io, registry.redhat.io). Obtain one from the [Red Hat Hybrid Cloud Console](https://console.redhat.com/openshift/install/pull-secret).

Download the JSON file and place it at the path above (e.g., `values/vmaas-ci/pull-secret.json`).

### AAP license

The AAP bootstrap job requires a subscription manifest (`license.zip`). Obtain it from the [Red Hat Customer Portal](https://access.redhat.com/) under **Subscriptions > Subscription Allocations > Export Manifest**.

Place `license.zip` at the path above (e.g., `values/vmaas-ci/license.zip`).

For full details, see [Section 2.4 of the Helm Deployment Guide](https://github.com/osac-project/osac-installer/blob/main/docs/helm-deployment-guide.md#24-aap-license).

---

## Step 5: Refresh the OSAC stack

The snapshot contains a frozen version of OSAC. To apply the latest component images (operator, fulfillment-service, AAP), run the refresh script.

**Why refresh?** The flavor was built at a specific point in time. Your code (or `main`) has likely moved since then. Refresh does a `helm upgrade` with the latest image tags from the osac-installer repo, plus fixes stale routes, certificates, and Keycloak configuration.

### Prerequisites

You need the osac-installer repo cloned, submodules initialized, and up to date:

```bash
git clone https://github.com/osac-project/osac-installer.git
cd osac-installer
git submodule update --init --recursive
git fetch origin main && git rebase origin/main
```

The refresh script also requires:
- **Tools on your laptop:** `python3`, `oc`, `helm`, `curl`, `jq`, and the `osac` CLI
- **AAP license file** at `values/<env>/license.zip` (e.g., `values/vmaas-ci/license.zip`)
- **Quay pull secret** at `values/<env>/pull-secret.json` (e.g., `values/vmaas-ci/pull-secret.json`)

See [Obtaining a Pull Secret and AAP License](#obtaining-a-pull-secret-and-aap-license) for how to get these files.

### Verify refresh parameters are current

Before running refresh, check the CI boot script to confirm the env vars below haven't changed:

```bash
curl -s https://raw.githubusercontent.com/openshift/release/master/ci-operator/step-registry/osac-project/cluster-tool/boot/osac-project-cluster-tool-boot-commands.sh | grep -A5 refresh-after-snapshot
```

Verify `VALUES_FILE`, `INSTALLER_NAMESPACE`, `INSTALLER_VM_TEMPLATE`, and `INSTALLER_CLUSTER_TEMPLATE` match what's documented below.

### Refresh for VMaaS

```bash
export KUBECONFIG=~/.kube/<name>.kubeconfig
cd <path-to-osac-installer>

env \
    VALUES_FILE=values/vmaas-ci/values.yaml \
    INSTALLER_NAMESPACE=osac-e2e-ci \
    INSTALLER_VM_TEMPLATE=osac.templates.ocp_virt_vm \
    python3 ./scripts/refresh-after-snapshot.py
```

### Refresh for CaaS

```bash
export KUBECONFIG=~/.kube/<name>.kubeconfig
cd <path-to-osac-installer>

env \
    VALUES_FILE=values/caas-ci/values.yaml \
    INSTALLER_NAMESPACE=osac-e2e-ci \
    INSTALLER_CLUSTER_TEMPLATE=osac.templates.ocp_ci_small \
    python3 ./scripts/refresh-after-snapshot.py
```

### What refresh does (4 phases, ~10-20 minutes)

| Phase | What |
|-------|------|
| 1. Fix identity | Patch stale routes, refresh certificates, configure MetalLB subnet |
| 2. Prepare | Sync Keycloak realm, create secrets, deploy fulfillment-db |
| 3. Deploy | `helm upgrade osac` with latest images, wait for rollouts, configure AAP |
| 4. Post-flight | Create AAP token, create hub, publish templates, create tenants |

### Environment variables reference

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `VALUES_FILE` | Yes | — | Helm values file path (relative to repo root) |
| `INSTALLER_NAMESPACE` | No | `osac-e2e-ci` | Kubernetes namespace where OSAC is deployed |
| `INSTALLER_VM_TEMPLATE` | VMaaS | `""` | Template name to wait for after publish |
| `INSTALLER_CLUSTER_TEMPLATE` | CaaS | `""` | Cluster template name to wait for after publish |
| `KUBECONFIG` | Yes | — | Path to the cluster's kubeconfig (set in your shell) |

### Testing PR changes with refresh

To test a PR's component image on a snapshot cluster, edit the values file before running refresh:

```bash
cd osac-installer

# Override the operator image to a PR build
sed -i 's|ghcr.io/osac-project/osac-operator:sha-.*|ghcr.io/osac-project/osac-operator:sha-YOURSHA|' values/vmaas-ci/values.yaml

# Then run refresh as normal
```

### CaaS: Additional agent setup

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

---

## Step 6: Verify the cluster

```bash
cluster-tool verify <name> --server <alias>
```

Deploys a test pod that checks cluster DNS, external DNS resolution, and API access. Reports PASS/FAIL per check.

You can also verify manually:

```bash
export KUBECONFIG=~/.kube/<name>.kubeconfig
oc get nodes                   # Should show one Ready node
oc get co                      # All ClusterOperators should be Available
oc get pods -n osac-e2e-ci     # All pods should be Running (after refresh)
```

---

## If You Want to Run E2E Tests

After refresh, you can run the OSAC E2E test suite against your cluster.

### Prerequisites

```bash
git clone https://github.com/osac-project/osac-test-infra.git
cd osac-test-infra
pip install -e .
```

You also need the `osac` CLI binary. Check the test-infra repo for the current required version.

### VMaaS tests

```bash
export KUBECONFIG=~/.kube/<name>.kubeconfig
export OSAC_VM_KUBECONFIG=$KUBECONFIG
export OSAC_NAMESPACE=osac-e2e-ci
export OSAC_CLI_PATH=<path-to-osac-binary>

cd osac-test-infra
make test-vmaas
```

### CaaS tests

```bash
export KUBECONFIG=~/.kube/<name>.kubeconfig
export OSAC_VM_KUBECONFIG=$KUBECONFIG
export OSAC_NAMESPACE=osac-e2e-ci
export OSAC_CLI_PATH=<path-to-osac-binary>
export OSAC_PULL_SECRET_PATH=<path-to-osac-installer>/values/caas-ci/pull-secret.json
export OSAC_SSH_PUBLIC_KEY_PATH=~/.config/cluster-tool/cluster-tool.key.pub
export OSAC_CLUSTER_TEMPLATE=osac.templates.ocp_ci_small

cd osac-test-infra
make test-caas
```

### Run a specific test

```bash
make test TEST=test_compute_instance_lifecycle
```

---

## Cluster Management

### List running clusters

```bash
cluster-tool list                      # Default server
cluster-tool list --server <alias>     # Specific server
```

### Destroy a cluster

```bash
cluster-tool destroy <name> --server <alias>
cluster-tool destroy --all --server <alias>    # Destroy all clusters on a server
```

### Delete a flavor

```bash
cluster-tool flavors --delete <flavor-name> --server <alias>
```

---

## Quick Reference

### Complete first-time setup (VMaaS)

```bash
# 1. Install cluster-tool
git clone https://github.com/osac-project/cluster-tool.git
ln -sf "$(pwd)/cluster-tool/cluster-tool" ~/.local/bin/cluster-tool

# 2. One-time client DNS setup
sudo cluster-tool setup client

# 3. Connect to a server
cluster-tool connect myserver --host root@server.example.com --data-path /home/cluster-tool

# 4. Pull flavor (~10-15 min)
cluster-tool pull quay.io/rh-ee-ovishlit/cluster-flavors:vmaas --server myserver

# 5. Boot (~5 min)
cluster-tool boot --flavor vmaas --name dev --pull-secret values/vmaas-ci/pull-secret.json --server myserver

# 6. Use it
export KUBECONFIG=~/.kube/dev.kubeconfig
oc get nodes
```

### Subsequent boots (flavor already pulled)

```bash
cluster-tool boot --flavor vmaas --name dev --pull-secret values/vmaas-ci/pull-secret.json --server myserver
export KUBECONFIG=~/.kube/dev.kubeconfig
```

### Full workflow with refresh

```bash
cluster-tool boot --flavor vmaas --name dev --pull-secret values/vmaas-ci/pull-secret.json --server myserver
export KUBECONFIG=~/.kube/dev.kubeconfig

cd <path-to-osac-installer>
git fetch origin main && git rebase origin/main

env \
    VALUES_FILE=values/vmaas-ci/values.yaml \
    INSTALLER_NAMESPACE=osac-e2e-ci \
    INSTALLER_VM_TEMPLATE=osac.templates.ocp_virt_vm \
    python3 ./scripts/refresh-after-snapshot.py
```

### All cluster-tool commands

| Command | Description |
|---------|-------------|
| `setup client` | One-time DNS setup on your laptop (requires sudo) |
| `connect <alias> --host <ssh> --data-path <path>` | Connect to a baremetal server, install dependencies |
| `servers` | List connected servers |
| `use <alias>` | Set default server |
| `pull <image> [--server <s>] [--name <n>]` | Pull a flavor from OCI registry |
| `flavors [--server <s>] [--delete <n>]` | List or delete flavors |
| `boot --flavor <f> --name <n> --pull-secret <p> [--server <s>]` | Boot a cluster from a snapshot (~5 min) |
| `list [--server <s>]` | List running clusters |
| `verify <name> [--server <s>]` | Health-check a running cluster |
| `destroy <name>\|--all [--server <s>]` | Tear down cluster(s) |
| `snapshot --name <n> --source <id> [--server <s>]` | Create a flavor from a running cluster |
| `push <flavor> --registry <r> --tag <t> [--server <s>]` | Push a flavor to OCI registry |

## Troubleshooting

### "flavor not found" on boot

Boot does NOT auto-pull. You must pull the flavor first:

```bash
cluster-tool pull quay.io/rh-ee-ovishlit/cluster-flavors:<flavor-name> --server <alias>
```

### DNS not resolving (can't reach API or console)

Verify dnsmasq is working:

```bash
cat /etc/resolv.conf          # Should show: nameserver 127.0.0.1
ls /etc/NetworkManager/dnsmasq.d/   # Should have cluster-*.conf files
dig api.test-infra-cluster-<id>.redhat.com   # Should resolve to server IP
```

If broken, re-run:

```bash
sudo cluster-tool setup client
```

### Boot hangs at "waiting for API"

The VM may not have enough resources. Check:

```bash
ssh root@<server> "virsh list"          # Is the VM running?
ssh root@<server> "free -g"             # Enough RAM?
```

### Refresh fails with "helm upgrade" error

Make sure osac-installer is up to date with origin/main:

```bash
cd <osac-installer>
git fetch origin main
git rebase origin/main
git submodule update --init --recursive
```

### Clone name too long

Clone names must be 8 characters or fewer. Linux bridge names are `br-{name[:8]}` — longer names cause silent collisions that crash boot. When running multiple clusters, use names with different prefixes (e.g., `rdu-t1` and `del-t1`, not `test-01` and `test-02`).

### Subnet exhaustion

After ~90 boots (without full cleanup), the `192.168.x.0/24` range runs out. Fix:

```bash
cluster-tool destroy --all --server <alias>
# Then SSH to server and reset: edit state.json, set next_subnet to 160
```
