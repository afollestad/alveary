import AppKit

@MainActor
extension AppKitTranscriptScrollContainerView {
    func deferHeightInvalidationUntilStable(
        rowID: String?,
        preserveBottomIfFollowing: Bool,
        forceBottomIfPreserving: Bool,
        animatesLayoutChanges: Bool,
        shouldRestoreBottom: Bool
    ) -> Bool {
        if deferForcedBottomIfMeasuring(shouldRestoreBottom && forceBottomIfPreserving) {
            return true
        }
        if transcriptDocumentView.isApplyingFrameUpdates {
            DispatchQueue.main.async { [weak self] in
                self?.rowHeightInvalidated(
                    rowID: rowID,
                    preserveBottomIfFollowing: preserveBottomIfFollowing,
                    forceBottomIfPreserving: forceBottomIfPreserving,
                    animatesLayoutChanges: animatesLayoutChanges
                )
            }
            return true
        }
        if transcriptDocumentView.hasActiveFrameAnimation {
            transcriptDocumentView.runAfterActiveFrameAnimation { [weak self] in
                self?.rowHeightInvalidated(
                    rowID: rowID,
                    preserveBottomIfFollowing: preserveBottomIfFollowing,
                    forceBottomIfPreserving: forceBottomIfPreserving,
                    animatesLayoutChanges: animatesLayoutChanges
                )
            }
            return true
        }
        return false
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
