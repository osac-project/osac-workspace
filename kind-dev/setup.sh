#!/usr/bin/env bash
# OSAC Kind Development Environment Setup
#
# Creates a kind cluster with all prerequisites needed to run OSAC services.
# Designed to get developers up and running quickly without OpenShift.
#
# Usage:
#   ./setup.sh                    # Full setup
#   ./setup.sh --skip-osac        # Infrastructure only (cert-manager, envoy, keycloak, postgres)
#   ./setup.sh --cluster-only     # Kind cluster only (with CoreDNS *.localhost rewrite)
#
# Prerequisites:
#   - podman (rootful — see below)
#   - kind >= v0.20
#   - helm >= v3.10
#   - kubectl
#   - openssl
#   - inotify max_user_instances >= 256
#
# Rootful podman setup:
#   - Host:      sudo is used directly (no extra setup needed)
#   - Distrobox: install the systemd socket override on the host:
#       sudo install -d /etc/systemd/system/podman.socket.d
#       sudo install -m 0644 kind-dev/podman-socket-rootful.conf \
#         /etc/systemd/system/podman.socket.d/rootful-group.conf
#       sudo chgrp wheel /run/podman && sudo chmod 710 /run/podman
#       sudo systemctl daemon-reload && sudo systemctl restart podman.socket
#
# Environment variables:
#   CLUSTER_NAME        Kind cluster name (default: osac-dev)
#   OSAC_NAMESPACE      Namespace for OSAC services (default: osac)
#   KEYCLOAK_NAMESPACE  Namespace for Keycloak (default: keycloak)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-osac-dev}"
OSAC_NAMESPACE="${OSAC_NAMESPACE:-osac}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
SKIP_OSAC=false
CLUSTER_ONLY=false

# Component versions (aligned with fulfillment-service IT)
CERT_MANAGER_VERSION="v1.20.0"
TRUST_MANAGER_VERSION="v0.22.0"
ENVOY_GATEWAY_VERSION="v1.6.5"
AUTHORINO_VERSION="v0.23.1"

# Networking — services are accessed as <service>.<namespace>.localhost
EXTERNAL_INGRESS_PORT=8443
INTERNAL_INGRESS_NODE_PORT=30443
KIND_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"

# Detect distrobox: podman is a host-exec wrapper, sudo can't reach it.
# On the host: use sudo for rootful podman (separate socket/namespace).
if grep -qsw distrobox-host-exec "$(command -v podman 2>/dev/null)"; then
  IN_DISTROBOX=true
else
  IN_DISTROBOX=false
fi

ROOTFUL_SOCKET="/run/podman/podman.sock"

detect_podman_mode() {
  if [[ "$IN_DISTROBOX" == "true" ]]; then
    # Check if the rootful socket is reachable from the host
    if distrobox-host-exec env CONTAINER_HOST="unix://${ROOTFUL_SOCKET}" \
         podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null | grep -q false; then
      export PODMAN_ROOTFUL=1
      info "Using rootful podman via ${ROOTFUL_SOCKET}"
    else
      export PODMAN_ROOTFUL=0
      warn "Rootful podman socket not available — using rootless"
      warn "For rootful mode, run on the host:"
      warn "  sudo install -m 0644 kind-dev/podman-socket-rootful.conf \\"
      warn "    /etc/systemd/system/podman.socket.d/rootful-group.conf"
      warn "  sudo systemctl daemon-reload && sudo systemctl restart podman.socket"
    fi
  fi
}

kind_cmd() {
  if [[ "$IN_DISTROBOX" == "true" ]]; then
    if [[ "${PODMAN_ROOTFUL:-0}" == "1" ]]; then
      systemd-run --scope --user \
        env KIND_EXPERIMENTAL_PROVIDER="${KIND_PROVIDER}" \
        CONTAINER_HOST="unix://${ROOTFUL_SOCKET}" \
        kind "$@"
    else
      systemd-run --scope --user \
        env KIND_EXPERIMENTAL_PROVIDER="${KIND_PROVIDER}" \
        kind "$@"
    fi
  else
    sudo KIND_EXPERIMENTAL_PROVIDER="${KIND_PROVIDER}" kind "$@"
  fi
}

