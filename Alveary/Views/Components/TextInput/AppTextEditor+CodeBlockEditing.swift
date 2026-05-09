@preconcurrency import AppKit

/// Editing rules for composer-style fenced code blocks.
///
/// The editor keeps the raw markdown fences in `string`, but the user edits the
/// visual code block body. Selection normalization keeps clicks and arrow exits
/// from landing inside hidden fence delimiters.
extension AppKitTextView {
    func normalizedCodeBlockInsertionRange(_ range: NSRange) -> NSRange {
        guard range.length == 0,
              range.location != NSNotFound else {
            return range
        }

        let textLength = (string as NSString).length
        let location = min(max(range.location, 0), textLength)
        for blockRange in AppMarkdownCodeBlockParser.blockCodeRanges(in: string) {
            guard let openingDelimiterRange = blockRange.delimiterRanges.first else {
                continue
            }

            if location > openingDelimiterRange.location,
               location < NSMaxRange(openingDelimiterRange) {
                return NSRange(location: blockRange.contentRange.location, length: 0)
            }

            guard let closingDelimiterRange = blockRange.delimiterRanges.dropFirst().first else {
                continue
            }

            if location > closingDelimiterRange.location,
               location < NSMaxRange(closingDelimiterRange) {
                return NSRange(location: NSMaxRange(blockRange.contentRange), length: 0)
            }
        }

        return range
    }

    func openingFenceNormalizedInsertText(_ insertText: Any, at location: Int) -> (value: Any, selectionLocation: Int?) {
        guard let insertedString = codeBlockInsertedString(from: insertText),
              !insertedString.isEmpty else {
            return (insertText, nil)
        }

        // Typing exactly ``` starts a visual block immediately. Ensure the
        // editable content begins on the next line while preserving raw fences
        // in the submitted composer text.
        if shouldStartCodeContentLineBeforeInserting(at: location),
           !insertedString.hasPrefix("\n") {
            return (codeBlockInsertText(insertText, replacingStringWith: "\n" + insertedString), nil)
        }

        if shouldStartCodeContentLineAfterInserting(insertedString, at: location),
           !insertedString.hasSuffix("\n"),
           !insertedString.hasSuffix("\r") {
            let normalizedString = insertedString + "\n"
            return (
                codeBlockInsertText(insertText, replacingStringWith: normalizedString),
                location + (normalizedString as NSString).length
            )
        }

        return (insertText, nil)
    }

    func applyCodeBlockPostInsertionSelection(_ selectionLocation: Int?) {
        guard let selectionLocation else {
            return
        }

        setSelectedRangeWithoutCodeBlockNormalization(NSRange(location: selectionLocation, length: 0))
        ensureCodeBlockTypingAttributesIfNeeded(at: selectionLocation)
        notifyDelegateSelectionChanged()
    }

    func normalizeCodeBlockSelectionAfterTextMutation() {
        let normalizedSelection = normalizedCodeBlockInsertionRange(selectedRange())
        guard normalizedSelection != selectedRange() else {
            return
        }

        setSelectedRangeWithoutCodeBlockNormalization(normalizedSelection)
        ensureCodeBlockTypingAttributesIfNeeded(at: normalizedSelection.location)
        notifyDelegateSelectionChanged()
    }

    func unwrapCodeBlockAtContentStartIfNeeded() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0,
              let unwrap = codeBlockUnwrapReplacement(at: selection.location) else {
            return false
        }

        // Backspace at the visual start of a block removes the hidden fence
        // wrapper, preserving any editable code content as plain text.
        guard shouldChangeText(in: unwrap.range, replacementString: unwrap.replacement) else {
            return true
        }

