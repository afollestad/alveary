import Foundation
import SwiftUI

/// Code-block-specific composer keyboard handling for the document projection.
///
/// The text view contains only visible code content. Markdown fences are
/// serialized later, so navigation can work with projected code ranges instead
/// of avoiding hidden delimiter rows.
extension AppKitChatComposerBodyView {
    func handleCodeBlockLineBreakKeyPress(_ keyPress: AppTextEditorKeyPress) -> Bool {
        guard keyPress.key == .return,
              acceptsCodeBlockLineBreakModifiers(keyPress.modifiers),
              let selectedRange,
              selectedRange.length == 0,
              currentProjection.codeBlockSegment(containing: selectedRange.location) != nil,
              let configuration,
              let result = ComposerTransaction.insertNewline(
                  in: currentDocument,
                  projection: currentProjection,
                  location: selectedRange.location
              ) else {
            return false
        }

        applyDocumentResult(result, configuration: configuration)
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

    func applyDocumentResult(
        _ result: (document: ComposerDocument, selection: NSRange),
        configuration: AppKitChatComposerBodyConfiguration
    ) {
        currentDocument = result.document
        currentProjection = currentDocument.projection
        currentText = currentProjection.visibleString
        assertNoDocumentOwnedBlockFences()
        selectedRange = result.selection
        configuration.onTextChange(currentDocument.serializedMarkdown)
        editorView.configure(editorConfiguration(for: configuration))
        editorView.measureAndRefreshForCurrentLayout()
        setComposerEditorSelection(result.selection)
        refreshAutocomplete(text: currentText)
        invalidatePreferredSize()
    }

    private func codeBlockEntryTarget(
        for key: AppTextEditorKey,
        location: Int
    ) -> NSRange? {
        currentProjection.segments.compactMap { block -> NSRange? in
            guard block.kind == .codeBlock else { return nil }
            switch key {
            case .upArrow:
                return entryTargetFromLineBelow(block, location: location)
            case .downArrow:
                return entryTargetFromLineAbove(block, location: location)
            default:
                return nil
            }
        }.first
    }

    private func entryTargetFromLineAbove(_ block: ComposerProjection.Segment, location: Int) -> NSRange? {
        let nsText = currentText as NSString
        guard block.range.location > 0 else {
            return location == 0 ? NSRange(location: block.range.location, length: 0) : nil
        }

        let previousLine = nsText.lineRange(for: NSRange(location: max(block.range.location - 1, 0), length: 0))
        guard location >= previousLine.location,
              location < NSMaxRange(previousLine) else {
            return nil
        }
        return NSRange(location: block.range.location, length: 0)
    }

    private func entryTargetFromLineBelow(_ block: ComposerProjection.Segment, location: Int) -> NSRange? {
        let nextLocation = NSMaxRange(block.range)
        let nsText = currentText as NSString
        guard nextLocation < nsText.length else {
            return nil
        }

        let nextLine = nsText.lineRange(for: NSRange(location: nextLocation, length: 0))
        guard location >= nextLine.location,
              location <= NSMaxRange(nextLine) else {
            return nil
        }
        return NSRange(location: NSMaxRange(block.range), length: 0)
    }

    private func codeBlockNavigationTarget(
        for key: AppTextEditorKey,
        location: Int
    ) -> ComposerProjection.Segment? {
        currentProjection.segments.first { block in
            guard block.kind == .codeBlock else { return false }
            switch key {
            case .upArrow:
                return canExitAbove(block, from: location)
            case .downArrow:
                return canExitBelow(block, from: location)
            default:
                return false
            }
        }
    }

    private func canExitAbove(_ block: ComposerProjection.Segment, from location: Int) -> Bool {
        guard location >= block.range.location,
              location <= NSMaxRange(block.range) else {
            return false
        }
        let nsText = currentText as NSString
        let line = lineRange(in: nsText, at: location)
        return line.location <= block.range.location
    }

    private func canExitBelow(_ block: ComposerProjection.Segment, from location: Int) -> Bool {
        guard location >= block.range.location,
              location <= NSMaxRange(block.range) else {
            return false
        }
        let nsText = currentText as NSString
        let line = lineRange(in: nsText, at: location)
        return NSMaxRange(line) >= NSMaxRange(block.range)
    }

    private func lineRange(in text: NSString, at location: Int) -> NSRange {
        guard text.length > 0 else {
            return NSRange(location: 0, length: 0)
        }
        return text.lineRange(for: NSRange(location: min(max(location, 0), text.length - 1), length: 0))
    }

    private func exitCodeBlockBelow(_ block: ComposerProjection.Segment) {
        guard let configuration,
              let blockIndex = block.blockIndex else {
            return
        }

        if let nextParagraph = currentProjection.segments.first(where: { segment in
            segment.kind == .paragraph && segment.blockIndex.map { $0 > blockIndex } == true
        }) {
            moveInsertionPoint(to: NSRange(location: nextParagraph.range.location, length: 0))
            return
        }

        var blocks = currentDocument.blocks
        if case .codeBlock(var codeBlock) = blocks[blockIndex] {
            codeBlock.isClosed = true
            blocks[blockIndex] = .codeBlock(codeBlock)
        }
        blocks.insert(.paragraph(""), at: min(blockIndex + 1, blocks.count))
        let document = ComposerDocument(blocks: blocks)
        let projection = document.projection
        let target = projection.segments.first { $0.blockIndex == blockIndex + 1 }?.range.location ?? NSMaxRange(block.range)
        applyDocumentResult((document, NSRange(location: target, length: 0)), configuration: configuration)
    }

    private func exitCodeBlockAbove(_ block: ComposerProjection.Segment) {
        guard let configuration,
              let blockIndex = block.blockIndex else {
            return
        }

        if let previousParagraph = currentProjection.segments.last(where: { segment in
            segment.kind == .paragraph && segment.blockIndex.map { $0 < blockIndex } == true
        }) {
            moveInsertionPoint(to: NSRange(location: endOfVisibleParagraphLine(previousParagraph), length: 0))
            return
        }

        var blocks = currentDocument.blocks
        blocks.insert(.paragraph(""), at: blockIndex)
        applyDocumentResult((ComposerDocument(blocks: blocks), NSRange(location: 0, length: 0)), configuration: configuration)
    }

    private func moveInsertionPoint(to targetSelection: NSRange) {
        selectedRange = targetSelection
        guard let configuration else {
            return
        }
        editorView.configure(editorConfiguration(for: configuration))
        setComposerEditorSelection(targetSelection)
    }

    private func endOfVisibleParagraphLine(_ paragraph: ComposerProjection.Segment) -> Int {
        let text = currentText as NSString
        let end = NSMaxRange(paragraph.range)
        guard end > paragraph.range.location,
              end <= text.length,
              text.character(at: end - 1) == 0x0A else {
            return end
        }
        return end - 1
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

    private func setComposerEditorSelection(_ range: NSRange) {
        editorView.textViewForTesting.setSelectedRanges(
            [NSValue(range: range)],
            affinity: .downstream,
            stillSelecting: false
        )
        selectedRange = range
    }
}
