import AppKit
import SwiftUI

/// Canonical accent-derived fill token used across every prominent amber surface in
/// the app: primary action buttons (`primaryActionButtonStyle()`), selected sidebar
/// rows, selected conversation tabs, selected terminal session chips, user chat
/// bubbles, prompt-block question-card header pills, accent-toned diff preview rows,
/// composer inline-code / slash / `@mention` chip backgrounds and queued-message
/// chips (`AppMarkdownCodeBlockPalette.composerChipFillNSColor` is a structural
/// alias of `primaryNSColor` below, so composer chrome can't drift from selected
/// chrome), the transcript scroll-to-latest button, and the placeholder "Selected"
/// badge.
///
/// Pair the fill with `.primary` / `NSColor.labelColor` as foreground — `.primary`
/// adapts to both schemes and stays legible against the light and dark blends.
/// See `Alveary/Views/Components/Accent/AGENTS.md` for the full contract.
enum AppAccentFill {
    /// `NSColor` form of `primary`. Exposed because
    /// `AppMarkdownCodeBlockPalette.composerChipFillNSColor` aliases it — the
    /// composer's chip-drawing path is AppKit-level (`NSTextView` `setFill`,
    /// `NSAttributedString` attributes) so it needs an `NSColor`, not a SwiftUI
    /// `Color`. Every other caller uses `primary` (the SwiftUI wrapper) below.
    static let primaryNSColor: NSColor = .accentDerived { accent, appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            // Opaque blend toward black — `0.55` desaturates the amber so it
            // doesn't read as overly bright against the dark window background
            // while staying distinct from the window's near-black chrome.
            return accent.blended(withFraction: 0.55, of: .black) ?? accent
        default:
            // Opaque blend toward white rather than an alpha tint. Alpha-based
            // fills caused trouble for surfaces layered over non-background
            // content — the transcript's floating scroll-to-latest button used
            // to show ghost text from the transcript through its capsule.
            // `0.35` keeps the original amber family while making selected fills
            // read less washed out in light mode.
            return accent.blended(withFraction: 0.35, of: .white) ?? accent
        }
    }

    /// At-rest SwiftUI fill. Opaque blends — no alpha — so callers that layer
    /// the fill over non-uniform backgrounds (e.g. the transcript's floating
    /// scroll-to-latest button) render a consistent apparent color regardless
    /// of what sits behind them.
    static let primary: Color = Color(nsColor: primaryNSColor)

    /// Pressed-state SwiftUI fill. Bumps accent saturation against the muted
    /// `primary` fill so press feedback stays visible. Both modes narrow the
    /// blend toward the accent side (less neutral mixing); still fully opaque,
    /// no alpha.
    static let pressed: Color = Color(nsColor: .accentDerived { accent, appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return accent.blended(withFraction: 0.35, of: .black) ?? accent
        default:
            return accent.blended(withFraction: 0.25, of: .white) ?? accent
        }
    })
}

enum AppAccentIcon {
    static let foreground: Color = Color(nsColor: foregroundNSColor)

    static let foregroundNSColor = NSColor(name: nil, dynamicProvider: { appearance in
        let accent = (NSColor(named: "AccentColor") ?? appAccentAssetFallback).resolved(for: appearance)
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return accent
        default:
            return accent.appLightModeIconVariant()
        }
    })
}

private let appAccentAssetFallback = NSColor(
    srgbRed: CGFloat(0xF6) / 255,
    green: CGFloat(0xC7) / 255,
    blue: CGFloat(0x55) / 255,
    alpha: 1
)

private extension NSColor {
    func appLightModeIconVariant() -> NSColor {
        let color = usingColorSpace(.sRGB) ?? self
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 1
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return NSColor(
            calibratedHue: hue,
            saturation: min(1, saturation * 1.45),
            brightness: min(brightness, 0.78),
            alpha: alpha
        )
    }
}
