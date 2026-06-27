import AppKit
import BlockInputKit

enum BlockInputComposerStyle {
    static let chipCornerRadius: CGFloat = 4
    static let completionPopupCornerRadius: CGFloat = AppCornerRadius.standard
    static let completionPopupBorderWidth: CGFloat = 1
    static let imagePreviewThumbnailSize = NSSize(width: 76, height: 76)
    static let imagePreviewVerticalPadding: CGFloat = 8
    static let imagePreviewHorizontalPadding: CGFloat = AppKitChatComposerEditorController.editorHorizontalPadding
    static let imagePreviewInterItemSpacing: CGFloat = 12
    static let imagePreviewCornerRadius: CGFloat = AppCornerRadius.standard
    static let imagePreviewBorderWidth: CGFloat = 1
    static let imagePreviewRemoveButtonSize = NSSize(width: 20, height: 20)
    static let imagePreviewRemoveButtonBorderWidth: CGFloat = 1
    static let imagePreviewRemoveButtonShadowOpacity: Float = 0.22
    static let imagePreviewRemoveButtonShadowRadius: CGFloat = 4

    static let completionPopupBackgroundColor = AppPopupSurfaceStyle.backgroundNSColor

    static let completionPopupBorderColor = dynamicLabelColor(.secondaryLabelColor, opacity: 0.18)
    static let completionPopupHighlightColor = dynamicLabelColor(.labelColor, opacity: 0.1)
    static let editorFillColor = dynamicLabelColor(.secondaryLabelColor, opacity: 0.08)
    static let editorBorderColor = dynamicLabelColor(.secondaryLabelColor, opacity: 0.10)
    static let imagePreviewStripBackgroundColor = NSColor.windowBackgroundColor
    static let imagePreviewBorderColor = dynamicLabelColor(.separatorColor, opacity: 0.85)
    static let imagePreviewRemoveButtonBackgroundColor = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(calibratedWhite: 0.95, alpha: 0.94)
        default:
            return NSColor(calibratedWhite: 1, alpha: 0.96)
        }
    }
    static let imagePreviewRemoveButtonBorderColor = dynamicLabelColor(.labelColor, opacity: 0.22)
    static let imagePreviewRemoveButtonSymbolColor = NSColor(calibratedWhite: 0.08, alpha: 1)
    static let imagePreviewRemoveButtonShadowColor = NSColor.black
    static let selectionBackgroundColor = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(calibratedWhite: 0.34, alpha: 1)
        default:
            return NSColor(calibratedWhite: 0.68, alpha: 1)
        }
    }

    static func make(
        roundedCorners: BlockInputEditorChromeCorners = .all,
        strokedEdges: BlockInputEditorChromeEdges = .all
    ) -> BlockInputStyle {
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
                    strokedEdges: strokedEdges,
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
