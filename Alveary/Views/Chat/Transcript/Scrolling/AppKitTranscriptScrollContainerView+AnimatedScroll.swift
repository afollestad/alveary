import AppKit
import QuartzCore

@MainActor
extension AppKitTranscriptScrollContainerView {
    func finishHeightInvalidationScrollUpdate(
        restoresPosition: Bool,
        shouldRestoreBottom: Bool,
        visibleAnchor: AppKitTranscriptVisibleAnchor?
    ) {
        if restoresPosition {
            restoreScrollPosition(shouldRestoreBottom: shouldRestoreBottom, visibleAnchor: visibleAnchor)
        }
        hydrateViewportRows()
        publishScrollMetrics()
    }

    func targetScrollY(
        shouldRestoreBottom: Bool,
        visibleAnchor: AppKitTranscriptVisibleAnchor?,
        targetDocumentHeight: CGFloat
    ) -> CGFloat {
        let maxY = max(0, targetDocumentHeight - scrollView.contentView.bounds.height)
        if shouldRestoreBottom {
            return maxY
        }
        guard let visibleAnchor,
              visibleAnchor.generation == paginationGeneration,
              let rowFrame = rowFrame(for: visibleAnchor.rowID)
        else {
            return min(max(0, scrollOffsetY), maxY)
        }
        return min(max(0, rowFrame.minY + visibleAnchor.offsetWithinRow), maxY)
    }

    func finishAnimatedHeightInvalidationIfNeeded(
        animatesLayoutChanges: Bool,
        documentHeightBeforeLayout: CGFloat,
        shouldRestoreBottom: Bool,
        visibleAnchor: AppKitTranscriptVisibleAnchor?
    ) -> Bool {
        guard animatesLayoutChanges,
              transcriptDocumentView.hasActiveFrameAnimation,
              let targetDocumentSize = transcriptDocumentView.activeFrameAnimationTargetDocumentSize else {
            return false
        }
        guard targetDocumentSize.height < documentHeightBeforeLayout - 0.5 else {
            finishHeightInvalidationScrollUpdate(
                restoresPosition: !shouldRestoreBottom,
                shouldRestoreBottom: false,
                visibleAnchor: visibleAnchor
            )
            return true
        }

        let targetScrollY = targetScrollY(
            shouldRestoreBottom: shouldRestoreBottom,
            visibleAnchor: visibleAnchor,
            targetDocumentHeight: targetDocumentSize.height
        )
        animateDocumentHeightAndScroll(to: targetDocumentSize, targetScrollY: targetScrollY)
        transcriptDocumentView.runAfterActiveFrameAnimation { [weak self] in
            self?.finishHeightInvalidationScrollUpdate(
                restoresPosition: false,
                shouldRestoreBottom: shouldRestoreBottom,
                visibleAnchor: visibleAnchor
            )
        }
        return true
    }

    func animateDocumentHeightAndScroll(to targetDocumentSize: CGSize, targetScrollY: CGFloat) {
        let token = UUID()
        activeScrollAnimationToken = token
        let clampedTargetScrollY = min(max(0, targetScrollY), max(0, targetDocumentSize.height - scrollView.contentView.bounds.height))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = appExpansionAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            transcriptDocumentView.animator().setFrameSize(targetDocumentSize)
            scrollView.contentView.animator().setBoundsOrigin(CGPoint(x: 0, y: clampedTargetScrollY))
        } completionHandler: {
            Task { @MainActor in
                guard self.activeScrollAnimationToken == token else {
                    return
                }
                self.transcriptDocumentView.setDocumentSize(targetDocumentSize)
                self.scrollContentView(toY: clampedTargetScrollY)
                self.activeScrollAnimationToken = nil
                self.publishScrollMetrics()
            }
        }
    }
}
