---
name: browser-demo-recording
description: Record browser-based UI demos using Playwright and edit the video with ffmpeg (speed up, trim, concatenate, add title cards). Use when creating demo recordings of web UIs — Enclave Wizard, osac-ui, OpenShift console, or any browser-based workflow.
metadata:
  version: "0.1.0"
---

# Browser Demo Recording

Record a browser-based UI demo with Playwright video capture, then edit the result with ffmpeg — trim, speed up slow sections, add title cards, and produce a final video.

## Prerequisites

```bash
# One-time: build the Playwright container image
podman build -t osac-playwright -f Containerfile.playwright .

# Verify it works
scripts/playwright.sh npx playwright --version
```

All Playwright commands run inside the `osac-playwright` container via `scripts/playwright.sh` — no local Playwright or browser installation needed. ffmpeg is available both inside the container and in the Distrobox.

## Container Architecture

Playwright runs in a dedicated Ubuntu-based container (`Containerfile.playwright`), NOT in the Fedora Distrobox (Playwright doesn't support Fedora). The wrapper script `scripts/playwright.sh` handles:

- Bind-mounting the workspace at `/work`
- X11/Wayland passthrough for headed mode (when `DISPLAY` or `WAYLAND_DISPLAY` is set)
- `--userns=keep-id` to avoid root-owned output files
- `EXTRA_PODMAN_ARGS` env var for mounting additional paths (secrets, external files)

For scripts that need files outside the workspace, create a launcher shell script (see `scripts/record-enclave-wizard.sh` for an example) that sets `EXTRA_PODMAN_ARGS` with the required `-v` mounts.

## When to Use

- Demonstrating browser-based UIs (Enclave Wizard, osac-ui, OpenShift console)
- Recording multi-step wizard flows, form interactions, deployment progress
- Any demo where terminal recording (asciinema) is not suitable

## Workflow

### 1. Gather Inputs

| Input | Required | Default |
|-------|----------|---------|
| Target URL | Yes | — |
| Output filename | No | `presentations/assets/<slug>-demo.webm` |
| Resolution | No | 1920×1080 |
| Mode | No | Scripted (headless) |
| Speed-up segments | No | None |

Ask the user:
- What is the URL of the UI to record?
- Should the recording be manual (user drives the browser, requires X11) or scripted (Playwright automates, works headless)?
- Are there long-running sections to speed up later? If so, what are the visual cues for where they start/end?

### 2. Generate the Recording Script

Create a Playwright script at `scripts/record-<slug>.mjs`.

**Import pattern**: The container has `playwright` installed globally. ESM `import` doesn't resolve global packages via `NODE_PATH`, so use `createRequire`:

```javascript
import { createRequire } from 'module';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import { readFileSync, existsSync } from 'fs';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
```

#### Headless vs headed mode

- **Headless** (`headless: true`): works in the container without X11. Video recording still captures the full page rendering. Use for scripted recordings.
- **Headed** (`headless: false`): requires X11 forwarding via `DISPLAY`. Use for manual mode where the user interacts with the browser.

Playwright's `recordVideo` captures browser rendering, not screen capture — headless recordings look identical to headed ones.

#### Scripted mode (recommended)

Build the script to walk through the UI with human-like timing. Always use the helpers below. Key patterns learned from production use:

**Step transitions in multi-step wizards:**

```javascript
async function clickNext(page) {
  await humanPause(rand(800, 1500));
  // Use force:true — PatternFly overlays can intercept pointer events
  const cont = page.getByRole('button', { name: 'Continue' });
  const next = page.getByRole('button', { name: 'Next' });
  // waitFor before branching — isVisible() is a one-shot check that
  // returns immediately; without waiting the UI may still be settling.
  try {
    await cont.waitFor({ state: 'visible', timeout: 3000 });
    await cont.click({ force: true });
  } catch {
    await next.waitFor({ state: 'visible', timeout: 5000 });
    await next.click({ force: true });
  }
  await page.waitForLoadState('networkidle');
  await humanPause(rand(1500, 2500));
}
```

**File uploads (PatternFly FileUpload)**: PF6 `FileUpload` components hide the native `<input type="file">`. Don't look for the input directly. Instead, wait for the step to render, then use the filechooser event:

```javascript
// Wait for the step content to render (use visible text, not element IDs)
await page.getByText('AAP subscription manifest').waitFor({ timeout: 15000 });
await humanPause(1000);

const uploadBtn = page.getByRole('button', { name: 'Upload' });
await uploadBtn.waitFor({ state: 'visible', timeout: 5000 });
const [fileChooser] = await Promise.all([
  page.waitForEvent('filechooser', { timeout: 10000 }),
  humanClick(page, uploadBtn),
]);
await fileChooser.setFiles('/work/path/to/file.zip');
```

**Large text fields** (pull secrets, SSH keys, YAML): Use `humanFill` (instant paste) instead of `humanType` (character-by-character) — typing a 2KB pull secret character by character takes minutes:

```javascript
async function humanFill(page, selector, text) {
  const el = page.locator(selector);
  await el.scrollIntoViewIfNeeded();
  await humanPause(rand(200, 400));
  await el.click();
  await humanPause(150);
  await el.fill(text);
  await humanPause(rand(200, 400));
}

await humanFill(page, '#pull-secret', pullSecretContent);
```

**Conditional elements** (buttons that may or may not be present):

```javascript
const validateBtn = page.getByRole('button', { name: 'Validate' });
try {
  await validateBtn.waitFor({ state: 'visible', timeout: 5000 });
  await humanClick(page, validateBtn);
  await humanPause(3000);
} catch { /* button not present — skip */ }
```

**Adding dynamic form entries** (nodes, hosts): Check if the entry already exists before clicking "Add":

```javascript
for (let i = 0; i < hosts.length; i++) {
  const nameField = page.locator(`#node-${i}-name`);
  try {
    await nameField.waitFor({ state: 'visible', timeout: 500 });
  } catch {
    const addBtn = page.getByRole('button', { name: 'Add node' });
    try {
      await addBtn.waitFor({ state: 'attached', timeout: 1000 });
      if (await addBtn.isEnabled()) {
        await humanClick(page, addBtn);
        await humanPause(500);
      }
    } catch { /* no add button — skip */ }
  }
  await humanType(page, `#node-${i}-name`, hosts[i].name);
  // ... fill remaining fields
}
```

**Expandable sections** (Advanced settings): Click the toggle, wait, then fill the hidden fields:

```javascript
const advancedToggle = page.locator('button:has-text("Advanced settings")').nth(i);
try {
  await advancedToggle.waitFor({ state: 'visible', timeout: 1000 });
  await humanClick(page, advancedToggle);
  await humanPause(400);
  await humanType(page, `#node-${i}-rootdisk`, host.disk);
} catch { /* toggle not present — skip */ }
```

**Selectors**: prefer `page.getByRole()` and `page.getByText()` over CSS selectors — they survive UI refactors better. Use `scripts/playwright.sh npx playwright codegen <URL>` to discover selectors interactively (requires X11).

#### Manual mode (user drives the browser)

Requires X11 forwarding. Use `headless: false`:

```javascript
const browser = await chromium.launch({ headless: false });
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: { dir: OUTPUT_DIR, size: { width: 1920, height: 1080 } },
});

