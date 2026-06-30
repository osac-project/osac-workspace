# OSAC Kind Development Environment

A lightweight kind-based dev environment for OSAC, replacing the full OpenShift
dependency for local development and testing.

## What This Gives You

A single-node kind cluster running the core OSAC stack:

| Component | Version | Status |
|-----------|---------|--------|
| cert-manager | v1.20.0 | Fully working |
| trust-manager | v0.22.0 | Fully working |
| Envoy Gateway (Gateway API) | v1.6.5 | Fully working |
| Authorino (AuthZ) | v0.23.1 | Fully working |
| PostgreSQL (mTLS) | — | Fully working |
| Keycloak (OIDC) | — | Fully working |
| Fulfillment Service (gRPC + REST) | latest | Fully working |
| OSAC Operator | latest | Runs, but no AAP backend |
| Fake CRDs (HyperShift, KubeVirt, OVN-K) | — | Stubs only |

**Setup time**: ~5-8 minutes from scratch.

## Prerequisites

- **Podman** (rootless, with socket active — `systemctl --user start podman.socket`)
- **kind** >= v0.20 (`go install sigs.k8s.io/kind@latest`)
- **helm** >= v3.10
- **kubectl**
- **openssl** (for CA generation)

### System Tuning (one-time)

```bash
# kind nodes need many inotify watchers — default 128 is too low
sudo sysctl fs.inotify.max_user_instances=512
# Persist across reboots:
echo 'fs.inotify.max_user_instances=512' | sudo tee /etc/sysctl.d/99-kind-inotify.conf
sudo sysctl --system
```

No `/etc/hosts` entries needed — services are accessed via `*.localhost`
hostnames (e.g. `api.osac.localhost`) which resolve automatically via
systemd-resolved. The setup script adds a CoreDNS rewrite rule so the
same hostnames resolve inside pods too.

## Quick Start

```bash
cd kind-dev/

# Full setup (cluster + infra + OSAC)
./setup.sh

# Infrastructure only (no OSAC deployment)
./setup.sh --skip-osac

# Cluster only
./setup.sh --cluster-only

# Tear down
./teardown.sh
```

## Architecture

```
Laptop → api.osac.localhost:8443 (resolves to 127.0.0.1 via systemd-resolved)
       → Kind NodePort 30443
       → Envoy Gateway (TLS Passthrough, SNI match)
       → TLSRoute → fulfillment-api Service

Pods   → api.osac.localhost (CoreDNS rewrites to fulfillment-api.osac.svc.cluster.local)
       → ClusterIP directly
```

The setup mirrors the fulfillment-service integration test infrastructure
(see `fulfillment-service/internal/testing/kind.go`) but extracts it into
standalone scripts that any developer can run.

### Port Mappings

| Host Port | Container Port | Service |
|-----------|---------------|---------|
| 8443 | 30443 | Envoy Gateway (HTTPS ingress) |
| 8080 | 30080 | Envoy Gateway (HTTP ingress) |

### Hostnames

| Hostname | Purpose |
|----------|---------|
| `api.osac.localhost:8443` | Fulfillment API (external) |
| `internal-api.osac.localhost:8443` | Fulfillment API (internal/admin) |
| `keycloak.keycloak.localhost:8443` | Keycloak admin UI and OIDC |

## Research Findings

### OLM: Not Required

The production osac-installer uses OLM (Operator Lifecycle Manager) to deploy
prerequisites as OLM Subscriptions from the `redhat-operators` catalog. However,
**OLM is not needed for a kind dev environment**:

- cert-manager, trust-manager, Envoy Gateway: installed directly via Helm
- Authorino: installed from raw manifests
- OSAC operator + fulfillment-service: deployed via their own Helm charts

OLM adds several pods (olm-operator, catalog-operator, packageserver) and
complexity. Skip it unless you specifically need to test OLM-based installation.

### AAP: Stubbed Out

Red Hat Ansible Automation Platform is a heavyweight dependency (requires its own
operator, execution environments, license). In the kind environment:

- The osac-operator runs but with no AAP URL configured
- Provisioning requests (ClusterOrders, ComputeInstances) will be accepted by
  the fulfillment-service but won't complete lifecycle transitions
- This is sufficient for testing API flows, RBAC, multi-tenancy, and CRD
  reconciliation without actual provisioning

To test with AAP, use an OpenShift cluster with the full osac-installer.

### KubeVirt: Possible But Secondary

KubeVirt can run on kind in two modes:

