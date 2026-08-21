import Foundation

/// The HTML half of `AppMarkdownParser`'s source preprocessing: what each tag markdown can express
/// becomes, what the rest is dropped as, and the code-range filter every one of those rewrites runs
/// through. Split out of `AppMarkdownParser.swift` to keep that file inside its length limit.
///
/// Rewriting happens on *source text*, before Foundation parses it, because Foundation's parser has
/// no HTML intent to hook — it prints an unrecognized tag as literal characters.
extension AppMarkdownParser {
    /// Drops the tags markdown cannot express, keeping the text they wrapped.
    ///
    /// Runs last of the tag rewrites, so a tag this would delete has already had its chance to
    /// become markdown. `AppMarkdownHTMLElements` owns both lists, and owns why this matches named
    /// elements rather than any `<…>`.
    func markdownByDroppingUnhandledHTMLTags(in input: String) -> String {
        // Every parse reaches here, and most markdown carries no angle bracket at all. Without
        // this the run would spend a regex and a full code-range scan to find nothing.
        guard input.contains("<") else {
            return input
        }
        return replacingMatchesOutsideCode(
            pattern: AppMarkdownHTMLElements.droppedTagPattern,
            in: input
        ) { source, match in
            let name = source.substring(with: match.range(at: 1)).lowercased()
            return AppMarkdownHTMLElements.blockLevel.contains(name) ? "\n\n" : ""
        }
    }

    /// Collapses a disclosure into a bold summary above an always-visible body.
    ///
    /// This is the pre-disclosure rendering, kept as the fallback for every surface that
    /// renders `AppMarkdownDocument.content` rather than its blocks, and for markup the
    /// splitter rejects. Rewriting `<summary>` before dropping the wrapper tags is what keeps
    /// the summary text from merging into the first body paragraph.
    ///
    /// It drops every tag `AppMarkdownDetailsSyntaxParser` claims, not just `<details>` — a tag the
    /// splitter lifts on the block path but this leaves behind would print its own angle brackets
    /// on every inline surface.
    func markdownByFlatteningDisclosures(in input: String) -> String {
        var output = replacingMatchesOutsideCode(
            pattern: #"<summary(?:\s[^>]*)?>([\s\S]*?)</summary>"#,
            in: input
        ) { source, match in
            let summary = source.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? "" : "\n\n**\(summary)**\n\n"
        }
        let disclosureTags = AppMarkdownDetailsSyntaxParser.disclosureTagNames.joined(separator: "|")
        output = replacingMatchesOutsideCode(
            pattern: "</?(\(disclosureTags))(?:\\s[^>]*)?>",
            in: output
        ) { _, _ in
            "\n\n"
        }
        return output
    }

    func replacingHTMLPairTags(
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

    func replacingMatchesOutsideCode(
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
}
