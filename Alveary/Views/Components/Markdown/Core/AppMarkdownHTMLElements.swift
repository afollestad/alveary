import Foundation

/// The HTML element names `AppMarkdownParser` drops, keeping the text they wrapped.
///
/// GitHub renders a small subset of raw HTML; Foundation's markdown parser renders none of it and
/// prints the tags as literal text. The parser rewrites what it can express in markdown — and
/// `AppMarkdownImages` claims `<img>`, which must never reach these lists because a void element
/// has no text to keep, so dropping it would delete the picture. Everything left over is named
/// here, from GitHub's own allowlist.
///
/// **These are element names, never a `</?[a-z][^>]*>` catch-all.** A generic tag pattern also
/// matches `Array<String>`, `Vec<T>`, and `<Foo>` written in prose, and deleting those loses content
/// rather than preserving it — the opposite of what `Core/AGENTS.md` requires of an unknown-markup
/// fallback.
enum AppMarkdownHTMLElements {
    /// Dropped in favour of a paragraph break, so what they wrapped still reads as its own block.
    static let blockLevel: Set<String> = [
        "blockquote", "caption", "dd", "div", "dl", "dt", "figcaption", "figure",
        "h1", "h2", "h3", "h4", "h5", "h6", "hr", "li", "ol", "pre",
        "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul"
    ]

    /// Dropped outright, leaving their text in the run it was already part of.
    static let inline: Set<String> = [
        "abbr", "bdo", "cite", "del", "dfn", "ins", "kbd", "mark", "q", "rp", "rt",
        "ruby", "s", "samp", "small", "span", "strike", "sub", "sup", "time", "tt",
        "var", "wbr"
    ]

    /// One pattern for both lists, so a parse spends a single regex and a single code-range scan
    /// rather than one of each per list. Longest name first: the alternation would still backtrack
    /// its way from `s` to `small`, but only after failing the shorter branch at every `<s…` tag.
    static let droppedTagPattern: String = {
        let names = blockLevel.union(inline).sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        return "</?(\(names.joined(separator: "|")))(?:\\s[^>]*)?/?>"
    }()
}
