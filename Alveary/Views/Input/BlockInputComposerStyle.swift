import AppKit
import BlockInputKit

enum BlockInputComposerStyle {
    static let chipCornerRadius: CGFloat = 4
    static let completionPopupCornerRadius: CGFloat = 18
    static let completionPopupBorderWidth: CGFloat = 1

    static let completionPopupBackgroundColor = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
        default:
            return NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
        }
    }

    static let completionPopupBorderColor = dynamicLabelColor(.secondaryLabelColor, opacity: 0.18)
    static let completionPopupHighlightColor = dynamicLabelColor(.labelColor, opacity: 0.1)

    static func make() -> BlockInputStyle {
        return BlockInputStyle(
            inlineCode: BlockInputInlineCodeStyle(
                foregroundColor: AppMarkdownCodeBlockPalette.composerChipForegroundNSColor,
                backgroundColor: AppMarkdownCodeBlockPalette.composerChipFillNSColor
            ),
            editorSurface: BlockInputEditorSurfaceStyle(
                editorBackgroundColor: nil,
                scrollBackgroundColor: nil,
                collectionBackgroundColor: nil
            ),
            fileChip: chipStyle(),
            slashCommandChip: chipStyle(),
            rawSlashCommandChip: chipStyle()
        )
    }

    static func completionPopupStyle() -> BlockInputCompletionPopupStyle {
        BlockInputCompletionPopupStyle(
            backgroundColor: completionPopupBackgroundColor,
            borderColor: completionPopupBorderColor,
            highlightedRowBackgroundColor: completionPopupHighlightColor,
            cornerRadius: completionPopupCornerRadius,
            borderWidth: completionPopupBorderWidth
        )
    }

    private static func chipStyle() -> BlockInputInlineChipStyle {
        BlockInputInlineChipStyle(
            fillColor: AppMarkdownCodeBlockPalette.composerChipFillNSColor,
            strokeColor: nil,
            foregroundColor: AppMarkdownCodeBlockPalette.composerChipForegroundNSColor,
            cornerRadius: chipCornerRadius
        )
    }

    private static func dynamicLabelColor(_ color: NSColor, opacity: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let resolved = color.resolved(for: appearance)
            return resolved.withAlphaComponent(resolved.alphaComponent * opacity)
        }
    }
}
