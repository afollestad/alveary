import Foundation

/// Disclosure geometry, shared by both renderers and by `AppKitMarkdownLayoutMeasurer`.
///
/// It lives in Core rather than in either renderer because the measurer predicts the AppKit view's
/// height without building it: a number the two spelled separately could drift, and the transcript
/// would reserve height that no drawn pixel occupies.
enum AppMarkdownDetailsMetrics {
    static let chevronWidth: CGFloat = 14
    static let chevronSpacing: CGFloat = 4
    /// Gap between a disclosure's header and its body. Spent only while open — held as stack
    /// spacing instead, it would prop a gap open under every collapsed disclosure.
    static let bodySpacing: CGFloat = 8
    /// Body inset, so a disclosure's contents read as belonging to their summary.
    static let bodyIndent: CGFloat = 18
    /// Dimming for a disclosure with nothing to reveal, which both renderers draw but neither
    /// makes clickable.
    static let inertHeaderOpacity: CGFloat = 0.6
}

/// Locates the disclosure spans in raw markdown source, so the document splitter can lift them
/// into `AppMarkdownDocumentBlock.details` instead of letting Foundation's parser print the tags
/// literally.
///
/// This is the block-path counterpart to the flattening rewrite in `AppMarkdownParser`: the
/// splitter runs against `.preserveSource` text where the tags survive, while every other parsing
/// path has already rewritten them into bold-summary-plus-body.
enum AppMarkdownDetailsSyntaxParser {
    /// What GitHub renders when a disclosure declares no `<summary>` and its tag names nothing
    /// better; see `label(from:)`.
    static let defaultSummary = "Details"

    /// The tags that become a disclosure. Both patterns below are built from this list, so a tag
    /// added here needs no second edit.
    ///
    /// `<details>` is GitHub's own. `<section>` earns its place because bots reach for it to
    /// imitate GitHub's footnote footer: left unclaimed it printed its own tags and, once its
    /// `<p>` wrapper became blank lines, dropped a four-space-indented body into a code block.
    static let disclosureTagNames = ["details", "section"]

    /// Top-level disclosure spans in source order, skipping fenced and inline code.
    ///
    /// Nested disclosures stay inside their parent's `bodySource` for the caller to recurse into,
    /// which is what makes nesting work without this function knowing about it. An unbalanced or
    /// unclosed span yields no match at all, so the caller renders the raw text rather than
    /// swallowing everything to the end of the document.
    static func matchesOutsideCode(in text: String) -> [AppMarkdownDetailsMatch] {
        // Every caller runs on arbitrary markdown; skip the regex work for the overwhelming
        // majority of bodies that contain no disclosure.
        guard disclosureTagNames.contains(where: { text.range(of: "<\($0)", options: .caseInsensitive) != nil }) else {
            return []
        }

        let source = text as NSString
        let excluded = excludedCodeRanges(in: text)
        let openings = matches(for: openingPattern, in: text, excluding: excluded)
        let closings = matches(for: closingPattern, in: text, excluding: excluded)
        guard !openings.isEmpty, !closings.isEmpty else {
            return []
        }

        let tokens = (openings.map { Token(match: $0, source: source, isOpening: true) }
            + closings.map { Token(match: $0, source: source, isOpening: false) })
            .sorted { $0.range.location < $1.range.location }

        var results: [AppMarkdownDetailsMatch] = []
        var open: [Token] = []

        for token in tokens {
            guard !token.isOpening else {
                open.append(token)
                continue
            }

            // Pair with the innermost tag of the *same name*, so a `</section>` cannot close a
            // `<details>`. Anything opened after that one was never closed, and is discarded with
            // it rather than being left to swallow a later closing tag.
            guard let index = open.lastIndex(where: { $0.tag == token.tag }) else {
                // A stray closing tag with nothing open; ignore it rather than pairing it
                // with a later opening tag and inverting the span.
                continue
            }
            let opening = open[index]
            open.removeSubrange(index...)
            guard open.isEmpty else {
                // Still inside an outer disclosure, which carries this one in its body source.
                continue
            }

            let bodyStart = NSMaxRange(opening.range)
            let bodyRange = NSRange(location: bodyStart, length: max(token.range.location - bodyStart, 0))
            results.append(
                detailsMatch(
                    outerRange: NSRange(location: opening.range.location, length: NSMaxRange(token.range) - opening.range.location),
                    body: source.substring(with: bodyRange),
                    openingTag: source.substring(with: opening.range)
                )
            )
        }

        return results
    }

