@preconcurrency import AppKit

#if DEBUG
extension AppKitTranscriptTextBubbleRowView {
    var bubbleFrameForTesting: CGRect {
        bubbleView.frame
    }

    var expansionButtonFrameForTesting: CGRect {
        expansionButton.frame
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
