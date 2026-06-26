@preconcurrency import AppKit

#if DEBUG
extension AppKitTranscriptTextBubbleRowView {
    var bubbleFrameForTesting: CGRect {
        bubbleView.frame
    }

    var isBubbleHiddenForTesting: Bool {
        bubbleView.isHidden
    }

    var imageAttachmentStripFrameForTesting: CGRect {
        imageAttachmentStripView.frame
    }

    var imageAttachmentTileFramesForTesting: [CGRect] {
        imageAttachmentStripView.tileFramesForTesting
    }

    var attachmentTileBorderColorsForTesting: [CGColor?] {
        imageAttachmentStripView.tileBorderColorsForTesting
    }

    var attachmentTileFillColorsForTesting: [CGColor?] {
        imageAttachmentStripView.tileFillColorsForTesting
    }

    @discardableResult
    func openImageAttachmentForTesting(at index: Int = 0) -> Bool {
        imageAttachmentStripView.performOpenForTesting(at: index)
    }

    var expansionButtonFrameForTesting: CGRect {
        expansionButton.frame
    }

    var markdownClipFrameForTesting: CGRect {
        markdownClipView.frame
    }

    var markdownFrameForTesting: CGRect? {
        markdownView?.frame
    }

    var isMarkdownHydratedForTesting: Bool {
        isTranscriptViewportHydrated
    }

    var markdownIntrinsicHeightForTesting: CGFloat? {
        markdownView?.intrinsicContentSize.height
    }

    var isExpansionButtonHiddenForTesting: Bool {
        expansionButton.isHidden
    }

    var hasCollapsedFadeMaskForTesting: Bool {
        markdownClipView.layer?.mask === collapsedFadeMask
    }

    var collapsedFadeMaskDirectionForTesting: (start: CGPoint, end: CGPoint) {
        (collapsedFadeMask.startPoint, collapsedFadeMask.endPoint)
    }

    var bubbleBackgroundColorForTesting: CGColor? {
        bubbleView.layer?.backgroundColor
    }
}
#endif
