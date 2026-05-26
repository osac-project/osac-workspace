---
name: osac-feature
description: Create Feature issues in the OSAC Jira project using the REST API. Use when the user wants to create a Feature, enhancement, or new capability request for OSAC.
---

# OSAC Feature Creation

Create Feature issues in the OSAC Jira project (https://redhat.atlassian.net/browse/OSAC).

## When to Use

- User asks to create a Feature, enhancement, or new capability request for OSAC
- User wants to track a new feature idea in Jira
- User provides feature requirements that should be formalized as a Jira issue

## Before Creating

Ask the user for:
1. **Feature summary** - One-line description (if not provided)
2. **Assignee** (optional) - Jira username to assign

Default label is always `OSAC`.

**Note:** Features do not have parent epics.

## Authentication

The OSAC project requires **Basic Auth** (not Bearer). Extract credentials from `~/.netrc`:

```bash
TOKEN=$(awk '/machine redhat.atlassian.net/ {found=1} found && /password/ {print $2; exit}' ~/.netrc)
EMAIL=$(awk '/machine redhat.atlassian.net/ {found=1} found && /login/ {print $2; exit}' ~/.netrc)
```

All API calls use: `-u "${EMAIL}:${TOKEN}"`

## Creating a Feature

Use the Jira REST API v2 directly:

```bash
curl -s -u "${EMAIL}:${TOKEN}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "project": {"key": "OSAC"},
      "summary": "Feature title here",
      "issuetype": {"name": "Feature"},
      "labels": ["OSAC"],
      "description": "Plain text description (will be converted to ADF)"
    }
  }' \
  "https://redhat.atlassian.net/rest/api/2/issue"
```

**Important:** For initial creation, use plain text description. You can update with ADF formatting afterward.

## Response Format

Success response contains:
```json
{
  "key": "OSAC-XXX",
  "self": "https://redhat.atlassian.net/rest/api/2/issue/XXXXXXX"
}
```

Always output the issue URL for the user: `https://redhat.atlassian.net/browse/OSAC-XXX`

## Formatting the Description (Optional)

To update the description with proper formatting, use Atlassian Document Format (ADF):

```bash
curl -s -u "${EMAIL}:${TOKEN}" \
  -X PUT \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "description": {
        "type": "doc",
        "version": 1,
        "content": [
          {
            "type": "heading",
            "attrs": {"level": 2},
            "content": [{"type": "text", "text": "Section Title"}]
          },
          {
            "type": "paragraph",
            "content": [{"type": "text", "text": "Paragraph text"}]
          },
          {
            "type": "bulletList",
            "content": [
              {
                "type": "listItem",
                "content": [
                  {
                    "type": "paragraph",
                    "content": [{"type": "text", "text": "List item"}]
                  }
                ]
              }
            ]
          }
        ]
      }
    }
  }' \
  "https://redhat.atlassian.net/rest/api/3/issue/OSAC-XXX"
```

**Note:** Use API v3 for ADF updates.

## ADF Building Blocks

### Heading
```json
{
  "type": "heading",
  "attrs": {"level": 2},  // or 3 for H3
  "content": [{"type": "text", "text": "Heading Text"}]
}
```

### Paragraph
```json
{
  "type": "paragraph",
  "content": [{"type": "text", "text": "Paragraph text"}]
}
```

### Paragraph with Bold
```json
{
  "type": "paragraph",
  "content": [
    {
      "type": "text",
      "text": "Bold text",
      "marks": [{"type": "strong"}]
    }
  ]
}
```

### Bullet List
```json
{
  "type": "bulletList",
  "content": [
    {
      "type": "listItem",
      "content": [
        {
          "type": "paragraph",
          "content": [{"type": "text", "text": "Item 1"}]
        }
      ]
    },
    {
      "type": "listItem",
      "content": [
        {
          "type": "paragraph",
          "content": [{"type": "text", "text": "Item 2"}]
        }
      ]
    }
  ]
}
```

### Numbered List
```json
{
  "type": "orderedList",
  "content": [
    {
      "type": "listItem",
      "content": [
        {
          "type": "paragraph",
          "content": [{"type": "text", "text": "Step 1"}]
        }
      ]
    }
  ]
}
```

## Example Workflow

1. Extract credentials from netrc
2. Create Feature issue with plain text description via API v2
3. Parse response to get issue key
4. (Optional) Update description with ADF formatting via API v3
5. Output the issue URL to the user

## Common Sections for OSAC Features

Features should follow this standard format:
- **Feature Goal** - What the feature aims to accomplish
- **Problem Statement** - The problem this feature solves
- **User Stories** - Use cases and scenarios from user perspective
- **Definition of Done** - Checklist of completion criteria
- **Out of Scope** - What is explicitly excluded from this feature

## Troubleshooting

- **"Client must be authenticated"**: Token is invalid or missing. User needs to regenerate at https://id.atlassian.com/manage-profile/security/api-tokens
- **"No project could be found with key 'OSAC'"**: Auth is working but user doesn't have OSAC project access
- **"Operation value must be a string"**: Trying to use ADF in API v2 - use v3 for ADF updates
- **jira-cli panics**: This is expected - don't use jira-cli for OSAC, use curl with REST API

## Notes

- OSAC project type: `software` (classic)
- Project key: `OSAC`
- Default label: `OSAC`
- Issue types available: Bug, Epic, Story, Task, Sub-task, Spike, Risk, Feature
- Features do not link to parent epics in the OSAC project
