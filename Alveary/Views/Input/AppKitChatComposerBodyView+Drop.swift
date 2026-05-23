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

        var replacement = droppedMentions.joined(separator: " ")
        if insertionOffsets.lowerBound > 0,
           let previous = text.utf16OffsetScalar(before: insertionOffsets.lowerBound),
           !CharacterSet.whitespacesAndNewlines.contains(previous) {
            replacement = " " + replacement
        }
        replacement += " "
        guard let result = ComposerTransaction.replacingVisibleText(
            in: currentDocument,
            projection: currentProjection,
            range: NSRange(location: insertionOffsets.lowerBound, length: insertionOffsets.count),
            replacement: replacement
        ) else {
            return false
        }
        applyDocumentResult(result, configuration: configuration)
        window?.makeFirstResponder(editorView.textViewForTesting)
        return true
    }
}

private extension String {
    func utf16OffsetScalar(before offset: Int) -> Unicode.Scalar? {
        let source = self as NSString
        guard offset > 0, offset <= source.length else {
            return nil
        }
        return Unicode.Scalar(Int(source.character(at: offset - 1)))
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
