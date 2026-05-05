@preconcurrency import AppKit

extension AppKitChatComposerBodyView {
    func hasFileURLs(in pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    func handleDroppedFiles(
        _ items: [URL],
        configuration: AppKitChatComposerBodyConfiguration
    ) -> Bool {
        let droppedMentions = items
            .filter(\.isFileURL)
            .map {
                let normalized = ChatInputFieldTextSupport.normalizedMentionPath(
                    for: $0.path,
                    relativeTo: configuration.workingDirectory
                )
                return "@\(CanonicalPath.encodeStoredMentionPath(normalized))"
            }
        guard !droppedMentions.isEmpty else {
            return false
        }
        dismissAutocomplete()

        let text = currentText
        let insertionOffsets: Range<Int>
        if let selection = ChatInputFieldTextSupport.editableSelectionOffsets(text: text, selectedRange: selectedRange) {
            insertionOffsets = selection
        } else {
            let end = (text as NSString).length
            insertionOffsets = end..<end
        }

        let (newText, insertionOffset) = ChatInputFieldTextSupport.replacingText(
            in: text,
            offsets: insertionOffsets,
            with: droppedMentions.joined(separator: " "),
            appendTrailingSpace: true,
            ensureLeadingSpace: insertionOffsets.lowerBound > 0
        )
        selectedRange = NSRange(location: insertionOffset, length: 0)
        currentText = newText
        configuration.onTextChange(newText)
        refreshEditorConfiguration()
        window?.makeFirstResponder(editorView.textViewForTesting)
        return true
    }
}

extension NSBezierPath {
    /// Builds the editor outline used by the native composer body.
    ///
    /// Queued messages sit directly above the editor as part of one visual
    /// control, so the editor's top corners are squared only in that state.
    static func appKitComposerEditorPath(
        in rect: NSRect,
        radius: CGFloat,
        squaresTopCorners: Bool
    ) -> NSBezierPath {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        guard squaresTopCorners else {
            return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        }

        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - radius))
        path.curve(
            to: NSPoint(x: rect.maxX - radius, y: rect.maxY),
            controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY - radius * 0.45),
            controlPoint2: NSPoint(x: rect.maxX - radius * 0.45, y: rect.maxY)
        )
        path.line(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
        path.curve(
            to: NSPoint(x: rect.minX, y: rect.maxY - radius),
            controlPoint1: NSPoint(x: rect.minX + radius * 0.45, y: rect.maxY),
            controlPoint2: NSPoint(x: rect.minX, y: rect.maxY - radius * 0.45)
        )
        path.close()
        return path
    }
}
