import Foundation
import SwiftUI

/// Code-block-specific composer keyboard handling.
///
/// Raw fences stay in the backing string, but arrow navigation treats them as hidden chrome:
/// users should move between visible text lines and editable code content, never onto delimiter rows.
extension AppKitChatComposerBodyView {
    func handleCodeBlockLineBreakKeyPress(_ keyPress: AppTextEditorKeyPress) -> Bool {
        guard keyPress.key == .return,
              acceptsCodeBlockLineBreakModifiers(keyPress.modifiers),
              let selectedRange,
              selectedRange.length == 0,
              isInsideCodeBlockContent(location: selectedRange.location) else {
            return false
        }

        insertTextIntoComposer("\n", replacing: selectedRange)
        return true
    }

    func handleCodeBlockNavigationKeyPress(_ keyPress: AppTextEditorKeyPress) -> Bool {
        guard acceptsCodeBlockNavigationModifiers(keyPress.modifiers),
              let selectedRange,
              selectedRange.length == 0 else {
            return false
        }

        if let targetSelection = codeBlockEntryTarget(for: keyPress.key, location: selectedRange.location) {
            moveInsertionPoint(to: targetSelection)
            return true
        }

        guard let block = codeBlockNavigationTarget(for: keyPress.key, location: selectedRange.location) else {
            return false
        }

        switch keyPress.key {
        case .upArrow:
            exitCodeBlockAbove(block)
        case .downArrow:
            exitCodeBlockBelow(block)
        default:
            return false
        }
        return true
    }

    private func codeBlockEntryTarget(
        for key: AppTextEditorKey,
        location: Int
    ) -> NSRange? {
        // This handles re-entry from outside a block. AppKit's default vertical
        // movement sees the hidden fence lines, so intercept the adjacent visible
        // lines before the caret can land on a delimiter.
        AppMarkdownCodeBlockParser.blockCodeRanges(in: currentText).compactMap { block in
            switch key {
            case .upArrow:
                return entryTargetAboveClosingDelimiter(block, location: location)
            case .downArrow:
                return entryTargetBelowOpeningDelimiter(block, location: location)
            default:
                return nil
            }
        }.first
    }

    private func entryTargetBelowOpeningDelimiter(_ block: AppMarkdownBlockCodeRange, location: Int) -> NSRange? {
        guard let openingDelimiter = block.delimiterRanges.first else {
            return nil
        }

        if isInsertionLocationOnLineAboveOpeningDelimiter(openingDelimiter, location: location) ||
            NSLocationInRange(location, openingDelimiter) {
            return NSRange(location: block.contentRange.location, length: 0)
        }
        return nil
    }

    private func entryTargetAboveClosingDelimiter(_ block: AppMarkdownBlockCodeRange, location: Int) -> NSRange? {
        guard let closingDelimiter = block.delimiterRanges.dropFirst().first else {
            return nil
        }

        if isInsertionLocationOnLineBelowClosingDelimiter(closingDelimiter, location: location) ||
            NSLocationInRange(location, closingDelimiter) {
            return NSRange(location: editableContentEndLocation(for: block), length: 0)
        }
        return nil
    }

