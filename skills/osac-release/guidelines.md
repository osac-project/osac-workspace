# Output Formatting Guidelines

**CRITICAL:** Do NOT dump raw bash command output to the user. Run commands
silently and present results as clean, structured status lines with icons.
Every step must have a header and use the icon vocabulary below.

**Icon vocabulary:**

| Icon | Meaning |
|------|---------|
| `[Step N]` | Step header (always print before starting a step) |
| `✅` | Check passed / action succeeded |
| `❌` | Check failed / action failed |
| `📦` | Repo discovered or cloned |
| `🏷️`  | Tag operation (fetch, create, push) |
| `🔄` | Workflow monitoring / polling |
| `🔍` | Verification (OCI registry check) |
| `⏳` | Waiting / retrying |
| `⚠️`  | Warning (non-blocking) |
| `🚀` | Release summary / final result |

## Examples

**[Step 0] Pre-flight Checks**

  ✅ gh CLI authenticated (username)
  ✅ helm CLI available (v3.19.0)

  **Discovering repos...**
  📦 fulfillment-service             → /path/to/fulfillment-service
  📦 osac-operator                   → /path/to/osac-operator
  📦 osac-aap                        → /path/to/osac-aap
  📦 bare-metal-fulfillment-operator → /path/to/bare-metal-fulfillment-operator
  📦 osac-ui                         → /path/to/osac-ui
  📦 osac-installer                  → /path/to/osac-installer
  ✅ All 6 repos discovered. No uncommitted changes.

**[Step 1] Fetch Tags & Determine Current Versions**

  **Fetching upstream tags...**
  🏷️  fulfillment-service             → v0.0.69 (git tag)
  🏷️  osac-operator                   → v0.0.2  (git tag)
  🏷️  osac-aap                        → v0.0.4  (git tag)
  🔍 bare-metal-fulfillment-operator → (none)  (no git tags, checking OCI...)
  🏷️  osac-ui                         → v0.0.1  (git tag)
  🔍 osac (umbrella)                 → v0.0.2  (OCI fallback)

**[Step 4] Tag & Push Components**

  **Tagging upstream/main...**
  🏷️  fulfillment-service             → v0.0.70 pushed
  🏷️  osac-operator                   → v0.0.3  pushed
  🏷️  osac-aap                        → v0.0.5  pushed
  🏷️  bare-metal-fulfillment-operator → v0.0.1  pushed
  🏷️  osac-ui                         → v0.0.2  pushed
  ✅ All 5 component tags pushed.

**[Step 5] Monitor Publish Workflows**

  🔄 fulfillment-service             → ✅ completed
  🔄 osac-operator                   → ✅ completed
  🔄 osac-aap                        → ⏳ in_progress (45s)
  🔄 bare-metal-fulfillment-operator → ⏳ queued
  🔄 osac-ui                         → ⏳ queued

**[Step 9] Release Summary**

🚀 **Release Complete!** (Reason: Routine release)

┌──────────────────────────────────────┬─────────┬───────────────────────────────────────────────────────┐
│ Chart                                │ Version │ Registry                                              │
├──────────────────────────────────────┼─────────┼───────────────────────────────────────────────────────┤
│ fulfillment-service                  │ 0.0.70  │ oci://ghcr.io/osac-project/charts/fulfillment-service│
│ ...                                  │ ...     │ ...                                                   │
└──────────────────────────────────────┴─────────┴───────────────────────────────────────────────────────┘

## Rules

1. **ZERO narration.** NEVER output filler text like "Let me run the
   pre-flight checks", "Now let me validate...", "I'll clone the repos",
   "Moving to Step 1...", etc. The ONLY text the user should see between
   tool calls is formatted status lines with icons. No explanations, no
   transitions, no commentary. Just icons and results.

2. **Suppress bash output.** Redirect stdout with `>/dev/null` on every bash
   command. Keep stderr available (`2>&1` only on success paths) so failed
   commands can be diagnosed. The user must NEVER see raw git, helm, or gh
   output on success. On failure, show the captured stderr for debugging.

3. **Descriptive bash labels.** Always set the `description` parameter on
   every Bash tool call to a short, human-friendly label. The user sees
   this label in the UI. NEVER leave the description empty or set it to the
   command itself.

4. **Print progress BEFORE running.** Print the icon lines (📦, 🏷️, 🔄)
   BEFORE executing the bash command, so the user sees what is about to
   happen. Then run the command silently. Then print the result (✅ or ❌)
   after. NOT: run first, then print icons after (that is duplicate/late).

5. **Bold step headers.** Always print step headers in markdown bold:
   `**[Step 0] Pre-flight Checks**`. The `[Step N]` prefix and title must
   both be inside the bold markers.

6. **One status line per action.** After each bash command completes, print
   a single confirmation line with ✅ or ❌. Never print the bash command
   itself or its output.

7. **Batch operations into single commands.** When cloning, fetching tags,
   or pushing tags for multiple repos, run ALL repos in a single bash
   command (loop) rather than one command per repo. This minimizes the
   number of visible tool calls.

8. **Use indentation** (2 spaces) for status lines within a step.

9. **When polling workflows** (Step 5/8), re-print the status table on each
   poll iteration -- do not dump `gh run view` JSON.

10. **Box-drawing tables only.** Always use box-drawing characters
    (─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼) for tables in user-facing output. Never use
    markdown pipe tables.
