import AppKit

extension AppKitTranscriptScrollContainerView {
    /// Replaces queued candidates on every viewport change so scrolled-away or removed rows stop consuming UI work.
    func updateViewportPrewarming(in rect: CGRect) {
        // Off-window test hosts can prewarm; a previously mounted conversation must stay cancelled after switching away.
        guard !hasMountedWindow || window != nil else {
            cancelViewportPrewarming()
            return
        }
        viewportPrewarmCandidates = prewarmCandidates(in: transcriptDocumentView, intersecting: rect)
        guard !viewportPrewarmCandidates.isEmpty else {
            cancelViewportPrewarming()
            return
        }
        guard viewportPrewarmTask == nil else { return }
        viewportPrewarmGeneration += 1
        let generation = viewportPrewarmGeneration
        viewportPrewarmTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await Task.yield()
                guard self?.prewarmNextViewportRow(generation: generation) == true else { return }
            }
        }
    }

    func cancelViewportPrewarming() {
        viewportPrewarmGeneration += 1
        viewportPrewarmTask?.cancel()
        viewportPrewarmTask = nil
        viewportPrewarmCandidates = []
    }

    /// At most one detail subtree is constructed per actor turn, even when a group reveals many tools together.
    private func prewarmNextViewportRow(generation: Int) -> Bool {
        guard generation == viewportPrewarmGeneration else { return false }
        let visibleRect = scrollView.contentView.bounds
        let marginRect = visibleRect.insetBy(dx: 0, dy: -visibleRect.height * 1.5)
        while !viewportPrewarmCandidates.isEmpty {
            let candidate = viewportPrewarmCandidates.removeFirst()
            guard let view = candidate.view,
                  view.isDescendant(of: transcriptDocumentView),
                  view.convert(view.bounds, to: transcriptDocumentView).intersects(marginRect),
                  let prewarmable = view as? AppKitTranscriptViewportPrewarmable,
                  prewarmable.needsTranscriptViewportPrewarm else { continue }
            prewarmable.prewarmForTranscriptViewport()
            return true
        }
        viewportPrewarmTask = nil
        return false
    }

    private func prewarmCandidates(in view: NSView, intersecting rect: CGRect) -> [AppKitTranscriptPrewarmCandidate] {
        view.subviews.flatMap { child -> [AppKitTranscriptPrewarmCandidate] in
            guard !child.isHidden,
                  child.convert(child.bounds, to: transcriptDocumentView).intersects(rect) else { return [] }
            if let prewarmable = child as? AppKitTranscriptViewportPrewarmable,
               prewarmable.needsTranscriptViewportPrewarm {
                return [AppKitTranscriptPrewarmCandidate(view: child)]
            }
            return prewarmCandidates(in: child, intersecting: rect)
        }
    }
}

@MainActor
struct AppKitTranscriptPrewarmCandidate {
    weak var view: NSView?
}
