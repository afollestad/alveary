@preconcurrency import AppKit
import SwiftUI

enum AppMarkdownCodeBlockPalette {
    static func fillColor(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: fillNSColor(for: colorScheme))
    }

    static func borderColor(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: borderNSColor(for: colorScheme))
    }

    static func fillNSColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1)
        default:
            return NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        }
    }

    // Neutral-gray chip background used on standard app chrome (unselected sidebar rows,
    // unselected conversation tabs, assistant bubbles). Previously derived from
    // `controlAccentColor`, which made the chip track the system accent — visually
    // noisy on the default amber accent and inconsistent with the code-block fill. The
    // grayscale swatch reads as a neutral "this is code" signal regardless of accent.
    // Light mode uses a mid-gray that stands out against the near-white window chrome
    // and the code-block fill (~0.96 luminance); dark mode uses
    // a mid-gray that stands out against the dark window chrome (~0.12) and the dark
    // block fill (~0.17). `.labelColor` foreground (`inlineChipForegroundNSColor`
    // below) supplies the contrasting text in both modes.
    //
    // Note: the composer input field and queued-message rows use the accent-backed
    // palette below (`composerChipFillNSColor` / `composerChipForegroundNSColor`), not
    // this grayscale swatch — those surfaces are composer chrome and benefit from the
    // accent-tinted highlight to reinforce "this is live-input territory." The
    // foreground is `.labelColor`, not accent-derived, so the chip stays visually
    // aligned with other `AppAccentFill.primary` surfaces (see
    // `Alveary/Views/Components/Accent/AGENTS.md`).
    //
    // Built with a raw `NSColor(name:dynamicProvider:)` rather than `.accentDerived(...)`
    // because the resolved value does not depend on the system accent. Cached as a single
    // dynamic `NSColor` so repeated accesses return the same instance — important for
    // `NSColor` equality in attributed-string attributes (tests round-trip these colors
    // through `NSAttributedString`).
    static let inlineFillNSColor: NSColor = NSColor(name: nil, dynamicProvider: { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(white: 0.36, alpha: 1.0)
        default:
            return NSColor(white: 0.88, alpha: 1.0)
        }
    })

    // Shared foreground for both `.standard` and `.userBubble` inline chips (both
    // sit on grayscale fills, so `.labelColor` adapts correctly to either scheme).
    // A single token replaces what used to be two identical `static let`s — keeping
    // them separate was duplication without divergence.
    static let inlineChipForegroundNSColor: NSColor = NSColor.labelColor

    // Accent-derived chip background for composer surfaces — the live chips drawn over
    // the composer `NSTextView` (inline code, `/command`, `@mention`) and the chips
    // that appear inside queued-message rows rendered via `AppMarkdownText(inlineCodeStyle: .composer)`.
    // Composer chrome benefits from the brighter accent treatment so chips pop against
    // the composer's `.bar + secondary.opacity(0.08)` surface as the user is composing;
    // the rest of the app (thread rows, tabs, assistant bubbles) uses the neutral
    // grayscale `inlineFillNSColor` above.
    //
    // Aliased to `AppAccentFill.primaryNSColor` so the composer chip and every
    // selected-chrome surface resolve to the same dynamic `NSColor` by construction.
    // Prior iterations expressed the same blend math in both places and relied on a
    // "keep in lockstep" documentation contract; the structural alias makes drift
    // impossible. The shared `static let` also preserves `NSColor` equality for tests
    // that round-trip the value through `NSAttributedString` attributes.
    static let composerChipFillNSColor: NSColor = AppAccentFill.primaryNSColor

    // `.labelColor` is the canonical foreground pairing for `AppAccentFill.primary`
    // surfaces (see `Alveary/Views/Components/Accent/AGENTS.md`). User bubbles, selected sidebar rows, and
    // selected tab chips all use it, so composer chips now read at the same weight as
    // those surfaces instead of an accent-on-accent "all yellow" stack. White text in
    // dark mode / black text in light mode — both legible against the muted-amber
    // blended fill.
    static let composerChipForegroundNSColor: NSColor = .labelColor

    // Neutral-gray chip fill used when the chip sits on an accent-tinted surface —
    // currently the user chat bubble is the only consumer (sidebar thread rows and
    // conversation tabs lock their chip color to `.standard` across selection; see
    // `AppMarkdownInlineLabel`). The parent surface is `AppAccentFill.primary`, which
    // is already an accent blend — another accent-derived fill reads as "the same color
    // as the background" and fails contrast. A grayscale fill breaks the accent-on-accent
    // pattern and gives the chip a clearly distinct surface.
    // Light mode uses a near-white gray (so `.labelColor` black text pops); dark mode uses
    // a medium-dark gray (so `.labelColor` white text pops). Do not reintroduce a
    // `labelColor.withAlphaComponent(...)` fill here — it looks correct on darker accents
    // but vanishes into bright accent surfaces.
    //
    // Built with a raw `NSColor(name:dynamicProvider:)` rather than `.accentDerived(...)`
    // because the resolved value does not depend on the system accent — it's a pure
    // grayscale swatch. The `.accentDerived` helper's `performAsCurrentDrawingAppearance`
    // flattening is only load-bearing when the transform consumes `controlAccentColor`.
    static let userBubbleInlineFillNSColor: NSColor = NSColor(name: nil, dynamicProvider: { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(white: 0.18, alpha: 1.0)
        default:
            return NSColor(white: 0.93, alpha: 1.0)
        }
    })

    static func borderNSColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.26, green: 0.27, blue: 0.31, alpha: 1)
        default:
            return NSColor(srgbRed: 0.87, green: 0.87, blue: 0.90, alpha: 1)
        }
    }
}
