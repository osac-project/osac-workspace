# OSAC Enhancement Proposal Generator

A Claude Code plugin for generating OSAC enhancement proposals from high-level requirements.

## Skills

### generate-ep

Generate a structured OSAC enhancement proposal from:
- Conversational requirements (describe what you want to build)
- Meeting notes or requirements documents (point to a file)
- Jira tickets (provide a ticket number like MGMT-XXXXX)
- PR review feedback (iterate on an existing EP PR)

The skill explores the codebase, asks clarifying questions, drafts a full EP following the osac-project/enhancement-proposals template, and submits it as a PR.

**Usage:**
- "Draft an enhancement proposal for a storage network API"
- "Turn these meeting notes into an EP" (with file path)
- "Create an enhancement proposal from MGMT-24100"
- `/generate-ep review-feedback 42` — address reviewer comments on EP PR #42

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| gh | Yes | GitHub CLI for PR operations |
| jira | No (Jira mode only) | Jira CLI for `/generate-ep MGMT-XXXXX` mode |
| rg | Yes | ripgrep for codebase search |

## Installation

### Local testing
```bash
claude --plugin-dir /path/to/plugins/osac-ep-generator
```

## License

MIT
