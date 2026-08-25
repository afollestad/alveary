import Foundation

/// GitHub-flavored markdown allows a small set of raw HTML that the app's markdown
/// renderer prints literally. Rewrites the common tags into markdown equivalents
/// (`<b>` → `**`, `<br>` → newline) and strips the known wrappers (`<p>`, comments).
/// Fenced code blocks pass through untouched so code samples containing HTML stay verbatim.
///
/// **`<details>` and `<summary>` deliberately pass through.** The markdown layer owns them now —
/// `AppMarkdownDetailsSyntaxParser` lifts them into a real collapsible block. Rewriting the summary
/// to bold here would flatten the disclosure back open and hand the reader the long log its author
/// chose to hide.
enum PullRequestMarkdown {
    static func sanitized(_ markdown: String) -> String {
        // Alternate segments: outside/inside fenced code blocks. Only even-indexed
        // (outside) segments are transformed.
        let segments = markdown.components(separatedBy: "```")
        let transformed = segments.enumerated().map { index, segment in
            index.isMultiple(of: 2) ? sanitizeSegment(segment) : segment
        }
        return transformed.joined(separator: "```")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeSegment(_ segment: String) -> String {
        var text = segment
        replace(&text, pattern: "<!--.*?-->", with: "", options: [.dotMatchesLineSeparators])
        replace(&text, pattern: "</?p(\\s[^>]*)?>", with: "\n\n", options: [.caseInsensitive])
        replace(&text, pattern: "<br\\s*/?>", with: "\n", options: [.caseInsensitive])
        replace(&text, pattern: "</?(b|strong)>", with: "**", options: [.caseInsensitive])
        replace(&text, pattern: "</?(i|em)>", with: "*", options: [.caseInsensitive])
        replace(&text, pattern: "</?code>", with: "`", options: [.caseInsensitive])
        // Markdown has no sub/superscript; keep the content, drop the tags.
        replace(&text, pattern: "</?su[bp](\\s[^>]*)?>", with: "", options: [.caseInsensitive])
        replace(&text, pattern: "\n{3,}", with: "\n\n", options: [])
        return hardBreaking(text)
    }

    /// Marks every newline that GitHub would render as a line break, since it renders comment
    /// bodies with hard breaks on. Without this, owner-owl's `r:` and `cc:` lines — separate lines
    /// in the source — reflow into one wrapped paragraph.
    ///
    /// Two trailing spaces is markdown's own hard-break syntax, so Foundation turns each marked
    /// newline into a real `\n` run and both renderers break the line with no further handling.
    /// Only prose is affected: a marker at the end of a table row, list item, or ATX heading leaves
    /// those structures parsing identically, and fenced code never reaches here because
    /// `sanitized(_:)` transforms only the segments outside a fence.
    private static func hardBreaking(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        return lines.enumerated()
            .map { index, line in
                let next = index + 1 < lines.count ? lines[index + 1] : ""
                guard !isBlank(line), !isBlank(next), !endsWithHardBreak(line) else {
                    return line
                }
                return line + "  "
            }
            .joined(separator: "\n")
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func endsWithHardBreak(_ line: String) -> Bool {
        line.hasSuffix("  ") || line.hasSuffix("\\")
    }

    private static func replace(
        _ text: inout String,
        pattern: String,
        with template: String,
        options: NSRegularExpression.Options
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return
        }
        text = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }
}
