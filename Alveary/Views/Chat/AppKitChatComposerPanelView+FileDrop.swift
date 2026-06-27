@preconcurrency import AppKit

private var appKitComposerFileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] {
    [.urlReadingFileURLsOnly: true]
}

@MainActor
extension AppKitChatComposerPanelView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateFileDropOverlay(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateFileDropOverlay(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        resetCachedFileDropPasteboard()
        setFileDropOverlayActive(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        resetCachedFileDropPasteboard()
        setFileDropOverlayActive(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            resetCachedFileDropPasteboard()
            setFileDropOverlayActive(false)
        }
        guard let fileURLs = readableFileURLs(from: sender),
              !fileURLs.isEmpty,
              isDraggingLocationInsideFileDropTarget(sender) else {
            return false
        }
        Task { @MainActor [weak self] in
            await self?.insertSelectedLocalFileURLs(fileURLs)
        }
        return true
    }

    func layoutFileDropOverlay(configuration: AppKitChatComposerPanelConfiguration) {
        guard configuration.interactionOverlayConfiguration == nil,
              let frame = fileDropTargetFrame() else {
            fileDropOverlayView.frame = .zero
            fileDropOverlayView.isHidden = true
            fileDropOverlayView.alphaValue = 0
            return
        }
        fileDropOverlayView.frame = frame
    }

    func setFileDropOverlayActive(_ isActive: Bool) {
        guard configuration?.interactionOverlayConfiguration == nil else {
            fileDropOverlayView.isHidden = true
            fileDropOverlayView.alphaValue = 0
            return
        }
        let shouldHide = !isActive
        let targetAlpha: CGFloat = isActive ? 1 : 0
        guard fileDropOverlayView.isHidden != shouldHide ||
              abs(fileDropOverlayView.alphaValue - targetAlpha) > 0.001 else {
            return
        }
        fileDropOverlayView.isHidden = !isActive
        fileDropOverlayView.alphaValue = targetAlpha
        fileDropOverlayView.needsDisplay = true
    }

    private func updateFileDropOverlay(for sender: NSDraggingInfo) -> NSDragOperation {
        guard isDraggingLocationInsideFileDropTarget(sender),
              hasReadableFileURLs(in: sender) else {
            setFileDropOverlayActive(false)
            return []
        }
        setFileDropOverlayActive(true)
        return .copy
    }

    private func isDraggingLocationInsideFileDropTarget(_ sender: NSDraggingInfo) -> Bool {
        guard let frame = fileDropTargetFrame() else {
            return false
        }
        return frame.contains(convert(sender.draggingLocation, from: nil))
    }

    private func fileDropTargetFrame() -> NSRect? {
        var frame: NSRect?
        if !attachmentStripView.isHidden, !attachmentStripView.frame.isEmpty {
            frame = attachmentStripView.frame
        }
        if let editorView = editorController.view,
           !editorView.isHidden,
           !editorView.frame.isEmpty {
            frame = frame.map { $0.union(editorView.frame) } ?? editorView.frame
        }
        return frame
    }

    private func readableFileURLs(from sender: NSDraggingInfo) -> [URL]? {
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: appKitComposerFileURLReadingOptions
        ) as? [NSURL]
        return objects?.map { $0 as URL }
    }

    private func hasReadableFileURLs(in sender: NSDraggingInfo) -> Bool {
        let sequenceNumber = sender.draggingSequenceNumber
        if cachedFileDropSequenceNumber == sequenceNumber {
            return cachedFileDropHasReadableFileURLs
        }
        cachedFileDropSequenceNumber = sequenceNumber
        cachedFileDropHasReadableFileURLs = sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: appKitComposerFileURLReadingOptions
        )
        return cachedFileDropHasReadableFileURLs
    }

    private func resetCachedFileDropPasteboard() {
        cachedFileDropSequenceNumber = nil
        cachedFileDropHasReadableFileURLs = false
    }

}