podman_cmd() {
  if [[ "$IN_DISTROBOX" == "true" ]]; then
    podman "$@"   # wrapper handles PODMAN_ROOTFUL
  else
    sudo podman "$@"
  fi
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

for arg in "$@"; do
  case "$arg" in
    --skip-osac)    SKIP_OSAC=true ;;
    --cluster-only) CLUSTER_ONLY=true ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
  esac
done

# ── Prerequisites ──────────────────────────────────────────────────────────────

check_prerequisites() {
  local missing=()
  for cmd in podman kind helm kubectl openssl; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    exit 1
  fi

  if ! podman info >/dev/null 2>&1; then
    err "Podman is not reachable. Ensure the podman socket is active."
    err "  Host: systemctl --user start podman.socket"
    err "  Distrobox: the podman wrapper should delegate to the host"
    exit 1
  fi

  detect_podman_mode

  local max_instances
  max_instances=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)
  if [[ "$max_instances" -lt 256 ]]; then
    err "inotify max_user_instances is ${max_instances} (need >= 256)"
    err "Fix: sudo sysctl fs.inotify.max_user_instances=512"
    err "Persist: echo 'fs.inotify.max_user_instances=512' | sudo tee /etc/sysctl.d/99-kind-inotify.conf"
    exit 1
  fi

  log "All prerequisites met"
}

# ── Helpers ────────────────────────────────────────────────────────────────────

wait_for_crd() {
  local crd="$1" timeout="${2:-60}" start
  start=$(date +%s)
  while ! kubectl get crd "$crd" >/dev/null 2>&1; do
    if (( $(date +%s) - start > timeout )); then
      err "Timed out waiting for CRD: $crd"
      return 1
    fi
    sleep 2
  done
}

wait_for_secret() {
  local ns="$1" name="$2" timeout="${3:-60}" start
  start=$(date +%s)
  while ! kubectl -n "$ns" get secret "$name" >/dev/null 2>&1; do
    if (( $(date +%s) - start > timeout )); then
      err "Timed out waiting for secret ${ns}/${name}"
      return 1
    fi
    sleep 2
  done
}

# ── Cluster ────────────────────────────────────────────────────────────────────

create_cluster() {
  if kind_cmd get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    log "Kind cluster '${CLUSTER_NAME}' already exists, reusing it"
    return 0
  fi

  if [[ "$IN_DISTROBOX" != "true" ]] || [[ "${PODMAN_ROOTFUL:-0}" == "1" ]]; then
    log "Creating kind cluster '${CLUSTER_NAME}' (rootful podman)..."
  else
    log "Creating kind cluster '${CLUSTER_NAME}' (rootless podman)..."
  fi
  kind_cmd create cluster \
    --name "${CLUSTER_NAME}" \
    --config "${SCRIPT_DIR}/kind-config.yaml" \
    --wait 60s

  log "Kind cluster created"
}

setup_kubeconfig() {
  local kc_file
  kc_file="${HOME}/.kube/${CLUSTER_NAME}-kind.kubeconfig"
  mkdir -p "${HOME}/.kube"

  kind_cmd get kubeconfig --name "${CLUSTER_NAME}" 2>/dev/null > "${kc_file}"
  chmod 600 "${kc_file}"
  export KUBECONFIG="${kc_file}"
  log "Kubeconfig: ${KUBECONFIG}"
}

# ── CoreDNS *.localhost rewrite ────────────────────────────────────────────────
# Adds a generic rewrite rule so that <svc>.<ns>.localhost resolves to
# <svc>.<ns>.svc.cluster.local inside pods. This lets pods and your laptop
# use the same hostnames (*.localhost resolves to 127.0.0.1 on the host
# via systemd-resolved, and to the correct ClusterIP inside the cluster).