    private static func detailsMatch(
        outerRange: NSRange,
        body: String,
        openingTag: String
    ) -> AppMarkdownDetailsMatch {
        let summary = summary(in: markdownByDedenting(body), openingTag: openingTag)
        return AppMarkdownDetailsMatch(
            range: outerRange,
            bodySource: summary.remainingBody,
            summarySource: summary.text,
            isOpen: openingTagDeclaresOpen(openingTag)
        )
    }

    /// Pulls this disclosure's own `<summary>` out of its body.
    ///
    /// The first `<summary>` in the source is not necessarily this disclosure's — a parent with no
    /// summary of its own would otherwise adopt its first child's — so nested spans are excluded
    /// before picking.
    private static func summary(in body: String, openingTag: String) -> (text: String, remainingBody: String) {
        let nested = matchesOutsideCode(in: body).map(\.range)
        let excluded = excludedCodeRanges(in: body) + nested
        guard let match = firstMatch(for: summaryPattern, in: body, excluding: excluded),
              match.numberOfRanges == 2 else {
            return (label(from: openingTag), body)
        }

        let source = body as NSString
        let text = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        let remaining = NSMutableString(string: body)
        remaining.replaceCharacters(in: match.range, with: "")
        return (
            text.isEmpty ? label(from: openingTag) : text,
            remaining as String
        )
    }

    /// The header text for a disclosure whose markup carries no `<summary>`.
    ///
    /// A `<section>` never has one, and a bare "Details" over a footnote footer names it worse than
    /// its own attributes do. Only a *single-token* `class` is taken — a list of styling classes is
    /// not a title, and guessing which of them is would read as noise in the header.
    private static func label(from openingTag: String) -> String {
        if let ariaLabel = attributeValue("aria-label", in: openingTag), !ariaLabel.isEmpty {
            return ariaLabel
        }
        if let className = attributeValue("class", in: openingTag),
           !className.isEmpty,
           className.split(whereSeparator: \.isWhitespace).count == 1 {
            return humanized(className)
        }
        return defaultSummary
    }

    /// `footnotes` → `Footnotes`, `test-logs` → `Test logs`.
    private static func humanized(_ token: String) -> String {
        let spaced = token
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard let first = spaced.first else {
            return spaced
        }
        return first.uppercased() + spaced.dropFirst()
    }

    /// Removes the indentation an HTML wrapper's own pretty-printing left behind.
    ///
    /// A bot indents `<section>`'s contents four spaces; once the wrapper is lifted and its `<p>`
    /// tags have become blank lines, CommonMark reads those columns as an indented code block and
    /// boxes the body in monospace. Dedenting by the *minimum* across non-blank lines is what keeps
    /// a body that deliberately holds an indented code block intact — its prose sits at column
    /// zero, so the minimum is zero and nothing moves.
    private static func markdownByDedenting(_ body: String) -> String {
        // Spaces and tabs only, which is all CommonMark counts as indentation. `isWhitespace` also
        // matches a non-breaking space, and a line opening with one means it, so eating it would
        // rewrite the body rather than unindent it.
        let isIndent: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        let lines = body.components(separatedBy: "\n")
        let indents = lines.compactMap { line -> Int? in
            let indent = line.prefix(while: isIndent).count
            // A whitespace-only line carries no column of its own; counting it would pin the
            // minimum at whatever stray spaces the wrapper left on an otherwise empty line.
            return indent == line.count ? nil : indent
        }
        guard let minimum = indents.min(), minimum > 0 else {
            return body
        }
        return lines
            .map { line in
                String(line.dropFirst(min(minimum, line.prefix(while: isIndent).count)))
            }
            .joined(separator: "\n")
    }

    /// `open`, `open=""`, and `open="open"` all mean open; `open="false"` is the one spelling
    /// that does not, matching how browsers treat the attribute's absence as the only closed state
    /// while still honoring an explicit denial.
    ///
    /// The leading `(?<=\s)` is what keeps this an *attribute* match: a plain `\bopen\b` also fires
    /// inside `data-open`, `class="open-section"`, and `id="open"`, silently expanding disclosures
    /// their author left shut.
    private static func openingTagDeclaresOpen(_ tag: String) -> Bool {
        guard let value = attributeValue("open", in: tag, allowsValueless: true) else {
            return false
        }
        return value.lowercased() != "false"
    }

