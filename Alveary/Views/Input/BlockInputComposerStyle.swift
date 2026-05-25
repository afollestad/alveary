import AppKit
import BlockInputKit

enum BlockInputComposerStyle {
    static let chipCornerRadius: CGFloat = 4
    static let editorSurfaceOpacity: CGFloat = 0.08

    static func make() -> BlockInputStyle {
        let editorSurfaceColor = editorSurfaceColor()
        return BlockInputStyle(
            inlineCode: BlockInputInlineCodeStyle(
                foregroundColor: AppMarkdownCodeBlockPalette.composerChipForegroundNSColor,
                backgroundColor: AppMarkdownCodeBlockPalette.composerChipFillNSColor
            ),
            editorSurface: BlockInputEditorSurfaceStyle(
                editorBackgroundColor: editorSurfaceColor,
                scrollBackgroundColor: editorSurfaceColor,
                collectionBackgroundColor: editorSurfaceColor
            ),
            fileChip: chipStyle(),
            slashCommandChip: chipStyle(),
            rawSlashCommandChip: chipStyle()
        )
    }

    static func editorSurfaceColor() -> NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            let resolved = NSColor.secondaryLabelColor.resolved(for: appearance)
            return resolved.withAlphaComponent(resolved.alphaComponent * editorSurfaceOpacity)
        })
    }

    private static func chipStyle() -> BlockInputInlineChipStyle {
        BlockInputInlineChipStyle(
            fillColor: AppMarkdownCodeBlockPalette.composerChipFillNSColor,
            strokeColor: nil,
            foregroundColor: AppMarkdownCodeBlockPalette.composerChipForegroundNSColor,
            cornerRadius: chipCornerRadius
        )
    }
}
