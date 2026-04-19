#!/bin/bash
#
# OSAC API Demo - Simple Template
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-default}"
API_BASE="/api/fulfillment/v1"
CAST_FILE="${CAST_FILE:-demo.cast}"
CLEANUP="${CLEANUP:-false}"

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
    echo "${body}" | jq . 2>/dev/null || echo "${body}" >&2
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
  # Example:
  # result=$(api POST "${API_BASE}/virtual_networks" -d '{"metadata":{"name":"demo"}, "spec":{...}}')
  # id=$(echo "$result" | jq -r '.id')
  # CREATED_RESOURCES+=("virtualnetwork/${id}")
  # wait_for_state "${API_BASE}/virtual_networks" "${id}" "READY"

  if [[ "${CLEANUP}" == "true" ]]; then
    cleanup_resources
  fi
}

# Main
case "${1:-}" in
  --dry-run)
    run_demo
    ;;
  --cleanup)
    CLEANUP=true
    asciinema rec --title "OSAC API Demo" -c "bash -c 'source $0 && run_demo'" "${CAST_FILE}"
    ;;
  *)
    asciinema rec --title "OSAC API Demo" -c "bash -c 'source $0 && run_demo'" "${CAST_FILE}"
    ;;
esac
