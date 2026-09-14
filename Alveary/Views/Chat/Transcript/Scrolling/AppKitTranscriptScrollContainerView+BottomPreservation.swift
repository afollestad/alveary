import AppKit

/// Coalesces frame-blocked measurements while retaining the current reader anchor and following intent at flush time.
@MainActor
extension AppKitTranscriptScrollContainerView {
    func deferHeightInvalidationUntilStable(
        rowIDs: Set<String>?,
        preserveBottomIfFollowing: Bool,
        forceBottomIfPreserving: Bool,
        animatesLayoutChanges: Bool
    ) -> Bool {
        if deferForcedBottomIfMeasuring(preserveBottomIfFollowing && forceBottomIfPreserving) {
            return true
        }
        guard transcriptDocumentView.isApplyingFrameUpdates || transcriptDocumentView.hasActiveFrameAnimation ||
            pendingHeightInvalidation != nil else { return false }
        let invalidation = AppKitTranscriptHeightInvalidation(
            rowIDs: rowIDs,
            preserveBottomIfFollowing: preserveBottomIfFollowing,
            forceBottomIfPreserving: preserveBottomIfFollowing && forceBottomIfPreserving,
            animatesLayoutChanges: animatesLayoutChanges
        )
        if pendingHeightInvalidation == nil {
            pendingHeightInvalidation = invalidation
        } else {
            pendingHeightInvalidation?.merge(invalidation)
        }
        scheduleDeferredHeightInvalidationFlush()
        return true
    }

    private func scheduleDeferredHeightInvalidationFlush() {
        guard !hasScheduledHeightInvalidationFlush else { return }
        hasScheduledHeightInvalidationFlush = true
        if transcriptDocumentView.hasActiveFrameAnimation {
            transcriptDocumentView.runAfterActiveFrameAnimation { [weak self] in
                self?.flushDeferredHeightInvalidation()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.flushDeferredHeightInvalidation()
            }
        }
    }

    private func flushDeferredHeightInvalidation() {
        hasScheduledHeightInvalidationFlush = false
        guard let pending = pendingHeightInvalidation else { return }
        if transcriptDocumentView.hasActiveFrameAnimation || transcriptDocumentView.isApplyingFrameUpdates {
            scheduleDeferredHeightInvalidationFlush()
            return
        }
        pendingHeightInvalidation = nil
        // A collapse's clip animation can complete after its row animation; its old target must not replace this batch's size.
        activeScrollAnimationToken = nil
        rowHeightsInvalidated(
            rowIDs: pending.rowIDs,
            preserveBottomIfFollowing: pending.preserveBottomIfFollowing,
            forceBottomIfPreserving: pending.forceBottomIfPreserving && preservesBottomOnResize,
            animatesLayoutChanges: pending.animatesLayoutChanges
        )
    }

    func deferForcedBottomIfMeasuring(_ shouldRestoreBottom: Bool) -> Bool {
        guard transcriptDocumentView.isMeasuringRows else {
            return false
        }
        if shouldRestoreBottom {
            shouldForceBottomAfterCurrentMeasurement = true
        }
        return true
    }

    @discardableResult
    func restoreForcedBottomAfterMeasurementIfNeeded() -> Bool {
        guard shouldForceBottomAfterCurrentMeasurement else {
            return false
        }
        shouldForceBottomAfterCurrentMeasurement = false
        scrollToBottom()
        return true
    }
}

struct AppKitTranscriptHeightInvalidation {
    /// An unidentified change invalidates every row, even when other requests identify individual rows.
    var rowIDs: Set<String>?
    var preserveBottomIfFollowing: Bool
    var forceBottomIfPreserving: Bool
    var animatesLayoutChanges: Bool

    mutating func merge(_ other: Self) {
        if rowIDs != nil, let additionalIDs = other.rowIDs {
            rowIDs?.formUnion(additionalIDs)
        } else {
            rowIDs = nil
        }
        preserveBottomIfFollowing = preserveBottomIfFollowing || other.preserveBottomIfFollowing
        forceBottomIfPreserving = forceBottomIfPreserving || other.forceBottomIfPreserving
        // Streaming's nonanimated intent also applies when an expandable row joins the same measurement batch.
        animatesLayoutChanges = animatesLayoutChanges && other.animatesLayoutChanges
    }
}
