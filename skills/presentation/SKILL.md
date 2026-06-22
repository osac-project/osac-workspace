---
name: presentation
description: Create Red Hat-branded Marp presentations (slide decks). Produces a self-contained Marp markdown deck using the shared redhat theme, renders to HTML and PPTX. Encodes the hard-won rules for image paths and PPTX export so layouts and assets survive conversion.
version: 1.0.0
user-invocable: true
arguments: "[topic or outline]"
triggers:
  - create a presentation
  - new presentation
  - make slides
  - build a deck
  - slide deck
  - marp deck
  - convert to google slides
  - export pptx
---

# Presentation Skill

Create a Red Hat-branded slide deck as a [Marp](https://marp.app/) markdown file under [`presentations/`](../../presentations/), render it, and (when asked) export a PPTX for Google Slides import.

## Workflow

1. **Gather inputs.** Confirm the outline, the audience, and any source material (quotes, images, data). For each slide know: what class it is (content / title / divider / dark / cover) and whether it carries an image.
2. **Copy every image into [`presentations/assets/`](../../presentations/assets/)** before referencing it. Never reference `~/Documents`, `~/Downloads`, or any absolute path — the deck must be self-contained so it renders for anyone who clones the repo. `cp <source> presentations/assets/<name>`.
3. **Write the deck** as `presentations/<slug>.md` using `theme: redhat` (see Frontmatter below).
4. **Render and review** (see Rendering). Iterate on layout.
5. **If a PPTX / Google Slides export is requested**, follow the PPTX rules below — they change how you must author the slides.
6. **Do not commit rendered output** (`*.html`, `*.pptx`). These are build artifacts.

## Frontmatter

Use the shared theme — do **not** paste a giant inline `style:` block. The theme lives at [`presentations/themes/redhat.css`](../../presentations/themes/redhat.css) and is registered by `presentations/.marprc.yml`.

```yaml
---
marp: true
theme: redhat
paginate: true
---
```

Add a small per-deck `style:` block **only** for slide-specific tweaks (e.g. a compact table, a left-aligned overflow fix). Keep brand fonts/colors in the theme.

## Slide classes (from the redhat theme)

Set per-slide with `<!-- _class: name -->` directly above the slide content.

| Class | Use for | Look |
|---|---|---|
| *(none)* | Standard content slide | White bg, black text, red `h2` underline |
| `title` | Opening / closing slide | Black bg, white text, red top bar |
| `divider` | Section break | Solid red bg, white text |
| `dark` | High-impact statement / quote | Black bg, centered, red accents |
| `cover` | Full-bleed image slide | See Images below |
| `scorecard` / custom | Dense tables | Define a small `style:` override |

## Images

- **Inline, sized:** `![w:900](assets/x.png)` or `![h:560](assets/x.png)`. Prefer `h:` when a slide has a heading so the image fits under it without clipping.
- **Full-bleed background:** `![bg fit](assets/x.png)` shows the whole image (letterboxed); `![bg cover]` fills and crops.
- **Split layout (image + text):** `![bg left:50% contain](assets/x.png)` puts the image on the left half and lets the slide's markdown flow on the right. **Use this instead of HTML `<div>` columns** — it is the only split layout that survives PPTX export.

## Footers / source links

Use Marp's **native footer directive**, never a raw `<footer>` HTML tag:

```markdown
<!-- _footer: "Source: [Title](https://example.com)" -->
```

A raw `<footer>...</footer>` renders as literal text in PPTX. The native directive works in both HTML and PPTX.

## Rendering

Run from the **repo root**. Always pass `--theme-set` to load the Red Hat theme explicitly and `--allow-local-files` so relative `assets/...` paths resolve. Do **not** rely on `.marprc.yml` — its `./themes` path only resolves when Marp runs from `presentations/`, which is easy to get wrong.

```sh
# HTML — for previewing and for presenting live (preserves clickable links)
npx @marp-team/marp-cli@latest --html --allow-local-files \
  --theme-set presentations/themes/redhat.css \
  presentations/<slug>.md -o presentations/<slug>.html
open presentations/<slug>.html

# PPTX — for Google Slides import / archival
npx @marp-team/marp-cli@latest --allow-local-files --pptx \
  --theme-set presentations/themes/redhat.css \
  presentations/<slug>.md -o presentations/<slug>.pptx
```

To import into Google Slides: Drive → upload the `.pptx`, or Slides → **File → Import slides**.

## PPTX export rules (critical)

Marp's PPTX renderer **rasterizes each slide as an image**. Two consequences govern how you must author the deck:

1. **Raw HTML does not survive.** `<div>` flex/grid layouts and `<footer>` tags render as broken layout or literal text. Use Marp-native constructs only:
   - Split layouts → `![bg left:50% contain]` (not `<div style="display:flex">`).
   - Footers → `<!-- _footer: -->` (not `<footer>`).
   - If you need columns of text, prefer the bg-split or two separate slides.
2. **Hyperlinks are not clickable** — they're baked into the slide image. For a live talk, **present from the HTML**. PPTX is for import/archival or for re-adding links manually in Google Slides (`Cmd+K`). Tell the user this when you hand off a PPTX.

The `--pptx-editable` flag (LibreOffice-backed) preserves text/links but breaks on custom CSS, tables, and bg images — **do not use it** for branded decks.

## Common layout fixes

- **Text overflows / balloons and wraps:** the base theme centers text. Add a per-slide class with `text-align: left;` and a smaller `font-size:` in a deck-local `style:` block, then `<!-- _class: yourclass -->` the slide. Trim copy to short bullets.
- **Image clipped at the bottom:** switch from `w:` to `h:` sizing (e.g. `![h:560]`) so it's bounded by slide height, leaving room for the heading.
- **Footer link has an ugly drop shadow:** the `uncover` base applies `text-shadow` to links; override with `section footer a { text-shadow: none; box-shadow: none; }`.
