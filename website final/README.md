# Trading Titans — Marketing Website

A self-contained static marketing site for the Trading Titans app. No build step,
no dependencies, no hosting required — it runs from plain HTML/CSS/JS.

## Pages
- `index.html` — main landing page (hero, features, how-it-works, screenshot
  showcase, tools, FAQ, download CTA).
- `terms.html` — Terms of Service (also suitable to link from inside the app).
- `privacy.html` — Privacy Policy (also suitable to link from inside the app).

## Features
- Premium royal-blue dark theme with glassmorphism.
- Parallax scrolling (orbs + floating cards), 3D phone tilt on hover, animated
  gradient mesh, live-feel price ticker, scroll-reveal animations.
- Fully responsive (desktop, tablet, mobile) with a reduced-motion fallback.
- App screenshots live in `assets/screenshots/`.

## Run locally
From inside this folder:

```bash
# Option A — Python (no install needed on most machines)
python -m http.server 5500

# Option B — Node
npx serve -l 5500
```

Then open: http://localhost:5500

> Note: open it via the local server (not by double-clicking the file) so all
> assets and links resolve correctly.

## Embedding the legal pages in the app
`terms.html` and `privacy.html` are standalone. You can either host them and load
them in an in-app WebView, or lift the text content into native screens.
The legal text here is a starting template — have it reviewed by a legal
professional before public launch.
