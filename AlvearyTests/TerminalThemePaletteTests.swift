@preconcurrency import AppKit
import SwiftTerm
import XCTest

@testable import Alveary

@MainActor
final class TerminalThemePaletteTests: XCTestCase {
    func testLightAndDarkDefaultColorsHaveReadableContrast() throws {
        let lightPalette = TerminalThemePalette.resolved(for: try XCTUnwrap(NSAppearance(named: .aqua)))
        let darkPalette = TerminalThemePalette.resolved(for: try XCTUnwrap(NSAppearance(named: .darkAqua)))

        XCTAssertGreaterThanOrEqual(contrastRatio(foreground: lightPalette.foreground, background: lightPalette.background), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(foreground: darkPalette.foreground, background: darkPalette.background), 4.5)
        XCTAssertEqual(lightPalette.ansiColors.count, 16)
        XCTAssertEqual(darkPalette.ansiColors.count, 16)
    }

    func testSwiftTermColorConversionUsesSixteenBitChannels() {
        let color = NSColor(srgbRed: 0.5, green: 0.25, blue: 1, alpha: 1)

        let swiftTermColor = TerminalThemePalette.swiftTermColor(from: color)

        XCTAssertEqual(swiftTermColor.red, 32_768)
        XCTAssertEqual(swiftTermColor.green, 16_384)
        XCTAssertEqual(swiftTermColor.blue, UInt16.max)
    }

    func testApplyUpdatesSwiftTermNativeColorsAndLayerBackground() throws {
        let terminalView = AlvearyLocalTerminalView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let palette = TerminalThemePalette.resolved(for: try XCTUnwrap(NSAppearance(named: .darkAqua)))

        palette.apply(to: terminalView)

        XCTAssertEqual(rgbComponents(of: terminalView.nativeBackgroundColor), rgbComponents(of: palette.background))
        XCTAssertEqual(rgbComponents(of: terminalView.nativeForegroundColor), rgbComponents(of: palette.foreground))
        XCTAssertEqual(rgbComponents(of: terminalView.caretColor), rgbComponents(of: palette.caret))
        XCTAssertEqual(rgbComponents(of: try XCTUnwrap(terminalView.caretTextColor)), rgbComponents(of: palette.caretText))
        XCTAssertEqual(terminalView.layer?.backgroundColor, palette.background.cgColor)
    }

    private func contrastRatio(foreground: NSColor, background: NSColor) -> Double {
        let foregroundLuminance = relativeLuminance(foreground)
        let backgroundLuminance = relativeLuminance(background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> Double {
        let components = rgbComponents(of: color)
        let red = linearized(components.red)
        let green = linearized(components.green)
        let blue = linearized(components.blue)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private func linearized(_ value: Double) -> Double {
        value <= 0.03928
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    private func rgbComponents(of color: NSColor) -> RGBComponents {
        let rgbColor = color.usingColorSpace(.sRGB) ?? color
        return RGBComponents(
            red: Double(rgbColor.redComponent),
            green: Double(rgbColor.greenComponent),
            blue: Double(rgbColor.blueComponent)
        )
    }

    private struct RGBComponents: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }
}
