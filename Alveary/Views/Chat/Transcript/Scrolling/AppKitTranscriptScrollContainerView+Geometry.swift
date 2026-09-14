import AppKit

extension AppKitTranscriptScrollContainerView {
    /// Keeps intermediate clip-view notifications out of following-state decisions while frames and anchors disagree.
    func beginLayoutTransaction() {
        layoutTransactionDepth += 1
    }

    func endLayoutTransaction() {
        layoutTransactionDepth -= 1
        guard layoutTransactionDepth == 0 else { return }
        hydrateViewportRows()
        publishScrollMetrics()
        notifyStableLayoutIfNeeded()
    }

    func layoutTranscriptContainer() {
        loadingIndicator.frame = CGRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16)
        guard !transcriptDocumentView.hasActiveFrameAnimation else {
            if scrollView.frame.size != bounds.size {
                queueLayoutAfterFrameAnimation()
            }
            return
        }
        guard layoutTransactionDepth == 0 else {
            scrollView.frame = bounds
            transcriptDocumentView.layoutRows(width: bounds.width)
            return
        }

        beginLayoutTransaction()
        defer { endLayoutTransaction() }
        // Capture against the old viewport and row frames; resizing the clip view first can already clamp its offset.
        let visibleAnchor = captureVisibleAnchor()
        let shouldRestoreBottom = preservesBottomOnResize && isAtBottom
        let changesGeometry = scrollView.frame.size != bounds.size
        scrollView.frame = bounds
        transcriptDocumentView.layoutRows(width: bounds.width)
        guard !restoreForcedBottomAfterMeasurementIfNeeded(), changesGeometry else { return }
        restoreScrollPosition(shouldRestoreBottom: shouldRestoreBottom, visibleAnchor: visibleAnchor)
    }

    /// A resize or replacement during expansion must get a fresh pass after the captured animation target completes.
    func queueLayoutAfterFrameAnimation() {
        guard !hasQueuedAnimationLayout else { return }
        hasQueuedAnimationLayout = true
        transcriptDocumentView.runAfterActiveFrameAnimation { [weak self] in
            guard let self else { return }
            self.hasQueuedAnimationLayout = false
            guard self.pendingConfiguration != nil || self.scrollView.frame.size != self.bounds.size else {
                self.notifyStableLayoutIfNeeded()
                return
            }
            // The separate clip-view animation may finish later; its old size must not overwrite this newer layout.
            self.activeScrollAnimationToken = nil
            if let pending = self.pendingConfiguration {
                self.pendingConfiguration = nil
                self.configure(
                    rows: pending.rows,
                    dirtyRowIDs: pending.dirtyRowIDs,
                    rowIDAliases: pending.rowIDAliases,
                    preserveBottomIfFollowing: self.preservesBottomOnResize
                )
            } else {
                self.needsLayout = true
                self.layoutSubtreeIfNeeded()
            }
        }
    }

    func notifyStableLayoutIfNeeded() {
        guard bounds.width > transcriptScrollLeadingInset + transcriptScrollTrailingInset,
              !transcriptDocumentView.hasActiveFrameAnimation,
              !transcriptDocumentView.isMeasuringRows,
              !transcriptDocumentView.isApplyingFrameUpdates,
              activeScrollAnimationToken == nil,
              pendingHeightInvalidation == nil,
              !hasQueuedAnimationLayout else { return }
        onStableLayout?()
    }
}

@MainActor
struct AppKitTranscriptPendingConfiguration {
    let rows: [AppKitTranscriptLayoutRow]
    let dirtyRowIDs: Set<String>
    let rowIDAliases: [String: String]
}