    private func isInsertionLocationOnLineBelowClosingDelimiter(_ closingDelimiter: NSRange, location: Int) -> Bool {
        let nsText = currentText as NSString
        let lineStart = NSMaxRange(closingDelimiter)
        guard lineStart <= nsText.length else {
            return false
        }
        guard lineStart < nsText.length else {
            return location == lineStart
        }

        let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
        guard lineRange.location == lineStart else {
            return false
        }
        // A real text line below the fence can report a caret anywhere on that
        // line, while a trailing blank line at EOF can report the end position.
        if location >= lineRange.location,
           location < NSMaxRange(lineRange) {
            return true
        }

        let lineText = nsText.substring(with: lineRange)
        return location == NSMaxRange(lineRange) &&
            NSMaxRange(lineRange) == nsText.length &&
            lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func editableContentEndLocation(for block: AppMarkdownBlockCodeRange) -> Int {
        let contentEnd = NSMaxRange(block.contentRange)
        guard block.contentRange.length > 0 else {
            return block.contentRange.location
        }

        // Closed block content commonly ends with the newline before the hidden
        // closing fence. Put the caret before that newline so re-entry stays in
        // visible code content instead of normalizing to the delimiter row.
        let nsText = currentText as NSString
        let previousLocation = contentEnd - 1
        guard previousLocation >= block.contentRange.location,
              previousLocation < nsText.length,
              nsText.character(at: previousLocation) == 0x0A else {
            return contentEnd
        }
        return previousLocation
    }

    private func codeBlockNavigationTarget(
        for key: AppTextEditorKey,
        location: Int
    ) -> AppMarkdownBlockCodeRange? {
        AppMarkdownCodeBlockParser.blockCodeRanges(in: currentText).first { block in
            switch key {
            case .upArrow:
                return block.canExitAbove(from: location, in: currentText as NSString)
            case .downArrow:
                return block.canExitBelow(from: location, in: currentText as NSString)
            default:
                return false
            }
        }
    }

    private func isInsideCodeBlockContent(location: Int) -> Bool {
        AppMarkdownCodeBlockParser.blockCodeRanges(in: currentText).contains { block in
            location >= block.contentRange.location &&
                location <= NSMaxRange(block.contentRange)
        }
    }

    private func exitCodeBlockBelow(_ block: AppMarkdownBlockCodeRange) {
        let closingDelimiter = block.delimiterRanges.dropFirst().first
        if let closingDelimiter {
            moveInsertionPointBelowExistingClosingDelimiter(closingDelimiter)
            return
        }

        let insertionLocation = NSMaxRange(block.contentRange)
        let prefix = (currentText as NSString).substring(to: min(insertionLocation, (currentText as NSString).length))
        let textToInsert = prefix.hasSuffix("\n") ? "```\n" : "\n```\n"
        insertTextIntoComposer(
            textToInsert,
            replacing: NSRange(location: insertionLocation, length: 0),
            selectionOffset: (textToInsert as NSString).length
        )
    }

    private func exitCodeBlockAbove(_ block: AppMarkdownBlockCodeRange) {
        guard let openingDelimiter = block.delimiterRanges.first else {
            return
        }

        if openingDelimiter.location == 0 {
            insertTextIntoComposer("\n", replacing: NSRange(location: 0, length: 0), selectionOffset: 0)
            return
        }

        moveInsertionPoint(to: NSRange(location: insertionLocationOnLineAbove(openingDelimiter), length: 0))
    }

    private func moveInsertionPointBelowExistingClosingDelimiter(_ closingDelimiter: NSRange) {
        let nsText = currentText as NSString
        let insertionLocation = NSMaxRange(closingDelimiter)
        // `closingDelimiter` includes the fence line newline. If text follows,
        // `NSMaxRange` is already the first visible location below the block.
        guard insertionLocation < nsText.length else {
            insertTextIntoComposer("\n", replacing: NSRange(location: NSMaxRange(closingDelimiter), length: 0))
            return
        }

        moveInsertionPoint(to: NSRange(location: insertionLocation, length: 0))
    }

    private func moveInsertionPoint(to targetSelection: NSRange) {
        selectedRange = targetSelection
        guard let configuration else {
            return
        }
        editorView.configure(editorConfiguration(for: configuration))
        setComposerEditorSelection(targetSelection)
    }

    private func insertTextIntoComposer(
        _ insertedText: String,
        replacing range: NSRange,
        selectionOffset: Int? = nil
    ) {
        guard let configuration else {
            return
        }

        let mutableText = NSMutableString(string: currentText)
        let clampedRange = clampedReplacementRange(range, textLength: mutableText.length)
        mutableText.replaceCharacters(in: clampedRange, with: insertedText)

        currentText = mutableText as String
        let targetSelection = NSRange(
            location: clampedRange.location + (selectionOffset ?? (insertedText as NSString).length),
            length: 0
        )
        selectedRange = targetSelection
        configuration.onTextChange(currentText)
        editorView.configure(editorConfiguration(for: configuration))
        editorView.measureAndRefreshForCurrentLayout()
        setComposerEditorSelection(targetSelection)
        refreshAutocomplete(text: currentText)
        selectedRange = targetSelection
        invalidatePreferredSize()
    }

    private func acceptsCodeBlockLineBreakModifiers(_ modifiers: EventModifiers) -> Bool {
        var meaningfulModifiers = modifiers
        meaningfulModifiers.remove(.shift)
        return modifiers.contains(.shift) && inertCodeBlockModifiersRemoved(from: meaningfulModifiers).isEmpty
    }

    private func acceptsCodeBlockNavigationModifiers(_ modifiers: EventModifiers) -> Bool {
        inertCodeBlockModifiersRemoved(from: modifiers).isEmpty
    }

    private func inertCodeBlockModifiersRemoved(from modifiers: EventModifiers) -> EventModifiers {
        var meaningfulModifiers = modifiers
        meaningfulModifiers.remove(.numericPad)
        meaningfulModifiers.remove(.capsLock)
        return meaningfulModifiers
    }

    private func insertionLocationOnLineAbove(_ openingDelimiter: NSRange) -> Int {
        guard openingDelimiter.location > 0 else {
            return 0
        }

        let previousLocation = openingDelimiter.location - 1
        let nsText = currentText as NSString
        guard previousLocation >= 0,
              previousLocation < nsText.length,
              nsText.character(at: previousLocation) == 0x0A else {
            return openingDelimiter.location
        }
        return previousLocation
    }

    private func isInsertionLocationOnLineAboveOpeningDelimiter(_ openingDelimiter: NSRange, location: Int) -> Bool {
        guard openingDelimiter.location > 0 else {
            return location == 0
        }

        // AppKit preserves the caret's horizontal column for vertical movement,
        // so Down from the start of the visible line above a block can otherwise
        // target the hidden opening fence instead of the code content.
        let nsText = currentText as NSString
        let previousLocation = openingDelimiter.location - 1
        guard previousLocation >= 0,
              previousLocation < nsText.length,
              nsText.character(at: previousLocation) == 0x0A else {
            return location == openingDelimiter.location
        }

        let lineRange = nsText.lineRange(for: NSRange(location: previousLocation, length: 0))
        return location >= lineRange.location && location < NSMaxRange(lineRange)
    }

    private func clampedReplacementRange(_ range: NSRange, textLength: Int) -> NSRange {
        let location = min(max(range.location, 0), textLength)
        let maxLength = max(textLength - location, 0)
        return NSRange(location: location, length: min(max(range.length, 0), maxLength))
    }

    private func setComposerEditorSelection(_ range: NSRange) {
        editorView.textViewForTesting.setSelectedRanges(
            [NSValue(range: range)],
            affinity: .downstream,
            stillSelecting: false
        )
        selectedRange = range
    }
}

private extension AppMarkdownBlockCodeRange {
    func canExitAbove(from location: Int, in text: NSString) -> Bool {
        guard containsContentInsertionLocation(location),
              let firstLineRange = firstContentLineRange(in: text) else {
            return false
        }

        return firstLineRange.containsInsertionLocation(location, contentRange: contentRange)
    }