    /// One attribute's value, unquoted. `allowsValueless` is what separates a boolean attribute
    /// (`<details open>`) from a named one — for the latter a bare name carries no value and must
    /// not read as an empty string.
    private static func attributeValue(
        _ name: String,
        in tag: String,
        allowsValueless: Bool = false
    ) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<=\s)\#(escapedName)\b(?:\s*=\s*("[^"]*"|'[^']*'|[^\s>]+))?"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let source = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: source.length)),
              match.numberOfRanges == 2 else {
            return nil
        }
        let valueRange = match.range(at: 1)
        guard valueRange.location != NSNotFound else {
            return allowsValueless ? "" : nil
        }
        var value = source.substring(with: valueRange)
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func excludedCodeRanges(in text: String) -> [NSRange] {
        let codeRanges = AppMarkdownCodeBlockParser.codeRanges(in: text)
        return codeRanges.blockRanges + codeRanges.inlineFullRanges
    }

    private static func matches(
        for pattern: String,
        in text: String,
        excluding excludedRanges: [NSRange]
    ) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            .filter { match in
                !excludedRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
            }
    }

    private static func firstMatch(
        for pattern: String,
        in text: String,
        excluding excludedRanges: [NSRange]
    ) -> NSTextCheckingResult? {
        matches(for: pattern, in: text, excluding: excludedRanges).first
    }

    private static let tagAlternation = disclosureTagNames.joined(separator: "|")
    private static let openingPattern = "<(\(tagAlternation))(?:\\s[^>]*)?>"
    private static let closingPattern = "</(\(tagAlternation))\\s*>"
    private static let summaryPattern = #"<summary(?:\s[^>]*)?>([\s\S]*?)</summary>"#

    private struct Token {
        let range: NSRange
        /// Lowercased tag name, so `</DETAILS>` still pairs with `<details>`.
        let tag: String
        let isOpening: Bool

        init(match: NSTextCheckingResult, source: NSString, isOpening: Bool) {
            range = match.range
            tag = source.substring(with: match.range(at: 1)).lowercased()
            self.isOpening = isOpening
        }
    }
}

extension AppMarkdownParser {
    /// Splits source into document blocks, lifting disclosures out first and recursing into each
    /// one's body so images and nested disclosures inside a disclosure get the same treatment they
    /// get at the top level.
    ///
    /// Disclosures are split before images because a disclosure *contains* images; doing it the
    /// other way would extract an image out of the body it belongs to.
    func appMarkdownDocumentBlocks(
        for input: String,
        fullContent: AttributedString? = nil
    ) throws -> [AppMarkdownDocumentBlock] {
        let matches = AppMarkdownDetailsSyntaxParser.matchesOutsideCode(in: input)
        guard !matches.isEmpty else {
            return try appMarkdownImageBlocks(for: input, fullContent: fullContent)
        }

        let source = input as NSString
        var blocks: [AppMarkdownDocumentBlock] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                let fragment = source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                try appendImageSplitBlocks(fragment, to: &blocks)
            }
            blocks.append(.details(try detailsBlock(for: match)))
            cursor = NSMaxRange(match.range)
        }

        if cursor < source.length {
            try appendImageSplitBlocks(source.substring(from: cursor), to: &blocks)
        }

        if blocks.isEmpty {
            if let fullContent {
                return [.markdown(fullContent)]
            }
            return [.markdown(try attributedString(for: input))]
        }
        return blocks
    }

    func appMarkdownDocumentBlocksPreservingSource(
        for input: String,
        fullContent: AttributedString
    ) -> [AppMarkdownDocumentBlock] {
        do {
            return try appMarkdownDocumentBlocks(for: input, fullContent: fullContent)
        } catch {
            return [.markdown(fullContent)]
        }
    }

    private func detailsBlock(for match: AppMarkdownDetailsMatch) throws -> AppMarkdownDetailsBlock {
        // A summary is a single line of prose, so it parses in `.inline` mode — block parsing
        // would wrap it in a paragraph intent the header has nowhere to put.
        var summaryParser = self
        summaryParser.parsingMode = .inline
        // An empty body must be no blocks, not one empty markdown block: the latter draws a
        // blank line's worth of height under the header the moment the disclosure is opened.
        let hasBody = match.bodySource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return AppMarkdownDetailsBlock(
            summary: try summaryParser.attributedString(for: match.summarySource),
            blocks: hasBody ? try appMarkdownDocumentBlocks(for: match.bodySource) : [],
            isInitiallyOpen: match.isOpen
        )
    }

    private func appendImageSplitBlocks(
        _ fragment: String,
        to blocks: inout [AppMarkdownDocumentBlock]
    ) throws {
        // A disclosure sitting alone, or two in a row, leaves whitespace-only fragments either
        // side of it; emitting those as markdown blocks would add an empty block's worth of
        // stack spacing above and below every disclosure.
        guard fragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }
        blocks.append(contentsOf: try appMarkdownImageBlocks(for: fragment))
    }
}

struct AppMarkdownDetailsMatch {
    /// The whole disclosure span, both tags included.
    let range: NSRange
    /// What sits between the tags, dedented, with this disclosure's own `<summary>` removed.
    let bodySource: String
    let summarySource: String
    let isOpen: Bool
}