patch_coredns_localhost_rewrite() {
  local corefile
  corefile=$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')

  if echo "$corefile" | grep -q 'name regex .*.localhost'; then
    log "CoreDNS *.localhost rewrite already configured"
    return 0
  fi

  log "Patching CoreDNS with generic *.localhost rewrite rule..."

  local new_corefile
  new_corefile=$(echo "$corefile" | sed '/kubernetes cluster.local/i\
    rewrite name keycloak.osac.localhost keycloak-external.keycloak.svc.cluster.local\
    rewrite stop {\
        name regex (.+)\\.(.+)\\.localhost {1}.{2}.svc.cluster.local\
        answer name (.+)\\.(.+)\\.svc\\.cluster\\.local {1}.{2}.localhost\
    }')

  kubectl -n kube-system create configmap coredns \
    --from-literal=Corefile="$new_corefile" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl -n kube-system rollout restart deployment coredns
  kubectl -n kube-system rollout status deployment coredns --timeout=60s

  log "CoreDNS patched — <service>.<namespace>.localhost works inside pods"
}

# ── Infrastructure ─────────────────────────────────────────────────────────────

install_cert_manager() {
  log "Installing cert-manager ${CERT_MANAGER_VERSION}..."
  helm upgrade --install cert-manager \
    oci://quay.io/jetstack/charts/cert-manager \
    --version "${CERT_MANAGER_VERSION}" \
    --namespace cert-manager \
    --create-namespace \
    --set crds.enabled=true \
    --wait --timeout 5m

  wait_for_crd "clusterissuers.cert-manager.io"
  wait_for_crd "certificates.cert-manager.io"
  log "cert-manager installed"
}

install_trust_manager() {
  log "Installing trust-manager ${TRUST_MANAGER_VERSION}..."
  helm upgrade --install trust-manager \
    oci://quay.io/jetstack/charts/trust-manager \
    --version "${TRUST_MANAGER_VERSION}" \
    --namespace cert-manager \
    --set defaultPackage.enabled=false \
    --wait --timeout 5m

  wait_for_crd "bundles.trust.cert-manager.io"
  log "trust-manager installed"
}

install_ca() {
  log "Creating self-signed CA..."

  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -f '${tmpdir}/ca.key' '${tmpdir}/ca.crt'; rmdir '${tmpdir}' 2>/dev/null || true" RETURN

  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${tmpdir}/ca.key" \
    -out "${tmpdir}/ca.crt" \
    -subj "/CN=OSAC Dev CA" \
    -days 365 2>/dev/null

  kubectl -n cert-manager create secret tls default-ca \
    --cert="${tmpdir}/ca.crt" \
    --key="${tmpdir}/ca.key" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: default-ca
spec:
  ca:
    secretName: default-ca
EOF

  kubectl apply -f - <<'EOF'
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: ca-bundle
spec:
  sources:
    - secret:
        name: default-ca
        key: tls.crt
  target:
    configMap:
      key: bundle.pem
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values:
            - kube-node-lease
            - kube-public
            - kube-system
            - local-path-storage
            - cert-manager
            - envoy-gateway
EOF

  log "CA and trust bundle configured"
}

install_envoy_gateway() {
  log "Installing Envoy Gateway ${ENVOY_GATEWAY_VERSION}..."
  helm upgrade --install envoy-gateway \
    oci://docker.io/envoyproxy/gateway-helm \
    --version "${ENVOY_GATEWAY_VERSION}" \
    --namespace envoy-gateway \
    --create-namespace \
    --wait --timeout 5m

  wait_for_crd "envoyproxies.gateway.envoyproxy.io"
  wait_for_crd "gatewayclasses.gateway.networking.k8s.io"
  wait_for_crd "gateways.gateway.networking.k8s.io"

  kubectl apply -f - <<EOF
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: default
  namespace: envoy-gateway
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: NodePort
        patch:
          type: StrategicMerge
          value:
            spec:
              ports:
                - name: https
                  port: 443
                  nodePort: ${INTERNAL_INGRESS_NODE_PORT}
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: default
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    namespace: envoy-gateway
    name: default
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: default
  namespace: envoy-gateway
spec:
  gatewayClassName: default
  listeners:
    - name: tls
      protocol: TLS
      port: 443
      tls:
        mode: Passthrough
      allowedRoutes:
        namespaces:
          from: All
EOF

  log "Envoy Gateway configured with TLS passthrough on NodePort ${INTERNAL_INGRESS_NODE_PORT}"
}

