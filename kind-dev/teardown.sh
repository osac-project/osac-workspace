#!/usr/bin/env bash
# Tear down the OSAC Kind development environment
#
# Usage:
#   ./teardown.sh              # Delete the kind cluster
#   ./teardown.sh --keep-data  # Uninstall OSAC but keep the cluster
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-osac-dev}"
KEEP_DATA=false

for arg in "$@"; do
  case "$arg" in
    --keep-data) KEEP_DATA=true ;;
    --help|-h)
      echo "Usage: $0 [--keep-data]"
      echo "  --keep-data  Uninstall OSAC services but keep the kind cluster"
      exit 0
      ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }

KIND_BIN="$(which kind)"
KC_FILE="${HOME}/.kube/${CLUSTER_NAME}-kind.kubeconfig"

if [[ "$KEEP_DATA" == "true" ]]; then
  log "Uninstalling OSAC services (keeping cluster)..."
  export KUBECONFIG="${KC_FILE}"

  helm uninstall osac -n osac 2>/dev/null || true
  helm uninstall keycloak -n keycloak 2>/dev/null || true
  helm uninstall postgres -n osac 2>/dev/null || true

  log "OSAC services uninstalled. Cluster '${CLUSTER_NAME}' still running."
  log "To delete the cluster: sudo kind delete cluster --name ${CLUSTER_NAME}"
else
  log "Deleting kind cluster '${CLUSTER_NAME}'..."
  sudo "${KIND_BIN}" delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true
  log "Cluster deleted"
  log "Kubeconfig at ${KC_FILE} — remove manually if no longer needed"
fi
