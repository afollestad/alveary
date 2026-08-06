import Foundation

/// Memoizes the inline-parsing step the single-line label family shares.
///
/// Every one of those surfaces re-derives its content on each `body` evaluation (and each
/// AppKit reconfigure), so a list whose rows carry backticked titles re-parses every visible
/// title on every render pass. The strings are stable and small, which makes them ideal cache
/// keys — the pull request list re-renders far more often than its titles change.
///
/// `nil` means "no inline markdown here": callers keep their own plain-string fallbacks
/// because each renderer styles a plain string differently.
enum AppMarkdownInlineParseCache {
    nonisolated(unsafe) private static let cache: NSCache<NSString, AppMarkdownInlineParseBox> = {
        let cache = NSCache<NSString, AppMarkdownInlineParseBox>()
        cache.countLimit = 512
        return cache
    }()

    static func parsedInline(for markdown: String) -> AttributedString? {
        // Cheaper than a cache probe, and true for the majority of strings reaching here.
        // It also implies `appMarkdownCompactDisplaySource` is the identity, because a tag
        // needs the `<` this scans for — so a plain answer is safe for the raw string.
        guard appMarkdownMayContainInlineMarkdown(markdown) else {
            return nil
        }
        let key = markdown as NSString
        if let cached = cache.object(forKey: key) {
            return cached.parsed
        }

        let parser = AppMarkdownParser(parsingMode: .inline)
        guard let parsed = try? parser.attributedString(
            for: appMarkdownCompactDisplaySource(from: markdown)
        ) else {
            return nil
        }
        cache.setObject(AppMarkdownInlineParseBox(parsed), forKey: key, cost: markdown.count)
        return parsed
    }
}

/// Cheap pre-filter so plain strings never reach the parser — or the cache. The vast
/// majority of the strings these labels render carry no markdown at all.
private func appMarkdownMayContainInlineMarkdown(_ markdown: String) -> Bool {
    markdown.contains { character in
        switch character {
        case "`", "[", "*", "_", "<", "!", "\\":
            return true
        default:
            return false
        }
    }
}

private final class AppMarkdownInlineParseBox: NSObject {
    let parsed: AttributedString

    init(_ parsed: AttributedString) {
        self.parsed = parsed
    }
}
