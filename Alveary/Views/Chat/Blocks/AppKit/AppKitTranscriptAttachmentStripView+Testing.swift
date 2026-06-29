@preconcurrency import AppKit

#if DEBUG
extension AppKitTranscriptAttachmentStripView {
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

    var fileChipFramesForTesting: [CGRect] {
        fileChipViews.prefix(fileAttachments.count).map(\.frame)
    }

    var fileChipHitTargetsForTesting: [Bool] {
        fileChipViews.prefix(fileAttachments.count).map { chipView in
            let center = NSPoint(x: chipView.bounds.midX, y: chipView.bounds.midY)
            return chipView.hitTest(center) === chipView
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

    func setAppIconResolverForTesting(_ resolver: AppKitAppIconResolving) {
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
        let visibleFileCount = fileAttachments.count
        let fileIndex = index - visibleTileCount
        if fileIndex < visibleFileCount {
            guard fileChipViews.indices.contains(fileIndex) else {
                return false
            }
            return fileChipViews[fileIndex].accessibilityPerformPress()
        }
        let appShotIndex = index - visibleTileCount - visibleFileCount
        guard appShotCardViews.indices.contains(appShotIndex) else {
            return false
        }
        return appShotCardViews[appShotIndex].accessibilityPerformPress()
    }
}

extension AppKitImageAttachmentTileView {
    var imageFrameForTesting: CGRect? {
        imageView.aspectFillImageFrameForTesting
    }
}
#endif
