@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    func testComposerSemanticColorHelpersMatchSwiftUIOpacityAlpha() throws {
        let darkView = NSView()
        darkView.appearance = NSAppearance(named: .darkAqua)
        try assertComposerColor(
            appKitComposerPrimaryColor(in: darkView, opacity: 0.35),
            matches: NSColor.labelColor,
            opacity: 0.35,
            in: darkView
        )
        try assertComposerColor(
            appKitComposerSecondaryColor(in: darkView, opacity: 0.08),
            matches: NSColor.secondaryLabelColor,
            opacity: 0.08,
            in: darkView
        )

        let lightView = NSView()
        lightView.appearance = NSAppearance(named: .aqua)
        try assertComposerColor(
            appKitComposerPrimaryColor(in: lightView, opacity: 0.1),
            matches: NSColor.labelColor,
            opacity: 0.1,
            in: lightView
        )
        try assertComposerColor(
            appKitComposerSecondaryColor(in: lightView, opacity: 0.18),
            matches: NSColor.secondaryLabelColor,
            opacity: 0.18,
            in: lightView
        )
    }

    private func assertComposerColor(
        _ actual: NSColor,
        matches semanticColor: NSColor,
        opacity: CGFloat,
        in view: NSView
    ) throws {
        let expected = semanticColor
            .resolved(for: view.appKitRenderingAppearance)
            .withAlphaComponent(semanticColor.resolved(for: view.appKitRenderingAppearance).alphaComponent * opacity)
        let actualRGB = try XCTUnwrap(actual.usingColorSpace(.deviceRGB))
        let expectedRGB = try XCTUnwrap(expected.usingColorSpace(.deviceRGB))

        XCTAssertEqual(actualRGB.redComponent, expectedRGB.redComponent, accuracy: 0.001)
        XCTAssertEqual(actualRGB.greenComponent, expectedRGB.greenComponent, accuracy: 0.001)
        XCTAssertEqual(actualRGB.blueComponent, expectedRGB.blueComponent, accuracy: 0.001)
        XCTAssertEqual(actualRGB.alphaComponent, expectedRGB.alphaComponent, accuracy: 0.001)
    }
}
