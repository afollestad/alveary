import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
final class BlockInputComposerStyleTests: XCTestCase {
    func testComposerStyleLeavesEditorSurfaceBackgroundsTransparent() {
        let style = BlockInputComposerStyle.make()

        XCTAssertNil(style.editorSurface.editorBackgroundColor)
        XCTAssertNil(style.editorSurface.scrollBackgroundColor)
        XCTAssertNil(style.editorSurface.collectionBackgroundColor)
    }

    func testComposerStyleUsesBlockInputChromeTokens() throws {
        let style = BlockInputComposerStyle.make(roundedCorners: .bottom, strokedEdges: [.left, .bottom, .right])
        let chrome = try XCTUnwrap(style.editorSurface.chrome)

        XCTAssertEqual(chrome.borderWidth, AppKitChatComposerEditorController.borderWidth)
        XCTAssertEqual(chrome.cornerRadius, AppKitChatComposerEditorController.editorCornerRadius)
        XCTAssertEqual(chrome.roundedCorners, .bottom)
        XCTAssertEqual(chrome.strokedEdges, [.left, .bottom, .right])
        XCTAssertTrue(chrome.clipsContentToShape)
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            try assertDynamicColor(
                chrome.fillColor,
                matches: DynamicLabelExpectation(
                    appearanceName: appearanceName,
                    baseColor: .secondaryLabelColor,
                    opacity: 0.08
                )
            )
            try assertDynamicColor(
                chrome.strokeColor,
                matches: DynamicLabelExpectation(
                    appearanceName: appearanceName,
                    baseColor: .secondaryLabelColor,
                    opacity: 0.10
                )
            )
        }
    }

    func testComposerStyleUsesAlvearyChipTokens() {
        let style = BlockInputComposerStyle.make()

        assertComposerChipStyle(style.fileChip)
        assertComposerChipStyle(style.slashCommandChip)
        assertComposerChipStyle(style.rawSlashCommandChip)
        XCTAssertEqual(style.inlineCode.backgroundColor, AppMarkdownCodeBlockPalette.composerChipFillNSColor)
        XCTAssertEqual(style.inlineCode.foregroundColor, AppMarkdownCodeBlockPalette.composerChipForegroundNSColor)
    }

    func testComposerStyleKeepsHostAttachmentPreviewTokens() throws {
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewStripBackgroundColor, .windowBackgroundColor)
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewThumbnailSize, NSSize(width: 76, height: 76))
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewVerticalPadding, 8)
        XCTAssertEqual(
            BlockInputComposerStyle.imagePreviewHorizontalPadding,
            AppKitChatComposerEditorController.editorHorizontalPadding
        )
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewInterItemSpacing, 12)
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewCornerRadius, AppCornerRadius.standard)
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewBorderWidth, 1)
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewRemoveButtonSize, NSSize(width: 20, height: 20))
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewRemoveButtonBorderWidth, 1)
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewRemoveButtonShadowColor, .black)
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewRemoveButtonShadowOpacity, 0.22)
        XCTAssertEqual(BlockInputComposerStyle.imagePreviewRemoveButtonShadowRadius, 4)
    }

    func testComposerStyleUsesNeutralSelectionTokenDistinctFromChipFill() throws {
        let style = BlockInputComposerStyle.make()

        XCTAssertEqual(style.selectionBackgroundColor, BlockInputComposerStyle.selectionBackgroundColor)
        try assertColor(
            style.selectionBackgroundColor,
            appearanceName: .aqua,
            matches: NSColor(calibratedWhite: 0.68, alpha: 1)
        )
        try assertColor(
            style.selectionBackgroundColor,
            appearanceName: .darkAqua,
            matches: NSColor(calibratedWhite: 0.34, alpha: 1)
        )
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            try assertColorsAreDistinct(
                style.selectionBackgroundColor,
                AppMarkdownCodeBlockPalette.composerChipFillNSColor,
                appearanceName: appearanceName
            )
        }
    }

    func testCompletionPopupStyleUsesAlvearyTokens() throws {
        let style = BlockInputComposerStyle.completionPopupStyle()

        XCTAssertEqual(style.backgroundColor, BlockInputComposerStyle.completionPopupBackgroundColor)
        XCTAssertEqual(style.borderColor, BlockInputComposerStyle.completionPopupBorderColor)
        XCTAssertEqual(
            style.highlightedRowBackgroundColor,
            BlockInputComposerStyle.completionPopupHighlightColor
        )
        XCTAssertEqual(style.cornerRadius, BlockInputComposerStyle.completionPopupCornerRadius)
        XCTAssertEqual(style.borderWidth, BlockInputComposerStyle.completionPopupBorderWidth)
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            try assertColor(
                style.backgroundColor,
                appearanceName: appearanceName,
                matches: expectedPopupBackgroundColor(for: appearance)
            )
            try assertDynamicColor(
                style.borderColor,
                matches: DynamicLabelExpectation(
                    appearanceName: appearanceName,
                    baseColor: .secondaryLabelColor,
                    opacity: 0.18
                )
            )
            try assertDynamicColor(
                style.highlightedRowBackgroundColor,
                matches: DynamicLabelExpectation(
                    appearanceName: appearanceName,
                    baseColor: .labelColor,
                    opacity: 0.1
                )
            )
        }
    }

    func testPopupSurfaceStyleResolvesSharedFill() throws {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let expected = expectedPopupBackgroundColor(for: appearance)

            try assertColor(
                AppPopupSurfaceStyle.backgroundColor(for: appearance),
                appearanceName: appearanceName,
                matches: expected
            )
            try assertColor(
                BlockInputComposerStyle.completionPopupBackgroundColor,
                appearanceName: appearanceName,
                matches: expected
            )
        }
    }

    private func assertComposerChipStyle(
        _ style: BlockInputInlineChipStyle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(style.fillColor, AppMarkdownCodeBlockPalette.composerChipFillNSColor, file: file, line: line)
        XCTAssertNil(style.strokeColor, file: file, line: line)
        XCTAssertEqual(style.foregroundColor, AppMarkdownCodeBlockPalette.composerChipForegroundNSColor, file: file, line: line)
        XCTAssertEqual(style.cornerRadius, BlockInputComposerStyle.chipCornerRadius, file: file, line: line)
    }

    private func expectedPopupBackgroundColor(for appearance: NSAppearance) -> NSColor {
        NSColor.windowBackgroundColor
            .resolved(for: appearance)
            .withAlphaComponent(0.98)
    }

    private func assertColor(
        _ color: NSColor,
        appearanceName: NSAppearance.Name,
        matches expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let appearance = try XCTUnwrap(NSAppearance(named: appearanceName), file: file, line: line)
        let resolved = try XCTUnwrap(color.resolved(for: appearance).usingColorSpace(.genericRGB), file: file, line: line)
        let expected = try XCTUnwrap(expected.usingColorSpace(.genericRGB), file: file, line: line)

        XCTAssertEqual(resolved.redComponent, expected.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolved.greenComponent, expected.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolved.blueComponent, expected.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolved.alphaComponent, expected.alphaComponent, accuracy: 0.001, file: file, line: line)
    }

    private func assertColorsAreDistinct(
        _ first: NSColor,
        _ second: NSColor,
        appearanceName: NSAppearance.Name,
        minimumDistance: CGFloat = 0.12,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let appearance = try XCTUnwrap(NSAppearance(named: appearanceName), file: file, line: line)
        let first = try XCTUnwrap(first.resolved(for: appearance).usingColorSpace(.genericRGB), file: file, line: line)
        let second = try XCTUnwrap(second.resolved(for: appearance).usingColorSpace(.genericRGB), file: file, line: line)
        let distance = abs(first.redComponent - second.redComponent)
            + abs(first.greenComponent - second.greenComponent)
            + abs(first.blueComponent - second.blueComponent)

        XCTAssertGreaterThan(distance, minimumDistance, file: file, line: line)
    }

    private func assertDynamicColor(
        _ color: NSColor?,
        matches expectation: DynamicLabelExpectation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actual = try XCTUnwrap(color, file: file, line: line)
        let appearance = try XCTUnwrap(NSAppearance(named: expectation.appearanceName), file: file, line: line)
        let resolvedBase = expectation.baseColor.resolved(for: appearance)
        let expected = resolvedBase.withAlphaComponent(resolvedBase.alphaComponent * expectation.opacity)

        try assertColor(actual, appearanceName: expectation.appearanceName, matches: expected, file: file, line: line)
    }

}

private struct DynamicLabelExpectation {
    let appearanceName: NSAppearance.Name
    let baseColor: NSColor
    let opacity: CGFloat
}
