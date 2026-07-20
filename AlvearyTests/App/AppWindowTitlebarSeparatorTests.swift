import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class AppWindowTitlebarSeparatorTests: XCTestCase {
    func testPaneHeaderHairlineOccupiesOnePhysicalPixelInLightAndDark() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            let background = sampleBackground(for: colorScheme)
            let baseline = try renderSeparatorSample(
                surface: nil,
                colorScheme: colorScheme,
                background: background
            )
            let separator = try renderSeparatorSample(
                surface: .paneHeader,
                colorScheme: colorScheme,
                background: background
            )

            XCTAssertEqual(
                try differingRows(baseline, separator).count,
                1,
                "Expected one physical separator row in \(colorScheme) mode"
            )
        }
    }

    func testTitlebarAndPaneHeaderCalibrationResolveToMatchingPixels() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            let background = sampleBackground(for: colorScheme)
            let baseline = try renderSeparatorSample(
                surface: nil,
                colorScheme: colorScheme,
                background: background
            )
            let paneHeader = try renderSeparatorSample(
                surface: .paneHeader,
                colorScheme: colorScheme,
                background: background
            )
            let titlebar = try renderSeparatorSample(
                surface: .titlebar,
                colorScheme: colorScheme,
                background: background
            )
            let paneHeaderRows = try differingRows(baseline, paneHeader)
            let titlebarRows = try differingRows(baseline, titlebar)
            XCTAssertEqual(paneHeaderRows.count, 1)
            XCTAssertEqual(titlebarRows.count, 1)
            let paneHeaderRow = try XCTUnwrap(paneHeaderRows.first)
            let titlebarRow = try XCTUnwrap(titlebarRows.first)
            let backgroundColor = try renderedColor(in: baseline, row: paneHeaderRow)
            let paneHeaderColor = try renderedColor(in: paneHeader, row: paneHeaderRow)
            let titlebarColor = try renderedColor(in: titlebar, row: titlebarRow)
            let minimumContrast: CGFloat = colorScheme == .light ? 18.0 / 255.0 : 12.0 / 255.0

            assertMatchingRGB(paneHeaderColor, titlebarColor, accuracy: 1.0 / 255.0)
            assertMinimumRGBContrast(paneHeaderColor, backgroundColor, minimum: minimumContrast)
        }
    }

    private func renderSeparatorSample(
        surface: AppSeparatorHairline.Surface?,
        colorScheme: ColorScheme,
        background: Color,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSBitmapImageRep {
        let size = CGSize(width: 16, height: 3)
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        let rootView = SeparatorSample(
            surface: surface,
            background: background
        )
        .environment(\.colorScheme, colorScheme)
        .frame(width: size.width, height: size.height)
        let controller = NSHostingController(rootView: AnyView(rootView))
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.appearance = NSAppearance(named: appearanceName)

        let offscreenOrigin = CGPoint(x: -size.width - 1000, y: -size.height - 1000)
        let window = NSWindow(
            contentRect: CGRect(origin: offscreenOrigin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearanceName)
        window.contentViewController = controller
        defer { closeSnapshotWindow(window, controller: controller) }

        window.makeFirstResponder(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()

        let bitmap = try XCTUnwrap(
            controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds),
            file: file,
            line: line
        )
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        return bitmap
    }

    private func differingRows(
        _ first: NSBitmapImageRep,
        _ second: NSBitmapImageRep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [Int] {
        XCTAssertEqual(first.pixelsWide, second.pixelsWide, file: file, line: line)
        XCTAssertEqual(first.pixelsHigh, second.pixelsHigh, file: file, line: line)

        var rows: [Int] = []
        for row in 0..<min(first.pixelsHigh, second.pixelsHigh) {
            let firstColor = try renderedColor(in: first, row: row, file: file, line: line)
            let secondColor = try renderedColor(in: second, row: row, file: file, line: line)
            if !firstColor.matches(secondColor, accuracy: 1.0 / 255.0) {
                rows.append(row)
            }
        }
        return rows
    }

    private func renderedColor(
        in bitmap: NSBitmapImageRep,
        row: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> RGBColor {
        let color = try XCTUnwrap(
            bitmap.colorAt(x: bitmap.pixelsWide / 2, y: row)?.usingColorSpace(.deviceRGB),
            file: file,
            line: line
        )
        return RGBColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }

    private func assertMatchingRGB(
        _ first: RGBColor,
        _ second: RGBColor,
        accuracy: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(first.red, second.red, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(first.green, second.green, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(first.blue, second.blue, accuracy: accuracy, file: file, line: line)
    }

    private func assertMinimumRGBContrast(
        _ foreground: RGBColor,
        _ background: RGBColor,
        minimum: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(abs(foreground.red - background.red), minimum, file: file, line: line)
        XCTAssertGreaterThanOrEqual(abs(foreground.green - background.green), minimum, file: file, line: line)
        XCTAssertGreaterThanOrEqual(abs(foreground.blue - background.blue), minimum, file: file, line: line)
    }

    private func sampleBackground(for colorScheme: ColorScheme) -> Color {
        // The live pane is white in light mode and resolves to RGB 36 in dark mode.
        let component: Double = colorScheme == .light ? 1 : 36.0 / 255.0
        return Color(.sRGB, red: component, green: component, blue: component)
    }

}

private struct SeparatorSample: View {
    let surface: AppSeparatorHairline.Surface?
    let background: Color

    var body: some View {
        background
            .overlay(alignment: edgeAlignment) {
                if let surface {
                    AppSeparatorHairline(surface: surface)
                }
            }
    }

    private var edgeAlignment: Alignment {
        switch surface {
        case .some(.titlebar):
            .top
        case .some(.paneHeader), .none:
            .bottom
        }
    }
}

private struct RGBColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    func matches(_ other: RGBColor, accuracy: CGFloat) -> Bool {
        abs(red - other.red) <= accuracy
            && abs(green - other.green) <= accuracy
            && abs(blue - other.blue) <= accuracy
    }
}