install_authorino() {
  log "Installing Authorino ${AUTHORINO_VERSION}..."
  kubectl apply -f \
    "https://raw.githubusercontent.com/Kuadrant/authorino-operator/refs/heads/release-${AUTHORINO_VERSION}/config/deploy/manifests.yaml"
  wait_for_crd "authorinos.operator.authorino.kuadrant.io" 120
  wait_for_crd "authconfigs.authorino.kuadrant.io" 120
  log "Authorino installed"
}

# ── Data Services ──────────────────────────────────────────────────────────────

install_postgres() {
  local chart_dir="${WORKSPACE_DIR}/fulfillment-service/it/charts/postgres"
  if [[ ! -d "$chart_dir" ]]; then
    err "PostgreSQL chart not found at ${chart_dir}"
    err "Run bootstrap.sh to clone fulfillment-service"
    return 1
  fi

  log "Installing PostgreSQL..."
  kubectl create namespace "${OSAC_NAMESPACE}" 2>/dev/null || true

  helm upgrade --install postgres \
    "${chart_dir}" \
    --namespace "${OSAC_NAMESPACE}" \
    --set "certs.issuerRef.name=default-ca" \
    --set "certs.caBundle.configMap=ca-bundle" \
    --set "databases[0].name=service" \
    --set "databases[0].user=service" \
    --set "databases[1].name=keycloak" \
    --set "databases[1].user=keycloak" \
    --wait --timeout 5m

  log "PostgreSQL installed with 'service' and 'keycloak' databases"
}

create_database_resources() {
  log "Creating database resources..."

  # Fulfillment service database client cert + config
  kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: fulfillment-database-client
  namespace: ${OSAC_NAMESPACE}
spec:
  issuerRef:
    kind: ClusterIssuer
    name: default-ca
  commonName: service
  usages: [client auth]
  secretName: fulfillment-database-client-cert
  privateKey:
    rotationPolicy: Always
EOF

  kubectl -n "${OSAC_NAMESPACE}" create configmap fulfillment-database-config \
    --from-literal=url="postgres://service@postgres.${OSAC_NAMESPACE}.svc.cluster.local:5432/service" \
    --from-literal=sslmode="verify-full" \
    --dry-run=client -o yaml | kubectl apply -f -

  # Keycloak database client cert (DER format required by JDBC driver) + config
  kubectl create namespace "${KEYCLOAK_NAMESPACE}" 2>/dev/null || true

  kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: keycloak-database-client
  namespace: ${KEYCLOAK_NAMESPACE}
spec:
  issuerRef:
    kind: ClusterIssuer
    name: default-ca
  commonName: keycloak
  usages: [client auth]
  secretName: keycloak-database-client-cert
  privateKey:
    encoding: PKCS8
    rotationPolicy: Always
  additionalOutputFormats:
    - type: DER
EOF

  kubectl -n "${KEYCLOAK_NAMESPACE}" create configmap keycloak-database-config \
    --from-literal=url="postgres://keycloak@postgres.${OSAC_NAMESPACE}.svc.cluster.local:5432/keycloak" \
    --from-literal=user="keycloak" \
    --from-literal=password="" \
    --from-literal=sslmode="require" \
    --dry-run=client -o yaml | kubectl apply -f -

  wait_for_secret "${OSAC_NAMESPACE}" "fulfillment-database-client-cert"
  wait_for_secret "${KEYCLOAK_NAMESPACE}" "keycloak-database-client-cert"

  log "Database resources created"
}