const page = await context.newPage();
await page.goto(URL);

console.log('Recording — interact with the browser. Press Ctrl+C when finished.\n');

process.on('SIGINT', async () => {
  const video = page.video();
  await page.close();
  if (video) console.log(`Saved: ${await video.path()}`);
  await context.close();
  await browser.close();
  process.exit(0);
});

await new Promise(() => {});
```

### Human-Like Interaction Helpers

Paste these at the top of every scripted recording:

```javascript
function rand(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

async function humanPause(ms) {
  const base = ms || rand(400, 1200);
  const jitter = rand(-100, 200);
  await new Promise(r => setTimeout(r, Math.max(100, base + jitter)));
}

async function humanType(page, selector, text) {
  const el = page.locator(selector);
  await el.scrollIntoViewIfNeeded();
  await humanPause(300);
  await el.click();
  await humanPause(200);
  await el.fill('');
  for (const char of text) {
    await el.pressSequentially(char, { delay: rand(50, 140) });
    if (Math.random() < 0.05) await humanPause(rand(200, 500));
  }
  await humanPause(300);
}

async function humanClick(page, selectorOrLocator) {
  const el = typeof selectorOrLocator === 'string'
    ? page.locator(selectorOrLocator)
    : selectorOrLocator;
  await el.scrollIntoViewIfNeeded();
  await humanPause(rand(200, 500));
  await el.hover();
  await humanPause(rand(100, 300));
  await el.click();
  await humanPause(rand(300, 800));
}

async function humanFill(page, selector, text) {
  const el = page.locator(selector);
  await el.scrollIntoViewIfNeeded();
  await humanPause(rand(200, 400));
  await el.click();
  await humanPause(150);
  await el.fill(text);
  await humanPause(rand(200, 400));
}

async function humanSelect(page, selector, value) {
  await humanClick(page, selector);
  await humanPause(rand(300, 600));
  await page.selectOption(selector, value);
  await humanPause(rand(300, 700));
}
```

**Timing guidelines:**

| Action | Realistic delay |
|--------|----------------|
| Between fields in a form | 400–1200 ms |
| Before clicking "Next" | 1000–2000 ms |
| Typing speed | 50–140 ms per character |
| After a page transition | 1500–2500 ms |
| Before starting deployment | 2000–3000 ms |

### 3. Record

```bash
# Scripted (headless — no X11 needed)
scripts/playwright.sh node scripts/record-<slug>.mjs [URL]

# With external file mounts (secrets, manifests)
EXTRA_PODMAN_ARGS="-v $HOME/.ssh/id_ed25519.pub:/dot-ssh/id_ed25519.pub:ro,Z -v $HOME/src/secrets:/secrets:ro,Z" \
  scripts/playwright.sh node scripts/record-<slug>.mjs [URL]

# Or use a launcher script that sets up mounts (recommended)
scripts/record-<slug>.sh [URL]
```

The raw video lands in `presentations/assets/` with a Playwright-generated hash name. Rename it:

```bash
mv presentations/assets/<generated-id>.webm presentations/assets/<slug>-demo-raw.webm
```

### 4. Edit the Video

All editing uses ffmpeg. Build the commands based on what the user needs.

#### Trim (remove start/end)

```bash
ffmpeg -i raw.webm -ss 00:00:10 -to 00:45:00 -c copy trimmed.webm
```

#### Speed up a section

Split → speed up → concatenate:

```bash
# 1. Extract the normal-speed portion
ffmpeg -i raw.webm -t 00:02:30 -c copy part1-normal.webm

# 2. Extract the slow portion
ffmpeg -i raw.webm -ss 00:02:30 -c copy part2-raw.webm

# 3. Speed up (0.05 = 20x, 0.1 = 10x, 0.2 = 5x)
ffmpeg -i part2-raw.webm -filter:v "setpts=0.05*PTS" -an part2-fast.webm

# 4. Concatenate
cat > /tmp/concat.txt <<EOF
file '$(pwd)/part1-normal.webm'
file '$(pwd)/part2-fast.webm'
EOF
ffmpeg -f concat -safe 0 -i /tmp/concat.txt -c copy final.webm
```

**Speed reference:**

| Multiplier | Effect | 1 hour becomes |
|-----------|--------|----------------|
| `0.5` | 2× | 30 min |
| `0.1` | 10× | 6 min |
| `0.05` | 20× | 3 min |
| `0.02` | 50× | ~1 min |

#### Add a title card

```bash
ffmpeg -f lavfi \
  -i "color=c=black:s=1920x1080:d=3,drawtext=text='Enclave Wizard Demo':fontsize=72:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:fontfile=/usr/share/fonts/redhat-display/RedHatDisplay-Bold.otf" \
  -c:v libvpx-vp9 -pix_fmt yuv420p title.webm
```

Then prepend it:

```bash
cat > /tmp/concat.txt <<EOF
file '$(pwd)/title.webm'
file '$(pwd)/final.webm'
EOF
ffmpeg -f concat -safe 0 -i /tmp/concat.txt -c copy final-with-title.webm
```

#### Convert to MP4

```bash
ffmpeg -i final.webm -c:v libx264 -crf 23 -preset medium final.mp4
```

### 5. Publish

Copy the final video to `presentations/assets/` and link from the presentation.

## Selector Discovery

```bash
scripts/playwright.sh npx playwright codegen <URL>
```

Opens a browser with a recorder — click through the UI and it generates selector code. Requires X11 forwarding.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Browser won't launch | Rebuild: `podman build -t osac-playwright -f Containerfile.playwright .` |
| `ERR_MODULE_NOT_FOUND: playwright` | The container uses `createRequire` — don't use `import { chromium } from 'playwright'` |
| Headed mode fails (no X server) | Use `headless: true` for scripted recordings — video output is identical |
| `<div> intercepts pointer events` | Use `{ force: true }` on click — PatternFly overlays can block clicks |
| Step transition doesn't advance | Form validation is blocking — fill required fields or use `{ force: true }` on click |
| PF6 FileUpload: no `input[type="file"]` found | Use the `filechooser` event pattern (see File uploads above) |
| Video is blank/black | Ensure `recordVideo` is on the context, not the page |
| File too large | Lower resolution: `{ width: 1280, height: 720 }` |
| Speed-up looks choppy | Lower multiplier or re-encode: `ffmpeg -i fast.webm -c:v libvpx-vp9 -b:v 2M smooth.webm` |
| Concat fails "codec mismatch" | Re-encode both to same codec: `ffmpeg -i part.webm -c:v libvpx-vp9 -c:a libopus out.webm` |
| Root-owned output files | The wrapper uses `--userns=keep-id` — if missing, add it |
| TTY warning in CI/non-interactive | The wrapper detects TTY and omits `-it` when stdin isn't a terminal |

## Reference Implementation

See `scripts/record-enclave-wizard.mjs` and its launcher `scripts/record-enclave-wizard.sh` for a complete scripted recording that covers login, multi-step wizard, file upload, expandable sections, and deployment.
