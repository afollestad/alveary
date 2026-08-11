import Foundation

/// GitHub-flavored markdown allows a small set of raw HTML that the app's markdown
/// renderer prints literally. Rewrites the common tags into markdown equivalents
/// (`<summary>` → bold, `<b>` → `**`, `<br>` → newline) and strips the known
/// wrappers (`<details>`, `<p>`, comments). Fenced code blocks pass through
/// untouched so code samples containing HTML stay verbatim.
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
        replace(
            &text,
            pattern: "<summary(\\s[^>]*)?>(.*?)</summary>",
            with: "**$2**\n",
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )
        replace(&text, pattern: "</?details(\\s[^>]*)?>", with: "\n", options: [.caseInsensitive])
        replace(&text, pattern: "</?p(\\s[^>]*)?>", with: "\n\n", options: [.caseInsensitive])
        replace(&text, pattern: "<br\\s*/?>", with: "\n", options: [.caseInsensitive])
        replace(&text, pattern: "</?(b|strong)>", with: "**", options: [.caseInsensitive])
        replace(&text, pattern: "</?(i|em)>", with: "*", options: [.caseInsensitive])
        replace(&text, pattern: "</?code>", with: "`", options: [.caseInsensitive])
        // Markdown has no sub/superscript; keep the content, drop the tags.
        replace(&text, pattern: "</?su[bp](\\s[^>]*)?>", with: "", options: [.caseInsensitive])
        replace(&text, pattern: "\n{3,}", with: "\n\n", options: [])
        return text
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
