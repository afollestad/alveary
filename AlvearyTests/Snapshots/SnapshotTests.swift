import AppKit
@preconcurrency import SnapshotTesting
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class SnapshotTests: XCTestCase {
    func testExplicitFixedScaleSnapshotKeepsCallerPrecision() {
        XCTAssertEqual(
            fixedScaleSnapshotComparisonPrecision(
                precision: 0.99,
                perceptualPrecision: 0.98,
                relaxesForAutomaticOneXFallback: false
            ),
            SnapshotComparisonPrecision(pixel: 0.99, perceptual: 0.98)
        )
    }

    func testAutomaticOneXSnapshotFallbackRelaxesPrecision() {
        XCTAssertEqual(
            fixedScaleSnapshotComparisonPrecision(
                precision: 0.99,
                perceptualPrecision: 0.98,
                relaxesForAutomaticOneXFallback: true
            ),
            SnapshotComparisonPrecision(pixel: 0.9, perceptual: 0.9)
        )
    }

    func testEnvironmentForcedSnapshotRendererUsesAutomaticFallbackTolerance() {
        XCTAssertTrue(usesAutomaticOneXFallback(
            forceFixedScale: false,
            isFixedScaleRendererForced: true,
            screenScale: 2
        ))
    }

    func testOneXScreenUsesAutomaticFallbackTolerance() {
        XCTAssertTrue(usesAutomaticOneXFallback(
            forceFixedScale: false,
            isFixedScaleRendererForced: false,
            screenScale: 1
        ))
    }

    func testPerCallFixedScaleSnapshotDoesNotUseAutomaticFallbackTolerance() {
        XCTAssertFalse(usesAutomaticOneXFallback(
            forceFixedScale: true,
            isFixedScaleRendererForced: true,
            screenScale: 1
        ))
    }

    func testSnapshotHostTeardownSuspendsForQueuedMainActorWork() async {
        let probe = SnapshotHostTeardownProbe()
        Task { @MainActor [probe] in
            probe.didRun = true
        }

        XCTAssertFalse(probe.didRun)
        await awaitSnapshotHostTeardown(retaining: probe)
        XCTAssertTrue(probe.didRun)
    }

    func testAutomaticOneXSnapshotFallbackNormalizesUniformCornerBackground() {
        let reference = snapshotBackgroundNormalizationTestImage(
            background: SnapshotPixel(red: 64, green: 64, blue: 64, alpha: 255)
        )
        let failure = snapshotBackgroundNormalizationTestImage(
            background: SnapshotPixel(red: 16, green: 16, blue: 16, alpha: 255)
        )
        let images = oneXSnapshotImagesNormalizingCornerBackground(
            reference: reference,
            failure: failure
        )

        XCTAssertNil(
            Diffing<NSImage>.image(precision: 0.9, perceptualPrecision: 0.9)
                .diffV2(images.reference, images.failure)
        )
    }

    func testAppTextEditorInlineHint() {
        let text = "/review-github-pr "
        let selection = TextSelection(insertionPoint: text.endIndex)

        assertMacSnapshot(
            AppTextEditor(
                text: .constant(text),
                selection: .constant(selection),
                minHeight: 68,
                idealHeight: 68,
                maxHeight: 144,
                placeholder: "Ask anything, @ to add files, / for skills",
                cornerRadius: 18,
                horizontalPadding: 10,
                verticalPadding: 10,
                sizesToContent: true,
                textChips: ChatComposerTextSupport.composerTextChips(in:),
                inlineHint: AppTextEditorInlineHint(text: "[PR URL]")
            ),
            size: CGSize(width: 760, height: 120),
            named: "app_text_editor_inline_hint"
        )
    }

    func testSkillsScreenPopulated() async {
        let viewModel = SkillsViewModel(skillsService: SnapshotSkillsService())
        await viewModel.load()

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_populated"
        )
    }

    func testMCPScreenPopulated() async {
        let viewModel = MCPViewModel(mcpService: SnapshotMCPService())
        await viewModel.load()

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "mcp_screen_populated"
        )
    }

}

@MainActor
private final class SnapshotHostTeardownProbe {
    var didRun = false
}

private func snapshotBackgroundNormalizationTestImage(background: SnapshotPixel) -> NSImage {
    let pixelSize = 8
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let bitmapData = bitmap.bitmapData else {
        fatalError("Unable to create snapshot background normalization fixture")
    }
    let foreground = SnapshotPixel(red: 255, green: 192, blue: 0, alpha: 255)
    for row in 0..<pixelSize {
        for column in 0..<pixelSize {
            let pixel = (2..<6).contains(row) && (2..<6).contains(column) ? foreground : background
            let offset = row * bitmap.bytesPerRow + column * 4
            bitmapData[offset] = pixel.red
            bitmapData[offset + 1] = pixel.green
            bitmapData[offset + 2] = pixel.blue
            bitmapData[offset + 3] = pixel.alpha
        }
    }
    let size = CGSize(width: pixelSize, height: pixelSize)
    bitmap.size = size
    let image = NSImage(size: size)
    image.addRepresentation(bitmap)
    return image
}
