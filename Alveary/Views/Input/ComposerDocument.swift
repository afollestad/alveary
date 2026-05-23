import Foundation

/// Document-first model for the chat composer.
///
/// `NSTextView` should edit a `ComposerProjection.visibleString`, not the
/// serialized markdown. Markdown fences are imported into structured blocks and
/// re-created only when the composer sends, queues, or persists text.
struct ComposerDocument: Equatable {
    var blocks: [ComposerBlock]

    init(blocks: [ComposerBlock] = [.paragraph("")]) {
        self.blocks = blocks.isEmpty ? [.paragraph("")] : blocks
    }

    init(markdown: String) {
        self = ComposerMarkdownImporter.document(from: markdown)
    }

    var projection: ComposerProjection {
        ComposerProjection(document: self)
    }

    var serializedMarkdown: String {
        ComposerMarkdownSerializer.markdown(from: self)
    }

    var isEffectivelyEmpty: Bool {
        blocks.allSatisfy { block in
            switch block {
            case .paragraph(let text):
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .codeBlock(let block):
                return block.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }
}

enum ComposerBlock: Equatable {
    case paragraph(String)
    case codeBlock(ComposerCodeBlock)
}

struct ComposerCodeBlock: Equatable {
    var content: String
    var isClosed: Bool
}

/// Visible text and source mapping consumed by the AppKit editor.
struct ComposerProjection: Equatable {
    struct Segment: Equatable {
        let blockIndex: Int?
        let kind: ComposerProjectionSegmentKind
        let range: NSRange
    }

    let visibleString: String
    let segments: [Segment]

    init(document: ComposerDocument) {
        var visible = ""
        var segments: [Segment] = []

        for (index, block) in document.blocks.enumerated() {
            if index > 0, !visible.hasSuffix("\n") {
                let location = (visible as NSString).length
                visible += "\n"
                segments.append(Segment(
                    blockIndex: nil,
                    kind: .syntheticSeparator,
                    range: NSRange(location: location, length: 1)
                ))
            }

            let location = (visible as NSString).length
            let text: String
            let kind: ComposerProjectionSegmentKind
            switch block {
            case .paragraph(let value):
                text = value
                kind = .paragraph
            case .codeBlock(let value):
                text = value.content
                kind = .codeBlock
            }
            visible += text
            segments.append(Segment(
                blockIndex: index,
                kind: kind,
                range: NSRange(location: location, length: (text as NSString).length)
            ))
        }

        self.visibleString = visible
        self.segments = segments
    }

    var codeBlockRanges: [NSRange] {
        segments.compactMap { segment in
            segment.kind == .codeBlock ? segment.range : nil
        }
    }

    func codeBlockSegment(containing location: Int) -> Segment? {
        segments.first { segment in
            segment.kind == .codeBlock &&
                location >= segment.range.location &&
                location <= NSMaxRange(segment.range)
        }
    }

    func segment(containing range: NSRange) -> Segment? {
        let editableSegments = segments.filter { $0.blockIndex != nil }
        if range.length == 0 {
            return editableSegments.reversed().first { segment in
                range.location >= segment.range.location &&
                    range.location <= NSMaxRange(segment.range)
            }
        }

        return editableSegments.first { segment in
            guard segment.blockIndex != nil else {
                return false
            }
            return range.location >= segment.range.location &&
                NSMaxRange(range) <= NSMaxRange(segment.range)
        }
    }
}

enum ComposerMarkdownImporter {
    static func document(from markdown: String) -> ComposerDocument {
        let source = markdown as NSString
        guard source.length > 0 else {
            return ComposerDocument()
        }

        let codeBlocks = AppMarkdownCodeBlockParser.blockCodeRanges(in: markdown)
        guard !codeBlocks.isEmpty else {
            return ComposerDocument(blocks: [.paragraph(markdown)])
        }

        var blocks: [ComposerBlock] = []
        var cursor = 0
        for block in codeBlocks {
            if block.fullRange.location > cursor {
                appendParagraph(
                    source.substring(with: NSRange(location: cursor, length: block.fullRange.location - cursor)),
                    to: &blocks
                )
            }

            var content = source.substring(with: block.contentRange)
            let isClosed = block.delimiterRanges.count > 1
            if isClosed, content.hasSuffix("\n") {
                content.removeLast()
            }
            blocks.append(.codeBlock(ComposerCodeBlock(content: content, isClosed: isClosed)))
            cursor = NSMaxRange(block.fullRange)
        }

        if cursor < source.length {
            appendParagraph(source.substring(from: cursor), to: &blocks)
        } else if let lastCodeBlock = codeBlocks.last,
                  lastCodeBlock.delimiterRanges.count > 1,
                  source.character(at: source.length - 1) == 0x0A {
            blocks.append(.paragraph(""))
        }

        return ComposerDocument(blocks: normalizedBlocks(blocks))
    }

    private static func appendParagraph(_ text: String, to blocks: inout [ComposerBlock]) {
        guard !text.isEmpty else {
            return
        }
        if case .paragraph(let previous)? = blocks.last {
            blocks[blocks.count - 1] = .paragraph(previous + text)
        } else {
            blocks.append(.paragraph(text))
        }
    }

    private static func normalizedBlocks(_ blocks: [ComposerBlock]) -> [ComposerBlock] {
        var normalized: [ComposerBlock] = []
        for block in blocks {
            switch block {
            case .paragraph(let text) where text.isEmpty && !keepsEmptyParagraph(at: normalized.count, in: blocks):
                continue
            case .paragraph(let text):
                if case .paragraph(let previous)? = normalized.last {
                    normalized[normalized.count - 1] = .paragraph(previous + text)
                } else {
                    normalized.append(block)
                }
            case .codeBlock:
                normalized.append(block)
            }
        }
        return normalized.isEmpty ? [.paragraph("")] : normalized
    }

    private static func keepsEmptyParagraph(at index: Int, in blocks: [ComposerBlock]) -> Bool {
        guard index > 0 else {
            return false
        }
        if blocks.indices.contains(index - 1),
           case .codeBlock = blocks[index - 1] {
            return true
        }
        return false
    }
}

enum ComposerMarkdownSerializer {
    static func markdown(from document: ComposerDocument) -> String {
        var output = ""
        for (index, block) in document.blocks.enumerated() {
            if index > 0, !output.hasSuffix("\n") {
                output += "\n"
            }

            switch block {
            case .paragraph(let text):
                output += text
            case .codeBlock(let block):
                output += "```\n"
                output += block.content
                if block.isClosed {
                    if block.content.isEmpty {
                        // Empty blocks already have the opening fence newline.
                    } else if !block.content.hasSuffix("\n") {
                        output += "\n"
                    } else {
                        // Preserve an intentional trailing empty code line before
                        // writing the structural newline that precedes the fence.
                        output += "\n"
                    }
                    output += "```"
                }
            }
        }
        return output
    }
}

/// Mutates `ComposerDocument` from visible editor edits.
enum ComposerTransaction {
    static func replacingVisibleText(
        in document: ComposerDocument,
        projection: ComposerProjection,
        range: NSRange,
        replacement: String
    ) -> (document: ComposerDocument, selection: NSRange)? {
        if replacement == "```",
           range.length == 0,
           let converted = convertLineToCodeBlock(in: document, projection: projection, location: range.location) {
            return converted
        }

        if replacement.isEmpty,
           range.length == 1,
           let moved = moveFromOutsideLineIntoPreviousCodeBlock(in: document, projection: projection, deletedRange: range) {
            return moved
        }

        guard let segment = projection.segment(containing: range),
              let blockIndex = segment.blockIndex else {
            let mutable = NSMutableString(string: projection.visibleString)
            let clampedRange = clamped(range, length: mutable.length)
            mutable.replaceCharacters(in: clampedRange, with: replacement)
            return (
                ComposerDocument(blocks: [.paragraph(mutable as String)]),
                NSRange(location: clampedRange.location + (replacement as NSString).length, length: 0)
            )
        }

        var blocks = document.blocks
        let localRange = NSRange(location: range.location - segment.range.location, length: range.length)
        switch blocks[blockIndex] {
        case .paragraph(let text):
            blocks[blockIndex] = .paragraph(replacing(in: text, range: localRange, replacement: replacement))
        case .codeBlock(var block):
            block.content = replacing(in: block.content, range: localRange, replacement: replacement)
            blocks[blockIndex] = .codeBlock(block)
        }

        return (
            ComposerDocument(blocks: blocks),
            NSRange(location: range.location + (replacement as NSString).length, length: 0)
        )
    }

    static func insertNewline(
        in document: ComposerDocument,
        projection: ComposerProjection,
        location: Int
    ) -> (document: ComposerDocument, selection: NSRange)? {
        replacingVisibleText(
            in: document,
            projection: projection,
            range: NSRange(location: location, length: 0),
            replacement: "\n"
        )
    }

    private static func convertLineToCodeBlock(
        in document: ComposerDocument,
        projection: ComposerProjection,
        location: Int
    ) -> (document: ComposerDocument, selection: NSRange)? {
        guard let segment = projection.segment(containing: NSRange(location: location, length: 0)),
              segment.kind == .paragraph,
              let blockIndex = segment.blockIndex,
              case .paragraph(let paragraph) = document.blocks[blockIndex] else {
            return nil
        }

        let visible = projection.visibleString as NSString
        let lineRange: NSRange
        if location == visible.length,
           visible.length > 0,
           visible.character(at: visible.length - 1) == 0x0A {
            lineRange = NSRange(location: visible.length, length: 0)
        } else {
            lineRange = visible.lineRange(for: NSRange(location: min(location, max(visible.length - 1, 0)), length: 0))
        }
        guard location == lineRange.location else {
            return nil
        }

        let localLineLocation = lineRange.location - segment.range.location
        let localLineRange = NSRange(
            location: localLineLocation,
            length: max(lineRange.length - (visible.substring(with: lineRange).hasSuffix("\n") ? 1 : 0), 0)
        )
        let paragraphNSString = paragraph as NSString
        let lineText = paragraphNSString.substring(with: clamped(localLineRange, length: paragraphNSString.length))
        let before = paragraphNSString.substring(to: max(localLineRange.location, 0))
        let afterLocation = localLineRange.location + localLineRange.length
        let after = afterLocation < paragraphNSString.length ? paragraphNSString.substring(from: afterLocation) : ""

        var newBlocks = Array(document.blocks.prefix(blockIndex))
        if !before.isEmpty {
            newBlocks.append(.paragraph(before))
        }
        newBlocks.append(.codeBlock(ComposerCodeBlock(content: lineText, isClosed: false)))
        if !after.isEmpty {
            newBlocks.append(.paragraph(after.hasPrefix("\n") ? String(after.dropFirst()) : after))
        }
        newBlocks.append(contentsOf: document.blocks.suffix(from: blockIndex + 1))

        let newDocument = ComposerDocument(blocks: newBlocks)
        let newProjection = newDocument.projection
        let selection = newProjection.codeBlockRanges.first.map { range in
            NSRange(location: range.location, length: 0)
        } ?? NSRange(location: location, length: 0)
        return (newDocument, selection)
    }

    private static func moveFromOutsideLineIntoPreviousCodeBlock(
        in document: ComposerDocument,
        projection: ComposerProjection,
        deletedRange: NSRange
    ) -> (document: ComposerDocument, selection: NSRange)? {
        let deletedLocation = deletedRange.location
        let visibleString = projection.visibleString as NSString
        let deletedText = visibleString.substring(with: clamped(deletedRange, length: visibleString.length))
        guard deletedText == "\n" else {
            return nil
        }

        guard let codeSegment = projection.segments.last(where: { segment in
            segment.kind == .codeBlock && NSMaxRange(segment.range) == deletedLocation
        }) else {
            return nil
        }

        return (document, NSRange(location: NSMaxRange(codeSegment.range), length: 0))
    }

    private static func replacing(in text: String, range: NSRange, replacement: String) -> String {
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: clamped(range, length: mutable.length), with: replacement)
        return mutable as String
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), max(length - location, 0)))
    }
}

enum ComposerProjectionSegmentKind: Equatable {
    case paragraph
    case codeBlock
    case syntheticSeparator
}