        textStorage?.replaceCharacters(in: unwrap.range, with: unwrap.replacement)
        didChangeText()
        setSelectedRangeWithoutCodeBlockNormalization(NSRange(location: unwrap.selectionLocation, length: 0))
        notifyDelegateSelectionChanged()
        return true
    }

    func deleteTrailingOutsideLineAfterHiddenClosingFenceIfNeeded() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0,
              let replacement = trailingOutsideLineDeletionReplacement(at: selection.location) else {
            return false
        }

        // The outside blank line after a hidden closing fence is represented by
        // the fence line's trailing newline. Delete that newline as a whole so
        // AppKit never removes one visible backtick from the hidden delimiter.
        guard shouldChangeText(in: replacement.range, replacementString: replacement.replacement) else {
            return true
        }

        textStorage?.replaceCharacters(in: replacement.range, with: replacement.replacement)
        didChangeText()
        setSelectedRangeWithoutCodeBlockNormalization(NSRange(location: replacement.selectionLocation, length: 0))
        notifyDelegateSelectionChanged()
        return true
    }

    func setSelectedRangeWithoutCodeBlockNormalization(_ range: NSRange) {
        super.setSelectedRange(range)
    }

    func ensureCodeBlockTypingAttributesIfNeeded(at location: Int) {
        guard isCodeBlockContentInsertionLocation(location) else {
            return
        }

        var attributes = AppTextEditorCodeBlockStyling.codeBlockAttributes(
            font: baseTextFont,
            colorScheme: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        )
        attributes[.foregroundColor] = NSColor.labelColor
        typingAttributes = attributes
    }

    func notifyDelegateSelectionChanged() {
        let notification = Notification(name: NSTextView.didChangeSelectionNotification, object: self)
        delegate?.textViewDidChangeSelection?(notification)
    }

    private func codeBlockInsertedString(from insertText: Any) -> String? {
        // Real key input can arrive as an attributed string, while tests and
        // programmatic insertions often use plain strings. Fence normalization
        // should key off the inserted characters either way.
        if let string = insertText as? String {
            return string
        }
        if let attributedString = insertText as? NSAttributedString {
            return attributedString.string
        }
        return nil
    }

    private func codeBlockInsertText(_ insertText: Any, replacingStringWith string: String) -> Any {
        guard let attributedString = insertText as? NSAttributedString else {
            return string
        }

        let attributes = attributedString.length > 0 ? attributedString.attributes(at: 0, effectiveRange: nil) : [:]
        return NSAttributedString(string: string, attributes: attributes)
    }

    private func shouldStartCodeContentLineBeforeInserting(at location: Int) -> Bool {
        AppMarkdownCodeBlockParser.blockCodeRanges(in: string).contains { blockRange in
            guard let openingDelimiterRange = blockRange.delimiterRanges.first,
                  blockRange.delimiterRanges.count == 1,
                  location == NSMaxRange(openingDelimiterRange),
                  openingDelimiterRange.length >= 3 else {
                return false
            }

            let delimiter = (string as NSString).substring(with: openingDelimiterRange)
            return !delimiter.hasSuffix("\n") && !delimiter.hasSuffix("\r")
        }
    }

    private func shouldStartCodeContentLineAfterInserting(_ insertedString: String, at location: Int) -> Bool {
        guard !insertedString.contains("\r") else {
            return false
        }

        let text = string as NSString
        guard location >= 0,
              location <= text.length else {
            return false
        }

        let lineRange = text.lineRange(for: NSRange(location: min(location, max(text.length - 1, 0)), length: 0))
        let prefixRange = NSRange(location: lineRange.location, length: max(location - lineRange.location, 0))
        let insertedFenceLine = insertedString.components(separatedBy: "\n").last ?? insertedString
        let linePrefix = insertedString.contains("\n") ? "" : text.substring(with: prefixRange)
        let lineTextAfterInsertion = linePrefix + insertedFenceLine
        // Ignore the existing suffix. Typing ``` at the start of "code" should
        // become "```\ncode", moving that line into the visual block.
        return lineTextAfterInsertion.trimmingCharacters(in: .whitespaces) == "```"
    }

    private func isCodeBlockContentInsertionLocation(_ location: Int) -> Bool {
        AppMarkdownCodeBlockParser.blockCodeRanges(in: string).contains { blockRange in
            location >= blockRange.contentRange.location &&
                location <= NSMaxRange(blockRange.contentRange)
        }
    }

    private func codeBlockUnwrapReplacement(at location: Int) -> AppTextEditorCodeBlockUnwrap? {
        let text = string as NSString
        guard let blockRange = AppMarkdownCodeBlockParser.blockCodeRanges(in: string).first(where: { blockRange in
            location == blockRange.contentRange.location
        }),
            let openingDelimiter = blockRange.delimiterRanges.first else {
            return nil
        }

        let fullRangeEnd = blockRange.delimiterRanges.dropFirst().first.map(NSMaxRange) ?? NSMaxRange(blockRange.contentRange)
        let fullRange = NSRange(location: openingDelimiter.location, length: max(fullRangeEnd - openingDelimiter.location, 0))
        let replacement = blockRange.contentRange.length > 0 ? text.substring(with: blockRange.contentRange) : ""
        return AppTextEditorCodeBlockUnwrap(
            range: fullRange,
            replacement: replacement,
            selectionLocation: openingDelimiter.location
        )
    }

    private func trailingOutsideLineDeletionReplacement(at location: Int) -> AppTextEditorCodeBlockUnwrap? {
        let text = string as NSString
        guard let blockRange = AppMarkdownCodeBlockParser.blockCodeRanges(in: string).first(where: { blockRange in
            guard let closingDelimiter = blockRange.delimiterRanges.dropFirst().first else {
                return false
            }
            return NSMaxRange(closingDelimiter) == text.length &&
                text.length > 0 &&
                text.character(at: text.length - 1) == 0x0A &&
                (location == NSMaxRange(closingDelimiter) || location == NSMaxRange(blockRange.contentRange))
        }),
            let closingDelimiter = blockRange.delimiterRanges.dropFirst().first else {
            return nil
        }

        let trailingNewlineRange = NSRange(location: NSMaxRange(closingDelimiter) - 1, length: 1)
        return AppTextEditorCodeBlockUnwrap(
            range: trailingNewlineRange,
            replacement: "",
            selectionLocation: trailingNewlineRange.location
        )
    }
}

private struct AppTextEditorCodeBlockUnwrap {
    let range: NSRange
    let replacement: String
    let selectionLocation: Int
}
