import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
final class BlockInputComposerStyleTests: XCTestCase {
    func testComposerStyleLeavesEditorSurfaceTransparent() {
        let style = BlockInputComposerStyle.make()

        XCTAssertNil(style.editorSurface.editorBackgroundColor)
        XCTAssertNil(style.editorSurface.scrollBackgroundColor)
        XCTAssertNil(style.editorSurface.collectionBackgroundColor)
    }

    func testComposerStyleUsesAlvearyChipTokens() {
        let style = BlockInputComposerStyle.make()

        assertComposerChipStyle(style.fileChip)
        assertComposerChipStyle(style.slashCommandChip)
        assertComposerChipStyle(style.rawSlashCommandChip)
        XCTAssertEqual(style.inlineCode.backgroundColor, AppMarkdownCodeBlockPalette.composerChipFillNSColor)
        XCTAssertEqual(style.inlineCode.foregroundColor, AppMarkdownCodeBlockPalette.composerChipForegroundNSColor)
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
        try assertColor(
            style.backgroundColor,
            appearanceName: .aqua,
            matches: NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
        )
        try assertColor(
            style.backgroundColor,
            appearanceName: .darkAqua,
            matches: NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
        )
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
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
