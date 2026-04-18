import AppKit
import SwiftUI

extension Color {
    /// Foreground color paired with `Color.accentColor` for contrast on filled surfaces.
    /// Resolves to near-black or white at draw time based on the resolved accent color's
    /// luminance so it stays legible whether the asset-catalog `AccentColor` is in use
    /// (default "Multicolor" accent preference) or macOS is tracking a different system
    /// accent like graphite or blue. A fixed-dark asset would fail against dark system
    /// accents; a fixed-white asset would fail against a bright asset-catalog accent.
    static let onAccent = Color(nsColor: .accentDerived { accent, _ in
        let luminance = 0.2126 * accent.redComponent
                      + 0.7152 * accent.greenComponent
                      + 0.0722 * accent.blueComponent
        return luminance > 0.6
            ? NSColor(white: 0.102, alpha: 1)
            : .white
    })
}

extension NSColor {
    /// Builds a dynamic `NSColor` whose provider resolves `NSColor.controlAccentColor`
    /// against the requested appearance and applies `transform` to derive the final
    /// per-appearance color. The accent is resolved to sRGB inside
    /// `performAsCurrentDrawingAppearance`, so `transform` operates on a concrete color —
    /// subsequent calls like `withAlphaComponent(_:)` or `blended(withFraction:of:)` are
    /// computed against the provider's appearance rather than whichever appearance
    /// happens to be current at call time (e.g. when a popover forces a scheme).
    /// The returned color still resolves lazily per appearance, so callers safely cache
    /// the result in `static let` storage.
    static func accentDerived(
        transform: @escaping (_ accent: NSColor, _ appearance: NSAppearance) -> NSColor
    ) -> NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            // Fall back to `NSColor.white` (a valid sRGB color with component accessors)
            // if `usingColorSpace(.sRGB)` ever returns nil. `controlAccentColor` resolved
            // inside `performAsCurrentDrawingAppearance` always converts in practice, but
            // the fallback avoids handing callers a named color whose `.redComponent`
            // would raise an exception.
            var result: NSColor = .white
            appearance.performAsCurrentDrawingAppearance {
                let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .white
                result = transform(accent, appearance)
            }
            return result
        })
    }

    /// Resolves a dynamic `NSColor` against `appearance` and flattens it to a concrete
    /// sRGB color. Use when a consumer requires per-appearance `Color` values up front
    /// (e.g. Textual's `DynamicColor(light:dark:)`) rather than a single `NSColor` that
    /// still carries a `dynamicProvider`. The flatten happens inside
    /// `performAsCurrentDrawingAppearance` so derived values like `controlAccentColor`
    /// resolve against the requested appearance, not whichever appearance was current at
    /// call time.
    func resolved(for appearance: NSAppearance) -> NSColor {
        var result: NSColor = self
        appearance.performAsCurrentDrawingAppearance {
            result = self.usingColorSpace(.sRGB) ?? self
        }
        return result
    }
}
