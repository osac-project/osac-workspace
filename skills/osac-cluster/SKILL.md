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

**Read [pull-secret-and-license.md](references/pull-secret-and-license.md)** if pull secret and AAP license paths are not already set up.

```bash
cluster-tool boot --flavor vmaas --name <name> --pull-secret <path-to-pull-secret.json> --server <alias>
```

- **`--flavor`** — which snapshot to boot from (must be pulled first)
- **`--name`** — short identifier, **max 8 characters** (e.g., `dev`, `test1`, `pr-42`). Linux bridge names are `br-{name[:8]}`, so longer names cause collisions.
- **`--pull-secret`** — **(mandatory)** path to a pull secret JSON file for authenticated registry access. See [pull-secret-and-license.md](references/pull-secret-and-license.md).
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

## Step 5: Refresh the OSAC stack

**Read [refresh.md](references/refresh.md)** before running `refresh-after-snapshot.py`. Pull secret and AAP license paths are in [pull-secret-and-license.md](references/pull-secret-and-license.md).

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

**Read [e2e-tests.md](references/e2e-tests.md)** for prerequisites, VMaaS/CaaS commands, and single-test invocation (after refresh).

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
WORKSPACE_ROOT=$(cd .. && git rev-parse --show-toplevel 2>/dev/null || echo "$(pwd)")
eval "$("${WORKSPACE_ROOT}/tools/resolve-remotes.sh" .)" || { echo "Failed to resolve remotes"; exit 1; }
git fetch "$UPSTREAM_REMOTE" main && git rebase "$UPSTREAM_REMOTE/main"

env \
    VALUES_FILE=values/vmaas-ci/values.yaml \
    INSTALLER_NAMESPACE=osac-e2e-ci \
    INSTALLER_VM_TEMPLATE=osac.templates.ocp_virt_vm \
    python3 ./scripts/refresh-after-snapshot.py
```

See [refresh.md](references/refresh.md) for CaaS refresh, PR image overrides, and agent setup.

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

Make sure osac-installer is up to date with the upstream remote:

```bash
cd <osac-installer>
WORKSPACE_ROOT=$(cd .. && git rev-parse --show-toplevel 2>/dev/null || echo "$(pwd)")
eval "$("${WORKSPACE_ROOT}/tools/resolve-remotes.sh" .)" || { echo "Failed to resolve remotes"; exit 1; }
git fetch "$UPSTREAM_REMOTE" main
git rebase "$UPSTREAM_REMOTE/main"
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
