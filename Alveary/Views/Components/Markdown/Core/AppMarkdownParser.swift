import Foundation

// Foundation's markdown parser has no native underline intent. These private-use
// markers survive parsing, then get removed after their enclosed range is underlined.
private let appMarkdownUnderlineStartMarker = "\u{E000}"
private let appMarkdownUnderlineEndMarker = "\u{E001}"

enum AppMarkdownParsingMode {
    case structured
    case inline
}

struct AppMarkdownParser {
    let baseURL: URL?
    let composerChipProvider: ((String) -> [AppTextEditorChip])?
    var parsingMode: AppMarkdownParsingMode = .structured

    init(
        baseURL: URL? = nil,
        composerChipProvider: ((String) -> [AppTextEditorChip])? = nil,
        parsingMode: AppMarkdownParsingMode = .structured
    ) {
        self.baseURL = baseURL
        self.composerChipProvider = composerChipProvider
        self.parsingMode = parsingMode
    }

    func document(for input: String) throws -> AppMarkdownDocument {
        AppMarkdownDocument(content: try attributedString(for: input))
    }

    func documentPreservingSource(for input: String) -> AppMarkdownDocument {
        do {
            return try document(for: input)
        } catch {
            return AppMarkdownDocument(content: AttributedString(markdownByPreparingSourceForParsing(input)))
        }
    }

    func attributedString(for input: String) throws -> AttributedString {
        let input = markdownByPreparingSourceForParsing(input)
        let options: AttributedString.MarkdownParsingOptions
        switch parsingMode {
        case .structured:
            options = .init()
        case .inline:
            options = .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        }

        var attributedString = try AttributedString(
            markdown: input,
            options: options,
            baseURL: baseURL
        )
        applyUnderlineMarkers(to: &attributedString)
        attachComposerChips(to: &attributedString)
        return attributedString
    }

    private func markdownByPreparingSourceForParsing(_ input: String) -> String {
        var output = markdownByNormalizingFrontMatter(in: input)
        output = replacingMatchesOutsideCode(
            pattern: #"<u(?:\s[^>]*)?>([\s\S]*?)</u>"#,
            in: output
        ) { source, match in
            appMarkdownUnderlineStartMarker + source.substring(with: match.range(at: 1)) + appMarkdownUnderlineEndMarker
        }
        output = replacingHTMLPairTags(["strong", "b"], marker: "**", in: output)
        output = replacingHTMLPairTags(["em", "i"], marker: "*", in: output)
        output = replacingMatchesOutsideCode(
            pattern: #"<a\s+[^>]*href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>([\s\S]*?)</a>"#,
            in: output
        ) { source, match in
            let destination = (1...3)
                .compactMap { rangeIndex -> String? in
                    let range = match.range(at: rangeIndex)
                    return range.location == NSNotFound ? nil : source.substring(with: range)
                }
                .first ?? ""
            return "[\(source.substring(with: match.range(at: 4)))](\(destination))"
        }
        output = replacingMatchesOutsideCode(
            pattern: #"<p(?:\s[^>]*)?>([\s\S]*?)</p>"#,
            in: output
        ) { source, match in
            "\n\n\(source.substring(with: match.range(at: 1)))\n\n"
        }
        output = replacingMatchesOutsideCode(
            pattern: #"!\[([^\]]*)\]\(([^)]*)\)"#,
            in: output
        ) { source, match in
            let altText = source.substring(with: match.range(at: 1))
            let destination = source.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return altText.isEmpty ? destination : altText
        }
        return output
    }

