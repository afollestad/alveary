import AppKit

extension AppKitTranscriptScrollContainerView {
    /// Caches candidate discovery per row. Walking every descendant on each scroll frame makes
    /// complex rows such as review proposals hitch even when they contain no prewarmable work.
    func refreshViewportPrewarmRegistry(
        rows: [AppKitTranscriptLayoutRow],
        dirtyRowIDs: Set<String>
    ) {
        let liveRowIDs = Set(rows.map(\.id))
        viewportPrewarmRegistry = viewportPrewarmRegistry.filter { liveRowIDs.contains($0.key) }
        viewportPrewarmRowOrder = rows.map(\.id)
        for row in rows {
            guard dirtyRowIDs.contains(row.id) || viewportPrewarmRegistry[row.id]?.rootView !== row.view else {
                continue
            }
            viewportPrewarmRegistry[row.id] = AppKitTranscriptPrewarmRegistryEntry(
                rootView: row.view,
                candidates: prewarmCandidates(in: row.view)
            )
        }
    }

    /// A row can mount nested tool rows before its SwiftUI expansion-state echo reconfigures the
    /// transcript, so height invalidation also refreshes the affected inventories.
    func refreshViewportPrewarmRegistry(rowIDs: Set<String>?) {
        let ids = rowIDs ?? Set(viewportPrewarmRowOrder)
        for id in ids {
            guard let entry = viewportPrewarmRegistry[id], let rootView = entry.rootView else {
                viewportPrewarmRegistry[id] = nil
                continue
            }
            viewportPrewarmRegistry[id] = AppKitTranscriptPrewarmRegistryEntry(
                rootView: rootView,
                candidates: prewarmCandidates(in: rootView)
            )
        }
    }

    /// Replaces queued candidates on every viewport change so scrolled-away or removed rows stop consuming UI work.
    /// Only rows the document lays out inside `rect` are considered, so a scroll frame costs the
    /// viewport, not the transcript.
    func updateViewportPrewarming(in rect: CGRect) {
        // Off-window test hosts can prewarm; a previously mounted conversation must stay cancelled after switching away.
        guard !hasMountedWindow || window != nil else {
            cancelViewportPrewarming()
            return
        }
        var candidates: [AppKitTranscriptPrewarmCandidate] = []
        for rowFrame in transcriptDocumentView.rowFrames(intersecting: rect) {
            guard let entry = viewportPrewarmRegistry[rowFrame.id],
                  !entry.candidates.isEmpty,
                  let rootView = entry.rootView,
                  rootView === rowFrame.view,
                  !rootView.isHiddenOrHasHiddenAncestor
            else {
                continue
            }
            for candidate in entry.candidates {
                guard let view = candidate.view,
                      let prewarmable = view as? AppKitTranscriptViewportPrewarmable,
                      prewarmable.needsTranscriptViewportPrewarm,
                      !view.isHiddenOrHasHiddenAncestor,
                      view.isDescendant(of: transcriptDocumentView),
                      view === rootView || view.convert(view.bounds, to: transcriptDocumentView).intersects(rect)
                else {
                    continue
                }
                candidates.append(candidate)
            }
        }
        viewportPrewarmCandidates = candidates
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
                  let prewarmable = view as? AppKitTranscriptViewportPrewarmable,
                  prewarmable.needsTranscriptViewportPrewarm,
                  !view.isHiddenOrHasHiddenAncestor,
                  view.isDescendant(of: transcriptDocumentView),
                  view.convert(view.bounds, to: transcriptDocumentView).intersects(marginRect)
            else { continue }
            prewarmable.prewarmForTranscriptViewport()
            return true
        }
        viewportPrewarmTask = nil
        return false
    }

    private func prewarmCandidates(in view: NSView) -> [AppKitTranscriptPrewarmCandidate] {
        let ownCandidate = view is any AppKitTranscriptViewportPrewarmable
            ? [AppKitTranscriptPrewarmCandidate(view: view)]
            : []
        return ownCandidate + view.subviews.flatMap(prewarmCandidates(in:))
    }
}

@MainActor
struct AppKitTranscriptPrewarmRegistryEntry {
    weak var rootView: NSView?
    let candidates: [AppKitTranscriptPrewarmCandidate]
}

@MainActor
struct AppKitTranscriptPrewarmCandidate {
    weak var view: NSView?
}
