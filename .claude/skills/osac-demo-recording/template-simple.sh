#!/bin/bash
#
# OSAC Demo - Simple Template
# Prefer fulfillment-cli commands; use api() only when CLI lacks support.
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-default}"
API_BASE="/api/fulfillment/v1"
CAST_FILE="${CAST_FILE:-demo.cast}"
CLEANUP="${CLEANUP:-false}"
CLI="${CLI:-fulfillment-cli}"

ROUTE=""
TOKEN=""
CREATED_RESOURCES=()

refresh_auth() {
  ROUTE=$(kubectl get route -n "${NAMESPACE}" fulfillment-api -o jsonpath='{.spec.host}')
  TOKEN=$(kubectl create token -n "${NAMESPACE}" admin)
}

api() {
  local method=$1 path=$2
  shift 2
  local response http_code body
  response=$(curl -sk -w '\n%{http_code}' -X "${method}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    "https://${ROUTE}${path}" "$@")
  http_code=$(echo "${response}" | tail -1)
  body=$(echo "${response}" | sed '$d')
  if (( http_code >= 400 )); then
    echo "ERROR: HTTP ${http_code}" >&2
    (echo "${body}" | jq . 2>/dev/null || echo "${body}") >&2
    return 1
  fi
  echo "${body}"
}

wait_for_state() {
  local path=$1 id=$2 desired_state=$3 timeout=${4:-300}
  local elapsed=0
  while true; do
    refresh_auth
    local state
    state=$(api GET "${path}/${id}" | jq -r '.status.state // "UNKNOWN"')
    if [[ "${state}" == *"${desired_state}"* ]]; then
      echo "State: ${state}"
      return 0
    fi
    if [[ "${state}" == *"FAILED"* ]]; then
      echo "State: ${state}" >&2
      return 1
    fi
    if (( elapsed >= timeout )); then
      echo "Timed out (${timeout}s)" >&2
      return 1
    fi
    echo -ne "Waiting... ${state} (${elapsed}s)\r"
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

cleanup_resources() {
  for ((i=${#CREATED_RESOURCES[@]}-1; i>=0; i--)); do
    kubectl delete "${CREATED_RESOURCES[$i]}" -n "${NAMESPACE}" --force --grace-period=0
  done
}

run_demo() {
  refresh_auth

  # TODO: Add your demo steps here
  # Prefer CLI commands:
  #   ${CLI} get network-classes
  #   ${CLI} create -f virtual-network.yaml
  #   ${CLI} get virtual-networks -w
  #   ${CLI} delete virtual-network <id>
  # Fall back to api() only when CLI lacks support:
  #   result=$(api GET "${API_BASE}/virtual_networks")
  #   result=$(api POST "${API_BASE}/virtual_networks" -d '{"metadata":{"name":"demo"}, "spec":{...}}')

  if [[ "${CLEANUP}" == "true" ]]; then
    cleanup_resources
  fi
}

# Main
SCRIPT_PATH=$(printf '%q' "$(readlink -f "$0")")

case "${1:-}" in
  --dry-run)
    run_demo
    ;;
  --cleanup)
    export CLEANUP=true
    export NAMESPACE CAST_FILE
    asciinema rec --title "OSAC API Demo" -c "bash -c \"source ${SCRIPT_PATH} && run_demo\"" "${CAST_FILE}"
    ;;
  *)
    export NAMESPACE CAST_FILE
    asciinema rec --title "OSAC API Demo" -c "bash -c \"source ${SCRIPT_PATH} && run_demo\"" "${CAST_FILE}"
    ;;
esac
