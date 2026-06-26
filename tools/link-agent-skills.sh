#!/usr/bin/env bash
# Link agent skill discovery directories to the canonical skills/ tree.
#
# Usage: tools/link-agent-skills.sh [--claude] [--cursor] [--gemini] [--all] [--verify]
#
# Creates umbrella symlinks:
#   .claude/skills -> ../skills
#   .cursor/skills -> ../skills
#   .gemini/skills -> ../skills
#
# Run after ai-workflows install.sh all in bootstrap.sh.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

OSAC_SKILLS=(
  create-pr
  report-bug
  quick-fix
  osac-feature
  jira-task-management
  capture-tasks-from-meeting-notes
  generate-status-report
  ep-review
  prd-review
  milestone-scope
  osac-demo-recording
  presentation
)

AI_WORKFLOW_SKILLS=(bugfix design implement prd)

LINK_CLAUDE=false
LINK_CURSOR=false
LINK_GEMINI=false
VERIFY_ONLY=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--claude] [--cursor] [--gemini] [--all] [--verify]

  --claude   Link .claude/skills -> ../skills
  --cursor   Link .cursor/skills -> ../skills
  --gemini   Link .gemini/skills -> ../skills
  --all      Link all agent directories (default when no link flag is given)
  --verify   Verify symlinks and OSAC skill files; exit non-zero on failure
EOF
}

link_agent_skills() {
  local agent_dir="$1"
  local label="$2"

  rm -rf "${agent_dir}/skills"
  mkdir -p "${agent_dir}"
  ln -sfn ../skills "${agent_dir}/skills"
  echo "  Linked ${agent_dir}/skills -> ../skills  (${label})"
}

resolve_ai_workflows_dir() {
  if [[ -d "${HOME}/.ai-workflows" ]]; then
    readlink -f "${HOME}/.ai-workflows"
  elif [[ -d "${PROJECT_ROOT}/.ai-workflows" ]]; then
    readlink -f "${PROJECT_ROOT}/.ai-workflows"
  fi
}

link_canonical_ai_workflows() {
  local ai_dir
  ai_dir="$(resolve_ai_workflows_dir || true)"
  if [[ -z "${ai_dir}" ]]; then
    echo "WARN: ai-workflows not found; skipping skills/ workflow symlinks" >&2
    return 0
  fi

  mkdir -p "${PROJECT_ROOT}/skills"
  if [[ -d "${ai_dir}/_shared" ]]; then
    ln -sfn "${ai_dir}/_shared" "${PROJECT_ROOT}/skills/_shared"
    echo "  Linked skills/_shared -> ${ai_dir}/_shared"
  fi
  for wf in "${AI_WORKFLOW_SKILLS[@]}"; do
    if [[ -d "${ai_dir}/${wf}" ]]; then
      ln -sfn "${ai_dir}/${wf}" "${PROJECT_ROOT}/skills/${wf}"
      echo "  Linked skills/${wf} -> ${ai_dir}/${wf}"
    fi
  done
}

verify_symlink() {
  local agent_dir="$1"
  local label="$2"

  if [[ ! -L "${agent_dir}/skills" ]]; then
    echo "ERROR: ${label}: ${agent_dir}/skills is not a symlink" >&2
    return 1
  fi

  if [[ ! -r "${agent_dir}/skills/create-pr/SKILL.md" ]]; then
    echo "ERROR: ${label}: cannot read create-pr via ${agent_dir}/skills" >&2
    return 1
  fi

  echo "  OK ${label}: ${agent_dir}/skills -> ../skills"
}

verify_osac_skills() {
  local missing=0
  for skill in "${OSAC_SKILLS[@]}"; do
    if [[ ! -r "${PROJECT_ROOT}/skills/${skill}/SKILL.md" ]]; then
      echo "ERROR: missing ${PROJECT_ROOT}/skills/${skill}/SKILL.md" >&2
      missing=1
    fi
  done
  return "${missing}"
}

verify_ai_workflow_skills() {
  local missing=0
  for skill in "${AI_WORKFLOW_SKILLS[@]}"; do
    if [[ ! -r "${PROJECT_ROOT}/skills/${skill}/SKILL.md" ]]; then
      echo "ERROR: missing skills/${skill}/SKILL.md (run ai-workflows install first)" >&2
      missing=1
    fi
  done
  return "${missing}"
}

run_verify() {
  local errors=0

  echo "Verifying agent skill symlinks..."
  if [[ "${LINK_CLAUDE}" == true ]]; then
    verify_symlink "${PROJECT_ROOT}/.claude" "Claude" || errors=1
  fi
  if [[ "${LINK_CURSOR}" == true ]]; then
    verify_symlink "${PROJECT_ROOT}/.cursor" "Cursor" || errors=1
  fi
  if [[ "${LINK_GEMINI}" == true ]]; then
    verify_symlink "${PROJECT_ROOT}/.gemini" "Gemini" || errors=1
  fi

  echo "Verifying canonical skills/ content..."
  verify_osac_skills || errors=1
  verify_ai_workflow_skills || errors=1

  if [[ "${LINK_CURSOR}" == true ]] && [[ ! -f "${PROJECT_ROOT}/.cursor/commands/implement-ingest.md" ]]; then
    echo "WARN: missing .cursor/commands/implement-ingest.md (run ai-workflows cursor install?)" >&2
  fi

  if [[ "${errors}" -ne 0 ]]; then
    echo "Verification failed." >&2
    return 1
  fi

  echo "Verification passed."
}

if [[ $# -eq 0 ]]; then
  LINK_CLAUDE=true
  LINK_CURSOR=true
  LINK_GEMINI=true
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude) LINK_CLAUDE=true ;;
    --cursor) LINK_CURSOR=true ;;
    --gemini) LINK_GEMINI=true ;;
    --all)
      LINK_CLAUDE=true
      LINK_CURSOR=true
      LINK_GEMINI=true
      ;;
    --verify) VERIFY_ONLY=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "${VERIFY_ONLY}" == true ]]; then
  if [[ "${LINK_CLAUDE}" == false && "${LINK_CURSOR}" == false && "${LINK_GEMINI}" == false ]]; then
    LINK_CLAUDE=true
    LINK_CURSOR=true
    LINK_GEMINI=true
  fi
  run_verify
  exit $?
fi

echo "Linking agent skill directories to skills/..."
link_canonical_ai_workflows
if [[ "${LINK_CLAUDE}" == true ]]; then
  link_agent_skills "${PROJECT_ROOT}/.claude" "Claude"
fi
if [[ "${LINK_CURSOR}" == true ]]; then
  link_agent_skills "${PROJECT_ROOT}/.cursor" "Cursor"
fi
if [[ "${LINK_GEMINI}" == true ]]; then
  link_agent_skills "${PROJECT_ROOT}/.gemini" "Gemini"
fi

run_verify
