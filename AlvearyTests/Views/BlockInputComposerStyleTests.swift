import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
final class BlockInputComposerStyleTests: XCTestCase {
    func testComposerStyleUsesAlvearyEditorSurfaceFill() throws {
        let style = BlockInputComposerStyle.make()

        try assertComposerSurfaceColor(style.editorSurface.editorBackgroundColor)
        try assertComposerSurfaceColor(style.editorSurface.scrollBackgroundColor)
        try assertComposerSurfaceColor(style.editorSurface.collectionBackgroundColor)
    }

    func testComposerStyleUsesAlvearyChipTokens() {
        let style = BlockInputComposerStyle.make()

        assertComposerChipStyle(style.fileChip)
        assertComposerChipStyle(style.slashCommandChip)
        assertComposerChipStyle(style.rawSlashCommandChip)
        XCTAssertEqual(style.inlineCode.backgroundColor, AppMarkdownCodeBlockPalette.composerChipFillNSColor)
        XCTAssertEqual(style.inlineCode.foregroundColor, AppMarkdownCodeBlockPalette.composerChipForegroundNSColor)
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

    private func assertComposerSurfaceColor(
        _ color: NSColor?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actual = try XCTUnwrap(color, file: file, line: line)
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua), file: file, line: line)
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua), file: file, line: line)
        assertComposerSurfaceColor(actual, appearance: lightAppearance, file: file, line: line)
        assertComposerSurfaceColor(actual, appearance: darkAppearance, file: file, line: line)
    }

    private func assertComposerSurfaceColor(
        _ actual: NSColor,
        appearance: NSAppearance,
        file: StaticString,
        line: UInt
    ) {
        let resolvedActual = actual.resolved(for: appearance)
        let resolvedBase = NSColor.secondaryLabelColor.resolved(for: appearance)
        let resolvedExpected = resolvedBase.withAlphaComponent(
            resolvedBase.alphaComponent * BlockInputComposerStyle.editorSurfaceOpacity
        )
        XCTAssertEqual(resolvedActual.redComponent, resolvedExpected.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolvedActual.greenComponent, resolvedExpected.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolvedActual.blueComponent, resolvedExpected.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(resolvedActual.alphaComponent, resolvedExpected.alphaComponent, accuracy: 0.001, file: file, line: line)
    }
}
