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

    // Accent-tinted chip background; reads from the asset-catalog `AccentColor` via
    // `NSColor.controlAccentColor` and layers at low opacity so chips tint their parent
    // surface without overpowering surrounding text. Light mode bumps the opacity so the
    // fill still reads as amber against a white parent background instead of washing out
    // to near-white. Cached as a single dynamic NSColor so repeated accesses return the
    // same instance — important for NSColor equality in attributed-string attributes.
    static let inlineFillNSColor: NSColor = .accentDerived { accent, appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return accent.withAlphaComponent(0.22)
        default:
            return accent.withAlphaComponent(0.40)
        }
    }

    // Solid accent in dark mode reads well against the low-opacity tint, but in light
    // mode the same bright accent over a tinted fill loses contrast; blend the accent
    // toward black so the chip text stays legible. Deriving from `controlAccentColor`
    // keeps the foreground in sync with the `AccentColor` asset — swapping the asset to
    // a different hue produces a matching darkened foreground automatically.
    static let inlineForegroundNSColor: NSColor = .accentDerived { accent, appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return accent
        default:
            return accent.blended(withFraction: 0.70, of: .black) ?? accent
        }
    }

    // Neutral-gray chip fill used when the chip sits on an accent-tinted surface (user
    // bubble, selected sidebar row, selected conversation tab). The parent surface is
    // `AppSelectionStyle.rowFill`, which is already an accent tint — another accent-derived
    // fill at low opacity reads as "the same color as the background" and fails contrast,
    // especially in light mode where rowFill is a near-saturated accent. A grayscale fill
    // breaks the accent-on-accent pattern and gives the chip a clearly distinct surface.
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
            return NSColor(white: 0.25, alpha: 1.0)
        default:
            return NSColor(white: 0.93, alpha: 1.0)
        }
    })

    static let userBubbleInlineForegroundNSColor: NSColor = NSColor.labelColor

    static func borderNSColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.26, green: 0.27, blue: 0.31, alpha: 1)
        default:
            return NSColor(srgbRed: 0.87, green: 0.87, blue: 0.90, alpha: 1)
        }
    }
}