1. **Hardware virtualization**: Requires `/dev/kvm` exposed into kind nodes.
   Works on bare-metal Linux with nested virt enabled. Full VM performance.
2. **Software emulation**: Set `useEmulation: true` in KubeVirt config.
   10-100x slower — only useful for testing controller logic, not running VMs.

The kind-dev environment installs fake KubeVirt CRDs so the osac-operator's
ComputeInstance controller can load without errors. To actually run VMs, install
KubeVirt separately.

### Multiple Workers: Not Needed

A single control-plane node is sufficient. It runs all workloads (control plane +
OSAC services) on one node, which is simpler and uses fewer resources. Workers
would only be useful if you need to test node scheduling, taints/tolerations, or
run heavyweight workloads alongside the control plane.

## Customization

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `osac-dev` | Kind cluster name |
| `OSAC_NAMESPACE` | `osac` | Namespace for OSAC services |
| `KEYCLOAK_NAMESPACE` | `keycloak` | Namespace for Keycloak |

### Loading Custom Images

```bash
# Build and load a local fulfillment-service image
cd fulfillment-service
podman build -t fulfillment-service:dev .
podman save fulfillment-service:dev -o /tmp/fs.tar
kind load image-archive /tmp/fs.tar --name osac-dev

# Update the deployment
helm upgrade fulfillment-service charts/service \
  --namespace osac \
  --reuse-values \
  --set images.service=fulfillment-service:dev
```

