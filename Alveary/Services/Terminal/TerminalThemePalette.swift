@preconcurrency import AppKit
import SwiftTerm

struct TerminalThemePalette {
    let background: NSColor
    let foreground: NSColor
    let caret: NSColor
    let caretText: NSColor
    let ansiColors: [NSColor]

    @MainActor
    static func resolved(for appearance: NSAppearance?) -> TerminalThemePalette {
        isDarkAppearance(appearance) ? dark : light
    }

    static func swiftTermColor(from color: NSColor, appearance: NSAppearance? = nil) -> SwiftTerm.Color {
        let rgbColor = color
            .terminalResolvedColor(for: appearance)
            .usingColorSpace(.sRGB)
            ?? color.terminalResolvedColor(for: appearance)
        return SwiftTerm.Color(
            red: UInt16(clamping: Int((rgbColor.redComponent * CGFloat(UInt16.max)).rounded())),
            green: UInt16(clamping: Int((rgbColor.greenComponent * CGFloat(UInt16.max)).rounded())),
            blue: UInt16(clamping: Int((rgbColor.blueComponent * CGFloat(UInt16.max)).rounded()))
        )
    }

    @MainActor
    func apply(to terminalView: TerminalView) {
        let appearance = terminalView.effectiveAppearance
        let resolvedBackground = background.terminalResolvedColor(for: appearance)
        let resolvedForeground = foreground.terminalResolvedColor(for: appearance)
        let resolvedCaret = caret.terminalResolvedColor(for: appearance)
        let resolvedCaretText = caretText.terminalResolvedColor(for: appearance)

        terminalView.nativeBackgroundColor = resolvedBackground
        terminalView.nativeForegroundColor = resolvedForeground
        terminalView.caretColor = resolvedCaret
        terminalView.caretTextColor = resolvedCaretText
        terminalView.installColors(ansiColors.map { Self.swiftTermColor(from: $0, appearance: appearance) })
        terminalView.wantsLayer = true
        terminalView.layer?.backgroundColor = resolvedBackground.cgColor
        terminalView.needsDisplay = true
    }

    private static var light: TerminalThemePalette {
        TerminalThemePalette(
            background: rgb(0xFAFBFC),
            foreground: rgb(0x1F2328),
            caret: rgb(0x1F2328),
            caretText: rgb(0xFFFFFF),
            ansiColors: [
                rgb(0x24292F),
                rgb(0xCF222E),
                rgb(0x116329),
                rgb(0x4D2D00),
                rgb(0x0969DA),
                rgb(0x8250DF),
                rgb(0x1B7C83),
                rgb(0x6E7781),
                rgb(0x57606A),
                rgb(0xA40E26),
                rgb(0x1A7F37),
                rgb(0x9A6700),
                rgb(0x0550AE),
                rgb(0x6639BA),
                rgb(0x3192AA),
                rgb(0x1F2328)
            ]
        )
    }

    private static var dark: TerminalThemePalette {
        TerminalThemePalette(
            background: rgb(0x0B0F14),
            foreground: rgb(0xE6EDF3),
            caret: rgb(0xE6EDF3),
            caretText: rgb(0x0B0F14),
            ansiColors: [
                rgb(0x484F58),
                rgb(0xFF7B72),
                rgb(0x7EE787),
                rgb(0xD29922),
                rgb(0x79C0FF),
                rgb(0xD2A8FF),
                rgb(0x76E3EA),
                rgb(0xB1BAC4),
                rgb(0x6E7681),
                rgb(0xFFA198),
                rgb(0xA5D6A7),
                rgb(0xE3B341),
                rgb(0xA5D6FF),
                rgb(0xE2C5FF),
                rgb(0xB3F0FF),
                rgb(0xF0F6FC)
            ]
        )
    }

    @MainActor
    private static func isDarkAppearance(_ appearance: NSAppearance?) -> Bool {
        let effectiveAppearance = appearance ?? NSApp.effectiveAppearance
        return effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / CGFloat(255)
        let green = CGFloat((hex >> 8) & 0xFF) / CGFloat(255)
        let blue = CGFloat(hex & 0xFF) / CGFloat(255)

        return NSColor(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: 1
        )
    }
}

private extension NSColor {
    func terminalResolvedColor(for appearance: NSAppearance?) -> NSColor {
        guard let appearance else {
            return self
        }

        var resolvedColor = self
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = self.usingColorSpace(.sRGB) ?? self
        }
        return resolvedColor
    }
}