    func canExitBelow(from location: Int, in text: NSString) -> Bool {
        guard containsContentInsertionLocation(location),
              let lastLineRange = lastContentLineRange(in: text) else {
            return false
        }

        return lastLineRange.containsInsertionLocation(location, contentRange: contentRange)
    }

    private func containsContentInsertionLocation(_ location: Int) -> Bool {
        location >= contentRange.location && location <= NSMaxRange(contentRange)
    }

    private func firstContentLineRange(in text: NSString) -> NSRange? {
        contentLineRange(containing: contentRange.location, in: text)
    }

    private func lastContentLineRange(in text: NSString) -> NSRange? {
        let contentEnd = NSMaxRange(contentRange)
        guard contentRange.length > 0 else {
            return NSRange(location: contentRange.location, length: 0)
        }

        if delimiterRanges.count == 1,
           contentEnd <= text.length,
           contentEnd > contentRange.location,
           text.character(at: contentEnd - 1) == 0x0A {
            return NSRange(location: contentEnd, length: 0)
        }

        return contentLineRange(containing: contentEnd - 1, in: text)
    }

    private func contentLineRange(containing location: Int, in text: NSString) -> NSRange? {
        guard text.length > 0,
              location >= 0,
              location <= text.length else {
            return contentRange.length == 0 ? NSRange(location: contentRange.location, length: 0) : nil
        }

        let characterLocation = min(location, max(text.length - 1, 0))
        return text.lineRange(for: NSRange(location: characterLocation, length: 0))
    }
}

private extension NSRange {
    func containsInsertionLocation(_ location: Int, contentRange: NSRange) -> Bool {
        if length == 0 {
            return location == self.location
        }

        if location >= self.location,
           location < NSMaxRange(self) {
            return true
        }

        return location == NSMaxRange(self) && location == NSMaxRange(contentRange)
    }
}
