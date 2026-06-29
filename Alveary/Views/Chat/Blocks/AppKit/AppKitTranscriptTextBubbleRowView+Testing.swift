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

    var imageAttachmentTileImageFramesForTesting: [CGRect?] {
        imageAttachmentStripView.tileImageFramesForTesting
    }

    var imageAttachmentTileHitTargetsForTesting: [Bool] {
        imageAttachmentStripView.tileHitTargetsForTesting
    }

    var fileAttachmentChipFramesForTesting: [CGRect] {
        imageAttachmentStripView.fileChipFramesForTesting
    }

    var fileAttachmentChipHitTargetsForTesting: [Bool] {
        imageAttachmentStripView.fileChipHitTargetsForTesting
    }

    var appShotCardFramesForTesting: [CGRect] {
        imageAttachmentStripView.appShotCardFramesForTesting
    }

    var appShotCardImageFramesForTesting: [CGRect?] {
        imageAttachmentStripView.appShotCardImageFramesForTesting
    }

    var appShotCardImageViewFramesForTesting: [CGRect] {
        imageAttachmentStripView.appShotCardImageViewFramesForTesting
    }

    var appShotCardLabelsForTesting: [String?] {
        imageAttachmentStripView.appShotCardAccessibilityLabelsForTesting
    }

    var appShotCardIconsForTesting: [NSImage?] {
        imageAttachmentStripView.appShotCardIconImagesForTesting
    }

    var appShotCardIconFramesForTesting: [CGRect] {
        imageAttachmentStripView.appShotCardIconFramesForTesting
    }

    var appShotCardTitleFramesForTesting: [CGRect] {
        imageAttachmentStripView.appShotCardTitleFramesForTesting
    }

    var appShotCardHitTargetsForTesting: [Bool] {
        imageAttachmentStripView.appShotCardHitTargetsForTesting
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

    @discardableResult
    func openFileAttachmentForTesting(at index: Int = 0) -> Bool {
        imageAttachmentStripView.performOpenForTesting(at: imageAttachmentStripView.tileFramesForTesting.count + index)
    }

    func setAppShotIconResolverForTesting(_ resolver: AppKitAppIconResolving) {
        imageAttachmentStripView.setAppIconResolverForTesting(resolver)
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