install_keycloak() {
  local chart_dir="${WORKSPACE_DIR}/fulfillment-service/it/charts/keycloak"
  if [[ ! -d "$chart_dir" ]]; then
    err "Keycloak chart not found at ${chart_dir}"
    err "Run bootstrap.sh to clone fulfillment-service"
    return 1
  fi

  log "Installing Keycloak..."
  helm upgrade --install keycloak \
    "${chart_dir}" \
    --namespace "${KEYCLOAK_NAMESPACE}" \
    --create-namespace \
    --values "${SCRIPT_DIR}/keycloak-values.yaml" \
    --wait --timeout 10m

  # The chart hardcodes hostname-port=8000 but we need 8443 (the external port).
  # Override via KC_HOSTNAME_PORT env var by re-rendering the pod template.
  log "Patching Keycloak hostname-port to ${EXTERNAL_INGRESS_PORT}..."
  kubectl -n "${KEYCLOAK_NAMESPACE}" delete pod keycloak-service --wait 2>/dev/null || true

  helm template keycloak "${chart_dir}" \
    --namespace "${KEYCLOAK_NAMESPACE}" \
    --values "${SCRIPT_DIR}/keycloak-values.yaml" \
    -s templates/pod.yaml | \
    sed "/KC_BOOTSTRAP_ADMIN_PASSWORD/,/value:/{
      /value:/a\\
    - name: KC_HOSTNAME_PORT\\
      value: \"${EXTERNAL_INGRESS_PORT}\"
    }" | kubectl apply -f -

  log "Waiting for Keycloak to be ready..."
  kubectl -n "${KEYCLOAK_NAMESPACE}" wait --for=condition=Ready pod/keycloak-service --timeout=300s

  # Create a service on port 8443 so pods can reach keycloak.osac.localhost:8443
  # (CoreDNS rewrites the hostname, this service maps the external port to the pod port)
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keycloak-external
  namespace: ${KEYCLOAK_NAMESPACE}
spec:
  selector:
    app: keycloak-service
  ports:
  - port: ${EXTERNAL_INGRESS_PORT}
    targetPort: 8000
    protocol: TCP
    name: https
  type: ClusterIP
EOF

  log "Keycloak installed — admin UI: https://keycloak.${KEYCLOAK_NAMESPACE}.localhost:${EXTERNAL_INGRESS_PORT}/admin"
}

create_external_tlsroutes() {
  log "Creating external TLSRoutes for *.osac.localhost..."

  kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1alpha3
kind: TLSRoute
metadata:
  name: fulfillment-api-external
  namespace: ${OSAC_NAMESPACE}
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    namespace: envoy-gateway
    name: default
    sectionName: tls
  hostnames:
  - api.${OSAC_NAMESPACE}.localhost
  rules:
  - backendRefs:
    - name: fulfillment-api
      port: 8000
---
apiVersion: gateway.networking.k8s.io/v1alpha3
kind: TLSRoute
metadata:
  name: fulfillment-internal-api-external
  namespace: ${OSAC_NAMESPACE}
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    namespace: envoy-gateway
    name: default
    sectionName: tls
  hostnames:
  - internal-api.${OSAC_NAMESPACE}.localhost
  rules:
  - backendRefs:
    - name: fulfillment-internal-api
      port: 8001
---
apiVersion: gateway.networking.k8s.io/v1alpha3
kind: TLSRoute
metadata:
  name: keycloak-external
  namespace: ${KEYCLOAK_NAMESPACE}
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    namespace: envoy-gateway
    name: default
    sectionName: tls
  hostnames:
  - keycloak.${KEYCLOAK_NAMESPACE}.localhost
  rules:
  - backendRefs:
    - name: keycloak
      port: 8000
EOF

  log "External TLSRoutes created"
}

create_controller_credentials() {
  log "Creating controller credentials..."

  kubectl -n "${OSAC_NAMESPACE}" create secret generic fulfillment-controller-credentials \
    --from-literal=client-id=osac-controller \
    --from-literal=client-secret=password \
    --dry-run=client -o yaml | kubectl apply -f -

  log "Controller credentials created"
}

# ── OSAC Services (umbrella chart) ─────────────────────────────────────────────