    private func markdownByNormalizingFrontMatter(in input: String) -> String {
        let source = input as NSString
        guard source.length > 0 else {
            return input
        }

        let firstLineRange = source.lineRange(for: NSRange(location: 0, length: 0))
        guard trimmedLine(source.substring(with: firstLineRange)) == "---" else {
            return input
        }

        var location = NSMaxRange(firstLineRange)
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            if trimmedLine(source.substring(with: lineRange)) == "---" {
                let frontMatterRange = NSRange(location: NSMaxRange(firstLineRange), length: lineRange.location - NSMaxRange(firstLineRange))
                let bodyStart = NSMaxRange(lineRange)
                let frontMatter = frontMatterMarkdown(from: source.substring(with: frontMatterRange))
                let body = bodyStart < source.length ? source.substring(from: bodyStart).trimmingCharacters(in: .newlines) : ""
                return [frontMatter, "---", body]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
            }
            location = NSMaxRange(lineRange)
        }
        return input
    }

    private func frontMatterMarkdown(from rawFrontMatter: String) -> String {
        rawFrontMatter.trimmingCharacters(in: .newlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let value = String(line)
                return value.isEmpty ? value : "\(frontMatterLineMarkdown(from: value))  "
            }
            .joined(separator: "\n")
    }

    private func frontMatterLineMarkdown(from line: String) -> String {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return line
        }
        let prefix = line[..<colonIndex]
        let indentation = prefix.prefix(while: \.isWhitespace)
        let key = prefix.dropFirst(indentation.count)
        guard !key.isEmpty else {
            return line
        }
        return "\(indentation)**\(key)**\(line[colonIndex...])"
    }

    private func trimmedLine(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacingHTMLPairTags(
        _ tags: [String],
        marker: String,
        in input: String
    ) -> String {
        tags.reduce(input) { partial, tag in
            replacingMatchesOutsideCode(
                pattern: #"<\#(tag)(?:\s[^>]*)?>([\s\S]*?)</\#(tag)>"#,
                in: partial
            ) { source, match in
                marker + source.substring(with: match.range(at: 1)) + marker
            }
        }
    }

    private func replacingMatchesOutsideCode(
        pattern: String,
        in input: String,
        replacement: (NSString, NSTextCheckingResult) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }

        let source = input as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let codeRanges = AppMarkdownCodeBlockParser.codeRanges(in: input)
        let excludedRanges = codeRanges.blockRanges + codeRanges.inlineFullRanges
        let matches = regex.matches(in: input, range: fullRange)
            .filter { match in
                !excludedRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
            }
            .reversed()
        guard !matches.isEmpty else {
            return input
        }

        let result = NSMutableString(string: input)
        for match in matches {
            result.replaceCharacters(in: match.range, with: replacement(source, match))
        }
        return result as String
    }

    private func applyUnderlineMarkers(to attributedString: inout AttributedString) {
        let pairs = underlineMarkerPairs(in: String(attributedString.characters)).reversed()
        for pair in pairs {
            removeRange(pair.endMarkerRange, from: &attributedString)
            removeRange(pair.startMarkerRange, from: &attributedString)
            let underlinedRange = NSRange(
                location: pair.contentRange.location - pair.startMarkerRange.length,
                length: pair.contentRange.length
            )
            guard let attributedRange = resolveAttributedRange(for: underlinedRange, in: attributedString) else {
                continue
            }
            attributedString[attributedRange].underlineStyle = .single
        }
    }

    private func underlineMarkerPairs(in input: String) -> [AppMarkdownUnderlineMarkerPair] {
        let source = input as NSString
        let startLength = (appMarkdownUnderlineStartMarker as NSString).length
        let endLength = (appMarkdownUnderlineEndMarker as NSString).length
        var pairs: [AppMarkdownUnderlineMarkerPair] = []
        var searchLocation = 0

        while searchLocation < source.length {
            let searchRange = NSRange(location: searchLocation, length: source.length - searchLocation)
            let startRange = source.range(of: appMarkdownUnderlineStartMarker, options: [], range: searchRange)
            guard startRange.location != NSNotFound else {
                break
            }

            let afterStartLocation = startRange.location + startLength
            let endSearchRange = NSRange(location: afterStartLocation, length: source.length - afterStartLocation)
            let endRange = source.range(of: appMarkdownUnderlineEndMarker, options: [], range: endSearchRange)
            guard endRange.location != NSNotFound else {
                break
            }

            pairs.append(
                AppMarkdownUnderlineMarkerPair(
                    startMarkerRange: startRange,
                    contentRange: NSRange(location: afterStartLocation, length: endRange.location - afterStartLocation),
                    endMarkerRange: endRange
                )
            )
            searchLocation = endRange.location + endLength
        }
        return pairs
    }

    private func removeRange(
        _ nsRange: NSRange,
        from attributedString: inout AttributedString
    ) {
        guard let attributedRange = resolveAttributedRange(for: nsRange, in: attributedString) else {
            return
        }
        attributedString.removeSubrange(attributedRange)
    }

    // Attach composer-style chips after markdown parsing so link/code conflicts are visible in runs.
    private func attachComposerChips(to attributedString: inout AttributedString) {
        guard let composerChipProvider else {
            return
        }

        let initialFlatString = String(attributedString.characters)
        let chips = composerChipProvider(initialFlatString)
            .sorted { $0.range.location > $1.range.location }

        for chip in chips where chip.range.length > 0 {
            guard let attributedRange = resolveAttributedRange(for: chip.range, in: attributedString),
                  !runsConflictWithComposerChip(in: attributedString[attributedRange].runs) else {
                continue
            }
            applyComposerChip(chip, to: &attributedString, at: attributedRange)
        }
    }

    private func resolveAttributedRange(
        for nsRange: NSRange,
        in attributedString: AttributedString
    ) -> Range<AttributedString.Index>? {
        let flatString = String(attributedString.characters)
        guard nsRange.location >= 0,
              nsRange.location + nsRange.length <= (flatString as NSString).length,
              let swiftRange = Range(nsRange, in: flatString),
              let lowerScalar = swiftRange.lowerBound.samePosition(in: flatString.unicodeScalars),
              let upperScalar = swiftRange.upperBound.samePosition(in: flatString.unicodeScalars),
              let lowerAttr = AttributedString.Index(lowerScalar, within: attributedString),
              let upperAttr = AttributedString.Index(upperScalar, within: attributedString) else {
            return nil
        }
        return lowerAttr..<upperAttr
    }

    private func runsConflictWithComposerChip(
        in runs: AttributedString.Runs
    ) -> Bool {
        runs.contains { run in
            if run.link != nil { return true }
            if run.presentationIntent?.components.contains(where: { component in
                if case .codeBlock = component.kind { return true }
                return false
            }) == true {
                return true
            }
            if run.inlinePresentationIntent?.contains(.code) == true { return true }
            return false
        }
    }

    private func applyComposerChip(
        _ chip: AppTextEditorChip,
        to attributedString: inout AttributedString,
        at attributedRange: Range<AttributedString.Index>
    ) {
        let preservedPresentationIntent = attributedString[attributedRange].runs
            .compactMap { $0.presentationIntent }
            .first
        let decodedDisplayText = chip.style == .fileMention
            ? CanonicalPath.decodeStoredMentionPath(chip.displayText)
            : chip.displayText
        let fileMentionURL: URL? = chip.style == .fileMention
            ? fileMentionClickURL(from: attributedString, range: attributedRange)
            : nil

        var replacement = AttributedString(decodedDisplayText)
        replacement.inlinePresentationIntent = .code
        if let preservedPresentationIntent {
            replacement.presentationIntent = preservedPresentationIntent
        }
        if let fileMentionURL {
            replacement.link = fileMentionURL
        }
        attributedString.replaceSubrange(attributedRange, with: replacement)
    }

    private func fileMentionClickURL(
        from attributedString: AttributedString,
        range: Range<AttributedString.Index>
    ) -> URL? {
        let rawText = String(attributedString[range].characters)
        let storedPath = rawText.hasPrefix("@") ? String(rawText.dropFirst()) : rawText
        let decoded = CanonicalPath.decodeStoredMentionPath(storedPath)
        guard !decoded.isEmpty else {
            return nil
        }
        if decoded.hasPrefix("/") || decoded.hasPrefix("~") {
            let expanded = (decoded as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        return URL(string: decoded)
    }
}

private struct AppMarkdownUnderlineMarkerPair {
    let startMarkerRange: NSRange
    let contentRange: NSRange
    let endMarkerRange: NSRange
}
