#!/usr/bin/env bash
# Consumer wrapper: materialize OSAC skills from a vendored osac-ai-skills
# clone, then exec that repo's fan-out with PROJECT_ROOT set to this workspace.
#
# Usage: tools/link-agent-skills.sh [--claude] [--cursor] [--gemini] [--all]
#          [--with-ai-workflows] [--verify]
#
# Vendor resolution:
#   $OSAC_AI_SKILLS_VENDOR_DIR, if set (bootstrap.sh sets this to the vendor
#     it already resolved/updated/cloned, so this wrapper can't independently
#     pick a different, possibly stale, directory)
#   otherwise, first match: ~/.osac-ai-skills | $WORKSPACE/.osac-ai-skills
#
# Default flags when none given: --all --with-ai-workflows
set -euo pipefail

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
WORKSPACE_ROOT="$(realpath "${SCRIPT_DIR}/..")"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--claude] [--cursor] [--gemini] [--all] [--with-ai-workflows] [--verify]

  Consumer wrapper for osac-ai-skills fan-out. Materializes skills/ symlinks
  from the vendored clone, then runs that clone's tools/link-agent-skills.sh
  with PROJECT_ROOT=${WORKSPACE_ROOT}.

  --claude / --cursor / --gemini / --all / --with-ai-workflows / --verify
      Passed through to the vendored fan-out (see osac-ai-skills README).
EOF
}

# When $OSAC_AI_SKILLS_VENDOR_DIR is set, it is authoritative and is not
# re-validated against the two-candidate search below: bootstrap.sh sets it
# to the exact directory it already resolved (or just cloned), specifically
# to prevent this function from re-resolving independently and picking a
# different candidate -- e.g. a stale ~/.osac-ai-skills that bootstrap.sh
# already rejected in favor of a fresh ./.osac-ai-skills clone.
resolve_osac_ai_skills_dir() {
  local dir
  if [[ -n "${OSAC_AI_SKILLS_VENDOR_DIR:-}" ]]; then
    if [[ -d "${OSAC_AI_SKILLS_VENDOR_DIR}/skills" && -x "${OSAC_AI_SKILLS_VENDOR_DIR}/tools/link-agent-skills.sh" ]]; then
      (cd "${OSAC_AI_SKILLS_VENDOR_DIR}" && pwd -P)
      return 0
    fi
    return 1
  fi
  for dir in "${HOME}/.osac-ai-skills" "${WORKSPACE_ROOT}/.osac-ai-skills"; do
    if [[ -d "${dir}/skills" && -x "${dir}/tools/link-agent-skills.sh" ]]; then
      (cd "${dir}" && pwd -P)
      return 0
    fi
  done
  return 1
}

# Absolute symlink skills/<name> -> <vendor>/skills/<name>.
# Refuses to replace a real (non-symlink) path.
# Prunes stale symlinks that still point into ${vendor}/skills/ after removals.
materialize_osac_skills() {
  local vendor="$1"
  local skill_dir name link_path target vendor_skills existing link_target

  vendor_skills="$(cd "${vendor}/skills" && pwd -P)"
  mkdir -p "${WORKSPACE_ROOT}/skills"
  for skill_dir in "${vendor}/skills"/*/; do
    [[ -d "${skill_dir}" ]] || continue
    name="$(basename "${skill_dir}")"
    # Skip ai-workflows names if they somehow appear in the vendor tree.
    case "${name}" in
      bugfix|design|e2e|implement|prd|_shared) continue ;;
    esac
    link_path="${WORKSPACE_ROOT}/skills/${name}"
    target="$(cd "${skill_dir}" && pwd -P)"
    if [[ -L "${link_path}" ]]; then
      rm -f "${link_path}"
    elif [[ -e "${link_path}" ]]; then
      echo "ERROR: ${link_path} exists and is not a symlink; refusing to replace (remove or rename the real directory, then re-run)" >&2
      return 1
    fi
    ln -sfn "${target}" "${link_path}"
  done

  # Drop stale vendor skill links whose source was removed upstream.
  for existing in "${WORKSPACE_ROOT}/skills"/*; do
    [[ -e "${existing}" || -L "${existing}" ]] || continue
    [[ -L "${existing}" ]] || continue
    name="$(basename "${existing}")"
    case "${name}" in
      bugfix|design|e2e|implement|prd|_shared) continue ;;
    esac
    link_target="$(readlink "${existing}")"
    # Only prune links that point into this vendor's skills tree.
    case "${link_target}" in
      "${vendor_skills}"/*) ;;
      *) continue ;;
    esac
    if [[ ! -d "${vendor_skills}/${name}" ]]; then
      rm -f "${existing}"
    fi
  done
}

ARGS=("$@")
if [[ ${#ARGS[@]} -eq 0 ]]; then
  ARGS=(--all --with-ai-workflows)
fi

# Help without requiring a vendor clone.
for arg in "${ARGS[@]}"; do
  case "${arg}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

VENDOR_DIR="$(resolve_osac_ai_skills_dir)" || {
  if [[ -n "${OSAC_AI_SKILLS_VENDOR_DIR:-}" ]]; then
    echo "ERROR: OSAC_AI_SKILLS_VENDOR_DIR=${OSAC_AI_SKILLS_VENDOR_DIR} is not a usable osac-ai-skills vendor (missing skills/ or tools/link-agent-skills.sh)." >&2
  else
    echo "ERROR: osac-ai-skills vendor not found." >&2
    echo "Expected ~/.osac-ai-skills or ${WORKSPACE_ROOT}/.osac-ai-skills with skills/ and tools/link-agent-skills.sh." >&2
    echo "Run ./bootstrap.sh (or clone osac-project/osac-ai-skills into .osac-ai-skills)." >&2
  fi
  exit 1
}

materialize_osac_skills "${VENDOR_DIR}"

export PROJECT_ROOT="${WORKSPACE_ROOT}"
exec "${VENDOR_DIR}/tools/link-agent-skills.sh" "${ARGS[@]}"
