import AppKit
import BlockInputKit

enum BlockInputComposerStyle {
    static let chipCornerRadius: CGFloat = 4
    static let completionPopupCornerRadius: CGFloat = 18
    static let completionPopupBorderWidth: CGFloat = 1

    static let completionPopupBackgroundColor = AppPopupSurfaceStyle.backgroundNSColor

    static let completionPopupBorderColor = dynamicLabelColor(.secondaryLabelColor, opacity: 0.18)
    static let completionPopupHighlightColor = dynamicLabelColor(.labelColor, opacity: 0.1)
    static let editorFillColor = dynamicLabelColor(.secondaryLabelColor, opacity: 0.08)
    static let editorBorderColor = dynamicLabelColor(.secondaryLabelColor, opacity: 0.18)
    static let selectionBackgroundColor = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(calibratedWhite: 0.34, alpha: 1)
        default:
            return NSColor(calibratedWhite: 0.68, alpha: 1)
        }
    }

    static func make(roundedCorners: BlockInputEditorChromeCorners = .all) -> BlockInputStyle {
        return BlockInputStyle(
            selectionBackgroundColor: selectionBackgroundColor,
            inlineCode: BlockInputInlineCodeStyle(
                foregroundColor: AppMarkdownCodeBlockPalette.composerChipForegroundNSColor,
                backgroundColor: AppMarkdownCodeBlockPalette.composerChipFillNSColor
            ),
            editorSurface: BlockInputEditorSurfaceStyle(
                editorBackgroundColor: nil,
                scrollBackgroundColor: nil,
                collectionBackgroundColor: nil,
                chrome: BlockInputEditorChromeStyle(
                    fillColor: editorFillColor,
                    strokeColor: editorBorderColor,
                    borderWidth: AppKitChatComposerEditorController.borderWidth,
                    cornerRadius: AppKitChatComposerEditorController.editorCornerRadius,
                    roundedCorners: roundedCorners,
                    clipsContentToShape: true
                )
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
