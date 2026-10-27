# alveary.af.codes

This branch *is* the published site. GitHub Pages serves it from the repo root, so anything committed here goes live. There is no build step: `index.html`, the sheets in `styles/`, the scripts in `scripts/` and the assets in `images/` ship verbatim. Preview with a local static server (`python3 -m http.server`) rather than opening the file directly, so relative paths resolve the way they will in production.

## Look

- The page is a sibling of chromahora.af.codes and carouline.af.codes, sharing their hero, buttons, chips, footer and scroll-to-top button. Carry layout changes across from their `gh-pages` branches rather than letting the three drift apart.
- The colors come from the app, so keep them in step with it on `main`: `--accent` from `AccentColor`, and the title gradient, glows and comb from the amber of `AppIcon.icon`'s fill. `--accent` is too light for text on the light theme, so it only fills; text, focus rings and hover use `--accent-text`.
- The hero is a hive: a honeycomb fading down from the top over a glow behind the window. The comb is an inline SVG `<pattern>` stroked in `currentColor`, which the theme sheets set from `--comb`.
- Feature sections are centered rather than split beside their text like the siblings' phones, since a window screenshot needs the full width.
- The footer gradients that use `in oklab` follow an sRGB copy with literal colors, since a `var()` in the second declaration would defeat the fallback.

## Theming

`styles/index-light.css` and `styles/index-dark.css` hold the color tokens and the glows, and `styles/index-common.css` holds everything theme-independent. Both theme sheets ship on every load, media-scoped to `prefers-color-scheme`, so with no override the browser follows the OS on its own, including live appearance changes, with no JavaScript involved.

`scripts/dark-mode.js` only steps in when the toggle stores an override. It flips `media` to `all` or `not all` on the sheets and on every `<picture>` source with a `data-theme` (the app icon and the screenshots), and sets both `theme-color` metas to the override's color. Anything else that varies by theme follows that pattern: ship both variants, media-scope them, and let the script flip them. Don't swap `src` from script or hide a duplicate with `display`, since a hidden `<img>` still downloads and a script-set `src` leaves the page unthemed without JavaScript.

## Images

Every screenshot ships twice, once per theme: `-light` and `-dark` alongside each other in `images/`. Both are captures of the same window in the same state, so a single `alt` describes either one.

### Preparing a screenshot

Capture the window at 2x (`⌘⇧4`, then Space). That yields a PNG with the window on a transparent field, ringed by macOS's window shadow. Then:

1. **Crop to the window.** Take the bounding box of *fully opaque* pixels (alpha 255). The shadow is everything with partial alpha, and the page draws its own shadow in CSS. Thresholding lower than opaque pulls in shadow, and how much it pulls in differs between the light and dark captures, which silently misaligns the pair.
2. **Cut the corners.** Inside that box, every pixel that isn't fully opaque is a rounded corner where the capture blended the window edge into the shadow behind it. Set those to fully transparent, alpha *and* color: they're premultiplied, so leaving dark RGB behind fringes the downscale. Skip this and each corner draws a gray wedge over the light background, which is invisible while you're only looking at the dark shot.
3. **Downscale by a fraction the crop divides evenly by** (three quarters, at the window size the current set was captured at), which re-antialiases the corner from the hard edge left by step 2. Dividing evenly keeps the crop's aspect ratio exact and both sides integral. Pick the fraction landing just past 2x the 960px the shots are displayed at, `.screenshot`'s `max-width`. Every shot ships at that one size: `.screenshot` pins the ratio in `aspect-ratio` and each `<img>` repeats the size in `width`/`height` to reserve layout space. So capture the whole set at one window size, and update both of those when the window shape changes.
4. **Encode lossless WebP** (`cwebp -lossless -z 9 -alpha_q 100`). These are UI screenshots, where lossy ringing around text is obvious, and lossless lands around 200-300 KB each.

ImageMagick isn't installed on this machine. `cwebp`/`dwebp` and `sips` are, and steps 1-3 are a short CoreGraphics script (`CGImageSourceCreateWithURL`, walk the alpha channel, `cropping(to:)`, redraw into a smaller context).

### Wiring one up

```html
<picture>
    <source srcset="images/screenshot-x-dark.webp" type="image/webp" data-theme="dark"
        media="(prefers-color-scheme: dark)">
    <img class="screenshot" src="images/screenshot-x-light.webp" alt="…"
        width="…" height="…" loading="lazy" decoding="async">
</picture>
```

The dark variant is the `<source>` and the light one is the `<img>` fallback, so only the matching appearance is downloaded. `data-theme` is what `dark-mode.js` keys on. The one wrinkle: a visitor whose stored override contradicts their OS setting fetches the wrong variant first, because the preload scanner reaches the `<source>` before any script can flip it. That costs one image fetch for that visitor and is the price of keeping real `<img>` elements, with alt text, lazy loading and a working no-JS page.

### Icons

- `images/app-icon-light.png` and `-dark.png` are Icon Composer renders of `AppIcon.icon` on `main`, with the plate and corner mask already in them, scaled to 256x256: `"/Applications/Icon Composer.app/Contents/Executables/ictool" AppIcon.icon --export-image --output-file out.png --platform macOS --rendition Default --width 1024 --height 1024 --scale 1`, with `--rendition Dark` for the dark one.
- `favicon-light.*` mirrors the app icon: the dark bee on a gold plate whose gradient comes from `AppIcon.icon`'s fill, so re-export the icons if that changes. The SVG embeds its bee as a 96px PNG; `favicon-light.png` is the same artwork rasterized for browsers that don't take SVG icons.
- Favicons aren't themed, deliberately. A graphite plate is the obvious dark counterpart, but Safari draws its own light backdrop behind any favicon too dark for its dark tab bar; even a fully opaque graphite square comes out ringed in white, and the plate has to reach roughly `#7A7A72` before Safari leaves it alone. Safari also reads `rel="icon"` once at load and ignores every later change to those links, so the toggle can't flip a themed icon anyway. Gold reads cleanly against both tab bars, so it is the only plate shipped, and `apple-touch-icon.png` matches it.
- Export the favicon `.png` files with **transparent** corners. The rounded plate leaves the corners empty, and a rasterizer that flattens onto white bakes an opaque white matte into them that shows as light corner artifacts in the tab bar.

### Link preview

`images/og-image.png` is 1200x630 on the dark theme's opaque `#120e07`, under the dark glow and comb: the dark icon, the name in the dark title gradient and a one-line tagline on the left, and the dark `screenshot-main` on the right, cut off by the right and bottom edges. It's rendered from a scratch page that links `styles/index-common.css` and `styles/index-dark.css` and copies the comb's `<svg>` from `index.html`, with headless Chrome: `--headless=new --force-dark-mode --hide-scrollbars --window-size=1200,630 --screenshot`. A preview can't know the reader's theme, and composites transparency unpredictably. Re-export it whenever the hero screenshot or the dark `--bg` changes, and keep it a PNG, since crawler support for WebP is patchy.