install_fake_crds() {
  local fakes_dir="${WORKSPACE_DIR}/osac-operator/config/crd/fakes"
  if [[ ! -d "$fakes_dir" ]]; then
    warn "Fake CRDs not found at ${fakes_dir} — skipping"
    return 0
  fi

  log "Installing fake CRDs (HyperShift, OVN-K)..."
  for f in "${fakes_dir}"/*.yaml; do
    local base
    base=$(basename "$f")
    [[ "$base" == "kustomization.yaml" ]] && continue
    # Skip CRDs managed by other installers
    [[ "$base" == *"osac.openshift.io"* ]] && continue  # umbrella chart
    [[ "$base" == *"kubevirt.io"* ]] && continue         # KubeVirt operator
    kubectl apply -f "$f" 2>/dev/null || true
  done
  log "Fake CRDs installed"
}

deploy_osac() {
  local installer_dir="${WORKSPACE_DIR}/osac-installer"
  local chart_dir="${installer_dir}/charts/osac"

  if [[ ! -d "$chart_dir" ]]; then
    err "Umbrella chart not found at ${chart_dir}"
    err "Make sure osac-installer is checked out (run bootstrap.sh)"
    return 1
  fi

  log "Initializing osac-installer submodules..."
  git -C "${installer_dir}" submodule update --init --recursive 2>&1 | tail -5

  log "Building umbrella chart dependencies..."
  helm dependency build "${chart_dir}" 2>&1 | tail -3

  log "Deploying OSAC via umbrella chart..."
  helm upgrade --install osac \
    "${chart_dir}" \
    --namespace "${OSAC_NAMESPACE}" \
    --create-namespace \
    --values "${SCRIPT_DIR}/values-kind.yaml" \
    --wait --timeout 10m

  log "OSAC deployed via umbrella chart"
}

# ── KubeVirt ───────────────────────────────────────────────────────────────────

install_multus() {
  log "Installing Multus CNI..."

  kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml 2>&1 | tail -3
  kubectl -n kube-system wait --for=condition=Ready pods -l app=multus --timeout=120s

  log "Installing bridge CNI plugin into kind node..."
  local node_name="${CLUSTER_NAME}-control-plane"
  podman_cmd exec "${node_name}" bash -c \
    'curl -sL https://github.com/containernetworking/plugins/releases/download/v1.6.2/cni-plugins-linux-amd64-v1.6.2.tgz | tar -C /opt/cni/bin -xz'

  log "Multus installed"
}

install_kubevirt() {
  log "Installing KubeVirt..."

  local version
  version=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
  log "KubeVirt version: ${version}"

  kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${version}/kubevirt-operator.yaml" 2>&1 | tail -3
  kubectl wait --for=condition=available --timeout=120s -n kubevirt deployments -l kubevirt.io

  kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${version}/kubevirt-cr.yaml"
  kubectl -n kubevirt wait kv kubevirt --for condition=Available --timeout=300s

  log "KubeVirt installed"
}

install_cdi() {
  log "Installing CDI (Containerized Data Importer)..."

  local version
  version=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases/latest | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])")
  log "CDI version: ${version}"

  kubectl apply -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${version}/cdi-operator.yaml" 2>&1 | tail -3
  kubectl apply -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${version}/cdi-cr.yaml"
  kubectl wait --for=condition=available --timeout=120s -n cdi deployments -l cdi.kubevirt.io

  log "CDI installed"
}

# ── AWX ────────────────────────────────────────────────────────────────────────

install_awx() {
  log "Installing AWX operator..."

  helm repo add awx-operator https://ansible-community.github.io/awx-operator-helm/ 2>/dev/null || true
  helm upgrade --install awx-operator awx-operator/awx-operator -n awx --create-namespace --wait --timeout 3m 2>&1 | tail -2

  log "Creating AWX instance..."
  kubectl apply -f "${SCRIPT_DIR}/awx/awx-instance.yaml"

  log "Waiting for AWX pods (this takes ~10 minutes)..."
  for i in $(seq 1 60); do
    local task_ready
    task_ready=$(kubectl -n awx get pods -l app.kubernetes.io/component=awx-task --no-headers 2>/dev/null | grep -c "4/4" || true)
    if [[ "$task_ready" -ge 1 ]]; then
      break
    fi
    sleep 10
  done

  kubectl -n awx get pods 2>/dev/null | grep -v Completed
  log "AWX installed"
}

configure_awx() {
  log "Configuring AWX for OSAC..."

  # Add HTTP listener to gateway and HTTPRoute for AWX web UI
  kubectl apply -f "${SCRIPT_DIR}/awx/gateway-with-http.yaml"
  kubectl apply -f "${SCRIPT_DIR}/awx/httproute.yaml"

  local admin_pass awx_token project_id inv_id
  admin_pass=$(kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d)

  # Port-forward for API access
  kubectl -n awx port-forward svc/awx-service 8052:80 &
  local pf_pid=$!
  sleep 3

  # Create OAuth token
  awx_token=$(curl -s -X POST http://localhost:8052/api/v2/tokens/ \
    -u "admin:${admin_pass}" \
    -H "Content-Type: application/json" \
    -d '{"scope": "write"}' | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
  log "AWX token created"

  # Create inventory
  inv_id=$(curl -s -X POST http://localhost:8052/api/v2/inventories/ \
    -H "Authorization: Bearer ${awx_token}" \
    -H "Content-Type: application/json" \
    -d '{"name": "OSAC Dev", "organization": 1}' | python3 -c "import json,sys; print(json.load(sys.stdin).get('id','error'))")

  curl -s -X POST "http://localhost:8052/api/v2/inventories/${inv_id}/hosts/" \
    -H "Authorization: Bearer ${awx_token}" \
    -H "Content-Type: application/json" \
    -d '{"name": "localhost", "variables": "ansible_connection: local"}' >/dev/null

  # Disable collection sync (ansible.platform not available in open-source AWX)
  curl -s -X PATCH http://localhost:8052/api/v2/settings/jobs/ \
    -H "Authorization: Bearer ${awx_token}" \
    -H "Content-Type: application/json" \
    -d '{"AWX_COLLECTIONS_ENABLED": false, "AWX_ROLES_ENABLED": false}' >/dev/null

  # Create project from osac-aap repo
  project_id=$(curl -s -X POST http://localhost:8052/api/v2/projects/ \
    -H "Authorization: Bearer ${awx_token}" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "osac-aap",
      "organization": 1,
      "scm_type": "git",
      "scm_url": "https://github.com/osac-project/osac-aap.git",
      "scm_branch": "main",
      "scm_update_on_launch": false
    }' | python3 -c "import json,sys; print(json.load(sys.stdin).get('id','error'))")

  # Wait for project sync
  for i in $(seq 1 20); do
    local status
    status=$(curl -s -H "Authorization: Bearer ${awx_token}" \
      "http://localhost:8052/api/v2/projects/${project_id}/" | \
      python3 -c "import json,sys; print(json.load(sys.stdin).get('status','unknown'))")
    if [[ "$status" == "successful" || "$status" == "failed" ]]; then break; fi
    sleep 5
  done
  log "AWX project synced: ${status}"

  # Create job templates
  local templates=(
    "osac-create-compute-instance:playbook_osac_create_compute_instance.yml"
    "osac-delete-compute-instance:playbook_osac_delete_compute_instance.yml"
  )

  for entry in "${templates[@]}"; do
    local name="${entry%%:*}" playbook="${entry##*:}"
    curl -s -X POST http://localhost:8052/api/v2/job_templates/ \
      -H "Authorization: Bearer ${awx_token}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"${name}\",
        \"organization\": 1,
        \"inventory\": ${inv_id},
        \"project\": ${project_id},
        \"playbook\": \"${playbook}\",
        \"ask_variables_on_launch\": true,
        \"extra_vars\": \"tenant_target_namespace: ${OSAC_NAMESPACE}\ncompute_instance_target_namespace: ${OSAC_NAMESPACE}\ntenant_storage_classes:\n  - name: standard\n    tier: default\"
      }" >/dev/null
    log "  template: ${name}"
  done

  # Create Kubernetes credential for AWX
  kubectl -n "${OSAC_NAMESPACE}" create serviceaccount awx-runner 2>/dev/null || true
  kubectl create clusterrolebinding awx-runner-admin --clusterrole=cluster-admin --serviceaccount="${OSAC_NAMESPACE}:awx-runner" 2>/dev/null || true

  local awx_runner_token cluster_ca
  awx_runner_token=$(kubectl -n "${OSAC_NAMESPACE}" create token awx-runner --duration=87600h)
  cluster_ca=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

  python3 -c "
import json, requests
r = requests.post('http://localhost:8052/api/v2/credentials/',
    headers={'Authorization': 'Bearer ${awx_token}', 'Content-Type': 'application/json'},
    json={
        'name': 'kind-cluster',
        'organization': 1,
        'credential_type': 17,
        'inputs': {
            'host': 'https://kubernetes.default.svc.cluster.local:443',
            'bearer_token': '${awx_runner_token}',
            'verify_ssl': True,
            'ssl_ca_cert': '''${cluster_ca}'''
        }
    })
cred_id = r.json().get('id')
# Attach to all job templates
for jt in requests.get('http://localhost:8052/api/v2/job_templates/',
    headers={'Authorization': 'Bearer ${awx_token}'}).json()['results']:
    requests.post(f'http://localhost:8052/api/v2/job_templates/{jt[\"id\"]}/credentials/',
        headers={'Authorization': 'Bearer ${awx_token}', 'Content-Type': 'application/json'},
        json={'id': cred_id})
print(f'Credential {cred_id} attached to all templates')
" 2>&1

  kill $pf_pid 2>/dev/null
  wait $pf_pid 2>/dev/null

  # Store AWX URL and token for operator config
  AWX_TOKEN="${awx_token}"
  AWX_URL="http://awx-service.awx.svc.cluster.local:80/api"

  log "AWX configured for OSAC"
}

# ── Summary ────────────────────────────────────────────────────────────────────

print_summary() {
  echo ""
  echo "============================================="
  echo "  OSAC Kind Development Environment Ready"
  echo "============================================="
  echo ""
  info "Cluster:    ${CLUSTER_NAME}"
  info "Kubeconfig: export KUBECONFIG=${KUBECONFIG}"
  echo ""

  if [[ "$CLUSTER_ONLY" == "true" ]]; then
    info "Cluster created with CoreDNS *.localhost rewrite."
    info "Use <service>.<namespace>.localhost from your laptop and from inside pods."
    return
  fi

  if [[ "$SKIP_OSAC" == "true" ]]; then
    info "Infrastructure deployed (cert-manager, envoy, keycloak, postgres)."
    info "Run again without --skip-osac to deploy OSAC services."
    echo ""
  fi

  info "Access (no /etc/hosts needed):"
  echo "  OSAC API:         https://api.${OSAC_NAMESPACE}.localhost:${EXTERNAL_INGRESS_PORT}"
  echo "  OSAC Internal:    https://internal-api.${OSAC_NAMESPACE}.localhost:${EXTERNAL_INGRESS_PORT}"
  echo "  Keycloak Admin:   https://keycloak.${KEYCLOAK_NAMESPACE}.localhost:${EXTERNAL_INGRESS_PORT}/admin  (admin/password)"
  echo ""
  info "CLI quickstart:"
  echo "  cd fulfillment-service && go build -o osac ./cmd/osac"
  echo "  TOKEN=\$(kubectl -n ${OSAC_NAMESPACE} create token admin --duration=1h)"
  echo "  ./osac login https://api.${OSAC_NAMESPACE}.localhost:${EXTERNAL_INGRESS_PORT} --token \"\$TOKEN\" --insecure"
  echo "  ./osac get tenants"
  echo ""
  info "Teardown:"
  echo "  ${SCRIPT_DIR}/teardown.sh"
  echo ""
  info "AWX admin:"
  echo "  URL:      http://awx.awx.localhost:8080 (after adding HTTPRoute)"
  echo "  Password: kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d"
  echo ""
  info "Open items:"
  echo "  - Hub registration (osac create hub) for full operator reconciliation"
  echo ""
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
  echo ""
  log "Setting up OSAC Kind development environment"
  echo ""

  check_prerequisites

  # Step 1: Create kind cluster and configure kubeconfig
  create_cluster
  setup_kubeconfig

  # Step 2: Patch CoreDNS for *.localhost resolution inside pods
  patch_coredns_localhost_rewrite

  if [[ "$CLUSTER_ONLY" == "true" ]]; then
    print_summary
    return 0
  fi

  # Step 3: Install infrastructure
  install_cert_manager
  install_trust_manager
  install_ca
  install_envoy_gateway
  install_authorino

  # Step 4: Install data services
  install_postgres
  create_database_resources
  install_keycloak
  create_controller_credentials

  if [[ "$SKIP_OSAC" == "true" ]]; then
    print_summary
    return 0
  fi

  # Step 5: Install OSAC via umbrella chart
  install_fake_crds
  deploy_osac
  create_external_tlsroutes

  # Step 6: Install KubeVirt + CDI + Multus
  install_multus
  install_kubevirt
  install_cdi

  # Step 7: Install and configure AWX
  install_awx
  configure_awx

  print_summary
}

main "$@"
