@preconcurrency import AppKit

#if DEBUG
extension AppKitTranscriptImageAttachmentStripView {
    var tileFramesForTesting: [CGRect] {
        tileViews.prefix(plainAttachments.count).map(\.frame)
    }

    var tileBorderColorsForTesting: [CGColor?] {
        tileViews.prefix(plainAttachments.count).map { $0.layer?.borderColor }
    }

    var tileFillColorsForTesting: [CGColor?] {
        tileViews.prefix(plainAttachments.count).map { $0.layer?.backgroundColor }
    }

    var tileImageFramesForTesting: [CGRect?] {
        tileViews.prefix(plainAttachments.count).map(\.imageFrameForTesting)
    }

    var tileHitTargetsForTesting: [Bool] {
        tileViews.prefix(plainAttachments.count).map { tileView in
            let center = NSPoint(x: tileView.bounds.midX, y: tileView.bounds.midY)
            return tileView.hitTest(center) === tileView
        }
    }

    var appShotCardFramesForTesting: [CGRect] {
        appShotCardViews.prefix(appShotAttachments.count).map(\.frame)
    }

    var appShotCardImageFramesForTesting: [CGRect?] {
        appShotCardViews.prefix(appShotAttachments.count).map(\.imageFrameForTesting)
    }

    var appShotCardImageViewFramesForTesting: [CGRect] {
        appShotCardViews.prefix(appShotAttachments.count).map(\.imageViewFrameForTesting)
    }

    var appShotCardAccessibilityLabelsForTesting: [String?] {
        appShotCardViews.prefix(appShotAttachments.count).map { $0.accessibilityLabel() }
    }

    var appShotCardIconImagesForTesting: [NSImage?] {
        appShotCardViews.prefix(appShotAttachments.count).map(\.iconImageForTesting)
    }

    var appShotCardIconFramesForTesting: [CGRect] {
        appShotCardViews.prefix(appShotAttachments.count).map(\.iconFrameForTesting)
    }

    var appShotCardTitleFramesForTesting: [CGRect] {
        appShotCardViews.prefix(appShotAttachments.count).map(\.titleFrameForTesting)
    }

    var appShotCardHitTargetsForTesting: [Bool] {
        appShotCardViews.prefix(appShotAttachments.count).map { cardView in
            let center = NSPoint(x: cardView.bounds.midX, y: cardView.bounds.midY)
            return cardView.hitTest(center) === cardView
        }
    }

    func setAppIconResolverForTesting(_ resolver: AppKitTranscriptAppIconResolving) {
        appIconResolver = resolver
    }

    @discardableResult
    func performOpenForTesting(at index: Int = 0) -> Bool {
        let visibleTileCount = plainAttachments.count
        if index < visibleTileCount {
            guard tileViews.indices.contains(index) else {
                return false
            }
            return tileViews[index].accessibilityPerformPress()
        }
        let appShotIndex = index - visibleTileCount
        guard appShotCardViews.indices.contains(appShotIndex) else {
            return false
        }
        return appShotCardViews[appShotIndex].accessibilityPerformPress()
    }
}

extension AppKitTranscriptImageAttachmentTileView {
    var imageFrameForTesting: CGRect? {
        imageView.aspectFillImageFrameForTesting
    }
}

extension AppKitTranscriptAspectFillImageView {
    var aspectFillImageFrameForTesting: CGRect? {
        aspectFillImageFrame
    }
}
#endif
