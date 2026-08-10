# alveary.af.codes

This branch *is* the published site — GitHub Pages serves it from the repo root, so
anything committed here goes live. There is no build step: `index.html`, the sheets
in `styles/`, the scripts in `scripts/`, and the assets in `images/` are shipped
verbatim. Preview with a local static server (`python3 -m http.server`) rather than
opening the file directly, so the relative paths resolve the way they will in
production.

## Theming

The page has two themes. `styles/index-light.css` and `styles/index-dark.css` hold
the color tokens; `styles/index-common.css` holds everything theme-independent.
Both sheets ship on every page load, media-scoped to `prefers-color-scheme`, so
with no override the browser follows the OS on its own — including live appearance
changes, with no JavaScript involved.

`scripts/dark-mode.js` only steps in when the toggle stores an override, and it
does so by flipping `media` to `all` / `not all`. **Anything that varies by theme
follows that same pattern**: ship both variants, media-scope them, and let the
script flip them. Don't introduce a third mechanism (swapping `src` from script,
duplicating elements and hiding one with `display`) — a hidden `<img>` still
downloads, and a script-set `src` leaves the page unthemed without JavaScript.

## Images

Every screenshot ships twice, once per theme: `-light` and `-dark` alongside each
other in `images/`. Both are captures of the same window in the same state, so a
single `alt` describes either one.

### Preparing a screenshot

Capture the window at 2x (`⌘⇧4`, then Space) — that yields a PNG with the window
on a transparent field, ringed by macOS's window shadow. Then:

1. **Crop to the window.** Take the bounding box of *fully opaque* pixels
   (alpha 255) — the shadow is everything with partial alpha, and the page draws
   its own shadow in CSS. Thresholding lower than opaque pulls in shadow, and how
   much it pulls in differs between the light and dark captures, which silently
   misaligns the pair.
2. **Cut the corners.** Inside that box, every pixel that isn't fully opaque is a
   rounded corner where the capture blended the window edge into the shadow behind
   it. Set those to fully transparent (alpha *and* color — premultiplied, so
   leaving dark RGB behind fringes the downscale). Skip this and each corner draws
   a gray wedge over the light background, which is invisible while you're only
   looking at the dark shot.
3. **Downscale to 1952x1136**, which re-antialiases the corner from the hard edge
   left by step 2. Keep this size: `.screenshot` pins `aspect-ratio: 1952 / 1136`
   and each `<img>` repeats it in `width`/`height` to reserve layout space.
4. **Encode lossless WebP** (`cwebp -lossless -z 9 -alpha_q 100`). These are UI
   screenshots — lossy ringing around text is obvious, and lossless lands around
   200-300 KB each.

ImageMagick isn't installed on this machine. `cwebp`/`dwebp` and `sips` are, and
steps 1-3 are a short CoreGraphics script (`CGImageSourceCreateWithURL`, walk the
alpha channel, `cropping(to:)`, redraw into a smaller context).

### Wiring one up

```html
<picture>
    <source srcset="images/screenshot-x-dark.webp" type="image/webp" data-theme="dark"
        media="(prefers-color-scheme: dark)">
    <img class="screenshot" src="images/screenshot-x-light.webp" alt="…"
        width="1952" height="1136" loading="lazy" decoding="async">
</picture>
```

The dark variant is the `<source>` and the light one is the `<img>` fallback, so
only the matching appearance is downloaded. `data-theme` is what `dark-mode.js`
keys on. The one wrinkle: a visitor whose stored override contradicts their OS
setting fetches the wrong variant first, because the preload scanner reaches the
`<source>` before any script can flip it. That costs one image fetch for that
visitor and is the price of keeping real `<img>` elements — with alt text, lazy
loading, and a working no-JS page.

### Icons

`favicon-light.*` and `favicon-dark.*` mirror the app icon: a gold plate under the
dark bee, a graphite plate under the gold one. The plate gradients come from
`.app-icon` in the theme sheets — if those change, re-export the icons. Each SVG
embeds its bee as a 96px PNG; the `.png` files are the same artwork rasterized for
browsers that don't take SVG icons.

Icons are the exception to the media-scoping rule above: browsers honor `media` on
`rel="icon"` inconsistently and settle on one icon rather than re-running the query
later, so `dark-mode.js` applies them on *every* theme change, override or not, and
re-inserts each link to make the browser look again. The dark pair is listed first
in `<head>` so a browser that ignores `media` entirely falls back to the light one.
`apple-touch-icon.png` stays light — home screen icons can't follow the theme.

### Link preview

`images/og-image.png` is the **dark** hero screenshot letterboxed onto an opaque
`#0b0b0a` canvas (the dark `--bg`) at 1200x630, with 32px top and bottom margins
and centered horizontally. A preview can't know the reader's theme, so it always
gets the dark shot on its matching canvas. Re-export it whenever the hero
screenshot changes. It has to stay a PNG: crawler support for WebP is patchy, and
the screenshot's transparent corners composite unpredictably in previews.