**Important**: Use `podman save` + `kind load image-archive`, not
`kind load docker-image` (broken with podman — see
[kind#3945](https://github.com/kubernetes-sigs/kind/issues/3945)).

## Comparison with Existing Tools

| | kind-dev | cluster-tool | osac-installer |
|---|---------|-------------|---------------|
| **Target** | Local dev laptop | Baremetal server | OpenShift cluster |
| **Cluster type** | kind (containers) | SNO VM (libvirt) | OpenShift |
| **Setup time** | ~5-8 min | ~5 min (from snapshot) | ~30-45 min |
| **Resources** | ~4 GB RAM | 64+ GB RAM | Full OCP cluster |
| **AAP** | Stubbed | Full | Full |
| **VMs** | Fake CRDs | Full KubeVirt | Full KubeVirt |
| **Use case** | API/controller dev | Full integration | Production-like |

## Stage 2: KubeVirt on Kind (Experimental)

The goal is to run actual VMs on the kind cluster via KubeVirt, so the
osac-operator's ComputeInstance controller can create real VirtualMachine CRs
that boot actual guest VMs.

### Prerequisites

- Host must have `/dev/kvm` available (hardware virtualization: Intel VT-x / AMD-V)
- Verify: `ls /dev/kvm` and `grep -c -E 'vmx|svm' /proc/cpuinfo`

### Status: Working with Rootful Podman

KubeVirt v1.8.4 runs on kind with full KVM hardware acceleration when
the cluster is created with rootful podman (`sudo kind create cluster`).
A cirros VM boots in ~40 seconds.

**Rootless podman does NOT work** for KubeVirt VMs. The virt-handler
needs to `chmod`/`chown` `/dev/kvm`, which rootless user namespaces deny.
The init container `chmod` can be patched via `customizeComponents`, but
the virt-handler binary's `chown` during VMI sync is in compiled code and
cannot be worked around.

### Quick Start (Stage 2)

```bash
# Create a rootful kind cluster
sudo $(which kind) create cluster --name osac-dev --config kind-dev/kind-config.yaml --wait 60s

# Save kubeconfig
mkdir -p ~/clusters/osac-dev-rootful
sudo $(which kind) get kubeconfig --name osac-dev 2>/dev/null > ~/clusters/osac-dev-rootful/kubeconfig
export KUBECONFIG=~/clusters/osac-dev-rootful/kubeconfig

# Install KubeVirt
VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml"
kubectl wait --for=condition=available --timeout=120s -n kubevirt deployments -l kubevirt.io
kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml"
kubectl -n kubevirt wait kv kubevirt --for condition=Available --timeout=300s

# Test with a cirros VM
kubectl create namespace osac
kubectl apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: testvm
  namespace: osac
spec:
  runStrategy: Always
  template:
    spec:
      domain:
        devices:
          disks:
          - name: containerdisk
            disk:
              bus: virtio
          interfaces:
          - name: default
            masquerade: {}
        resources:
          requests:
            memory: 128Mi
      networks:
      - name: default
        pod: {}
      volumes:
      - name: containerdisk
        containerDisk:
          image: quay.io/kubevirt/cirros-container-disk-demo:latest
EOF

# Verify
kubectl get vm,vmi -n osac    # STATUS: Running, READY: True
```

### Rootless vs Rootful

| | Rootless podman (stage 1) | Rootful podman (stage 2) |
|---|---|---|
| Kind cluster | Works | Works (`sudo`) |
| OSAC stack | Works | Works |
| KubeVirt install | Needs chmod patch | Works out of the box |
| VM launch | Blocked (chown EPERM) | Works — KVM accelerated |
| VM boot time | N/A | ~40 seconds (cirros) |
| Use case | API/controller dev | Full VM lifecycle |

### Stage 3: AWX as AAP Substitute (Proven)

AWX (open-source upstream of AAP) deploys on kind in ~12 minutes via the
awx-operator Helm chart. The osac-operator successfully launches AWX job
templates and polls for completion.

**Measured timeline:**
- AWX operator: 36s | AWX pods + migrations: ~12 min | Config: ~1 min
- **Repeatable total: ~15 minutes with a script**

**Full end-to-end flow — proven:**

```
osac create computeinstance --name kind-vm --template osac.templates.ocp_virt_vm ...
  → fulfillment-service stores it in PostgreSQL
  → fulfillment-controller creates ComputeInstance CR in osac namespace
  → osac-operator picks up CR, calls AWX: POST /api/v2/job_templates/osac-create-compute-instance/launch/
  → AWX runs the REAL osac-aap playbook (playbook_osac_create_compute_instance.yml)
  → Playbook creates DataVolume + VirtualMachine CR (with pod network override)
  → KubeVirt boots the VM with KVM hardware acceleration
  → VM Running, Ready=True, IP assigned
```

**Key findings:**
- The operator runs in **local mode** by default (no `multicluster-runtime`
  remote provider needed). It watches and creates resources on its own cluster.
- Hub registration uses the internal K8s API (`https://10.96.0.1:443`), not
  the host-reachable address. Hub namespace must match the operator's namespace.
- AWX `aap.url` must include `/api` path prefix (`http://awx-service.awx.svc.cluster.local:80/api`).
- Tenant namespaces (`shared`, `system`) must exist for the tenant controller.
- The ComputeInstance template ID must match the Ansible role name
  (`osac.templates.ocp_virt_vm`), not an arbitrary name.
- The real `osac-aap` playbooks work on kind with two adaptations:
  1. A pod-network override task (replaces Multus/CUDN with pod/masquerade)
  2. Extra vars: `tenant_target_namespace`, `compute_instance_target_namespace`,
     `tenant_storage_classes`
- CDI (Containerized Data Importer) is required for DataVolume-based VMs.
- AWX needs a Kubernetes credential or kubeconfig mount to reach the cluster API.
- AWX project sync must disable collection install (Red Hat proprietary
  collections like `ansible.platform` are not available in open-source AWX).

### Pod Network Override

The osac-aap playbooks hardcode Multus/CUDN networking. For kind (no Multus),
a small override task replaces the network spec with pod networking:

```
osac-aap/collections/ansible_collections/osac/templates/roles/
  ocp_virt_vm/tasks/create_modify_vm_spec_pod_network.yaml
```

Activated via AWX job template extra_vars:

```yaml
create_step_modify_vm_spec_override:
  name: osac.templates.ocp_virt_vm
  tasks_from: create_modify_vm_spec_pod_network.yaml
```

### Progress

- [x] KubeVirt VMs boot on rootful podman kind with KVM accel
- [x] Full OSAC stack deployed (fulfillment-service + osac-operator)
- [x] Hub registered, ComputeInstance CR created in correct namespace
- [x] AWX deployed on kind (~12 min), operator calls AWX API successfully
- [x] Real osac-aap playbooks run on AWX with pod network override
- [x] **Full end-to-end: `osac create computeinstance` → running KubeVirt VM**

## Known Limitations

- No AAP provisioning backend (ClusterOrder/ComputeInstance lifecycle won't complete)
- No real KubeVirt VMs in stage 1 (fake CRDs only — see Stage 2 above)
- No OpenShift Routes (uses Gateway API TLSRoute instead)
- Rootless podman may have issues with low ports and PID limits; if you hit
  problems, see the [kind rootless docs](https://kind.sigs.k8s.io/docs/user/rootless/)
- Images must be loaded via `kind load image-archive` (not `docker-image`)
