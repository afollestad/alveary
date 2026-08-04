import Foundation
import SwiftUI

/// Regex-based syntax highlighter that produces an `AttributedString` suitable for
/// SwiftUI `Text`. It is intentionally lightweight: comments, strings, keywords,
/// numbers, and a few language-specific structural tokens are colored well enough to
/// make code scan quickly, while unknown languages render as plain monospaced text.
enum SyntaxHighlighter {
    static func highlighted(_ source: String, language: String, colorScheme: ColorScheme,
                            preserveLineNumberPrefixes: Bool = false) -> AttributedString {
        let normalizedLanguage = normalizedLanguage(language)
        // Line-numbered tool output is never a diff, and its `-`-prefixed content would be read as
        // deletions, so an explicit language is the only way it can reach the diff path.
        if !preserveLineNumberPrefixes || DiffCodeHighlighting.languageNames.contains(normalizedLanguage),
           DiffCodeHighlighting.rendersAsDiff(
               language: normalizedLanguage,
               isRecognizedLanguage: recognizesLanguage(normalizedLanguage),
               source: source
           ) {
            return DiffCodeHighlighting.highlighted(source, colorScheme: colorScheme)
        }

        var attributed = AttributedString(source)
        guard let spec = languageSpecs[normalizedLanguage], !source.isEmpty else {
            attributed.foregroundColor = Palette(for: colorScheme).base
            return attributed
        }

        let palette = Palette(for: colorScheme)
        attributed.foregroundColor = palette.base

        var protectedRanges: [NSRange] = []
        let protectedMatches = spec.protectedRules(palette: palette)
            .flatMap { matches(for: $0, in: source) }
            .sorted { lhs, rhs in
                if lhs.range.location == rhs.range.location {
                    return lhs.range.length > rhs.range.length
                }
                return lhs.range.location < rhs.range.location
            }

        for match in protectedMatches where !protectedRanges.intersects(match.range) {
            apply(match.color, to: match.range, in: source, attributed: &attributed)
            protectedRanges.append(match.range)
        }

        for rule in spec.nonProtectedRules(palette: palette) {
            for match in matches(for: rule, in: source) where !protectedRanges.intersects(match.range) {
                apply(match.color, to: match.range, in: source, attributed: &attributed)
            }
        }

        if preserveLineNumberPrefixes {
            applyBaseColorToLeadingLineNumberPrefixes(in: source, palette: palette, attributed: &attributed)
        }

        return attributed
    }

    /// Whether the highlighter has token rules for a normalized language name. Diff rendering asks
    /// so an unlabeled block can be sniffed without stealing a language that highlights properly.
    static func recognizesLanguage(_ normalizedLanguage: String) -> Bool {
        languageSpecs[normalizedLanguage] != nil
    }

    static func normalizedLanguage(_ language: String) -> String {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return languageAliases[normalized] ?? normalized
    }

    private static func matches(for rule: Rule, in source: String) -> [TokenMatch] {
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
            return []
        }
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        return regex.matches(in: source, options: [], range: fullRange)
            .map { match in
                TokenMatch(range: match.range, color: rule.color)
            }
    }

    private static func apply(
        _ color: Color,
        to nsRange: NSRange,
        in source: String,
        attributed: inout AttributedString
    ) {
        guard let range = attributedRange(for: nsRange, source: source, in: attributed) else {
            return
        }
        attributed[range].foregroundColor = color
    }

    private static func attributedRange(
        for nsRange: NSRange,
        source: String,
        in attributed: AttributedString
    ) -> Range<AttributedString.Index>? {
        guard nsRange.location >= 0,
              nsRange.location + nsRange.length <= (source as NSString).length,
              let swiftRange = Range(nsRange, in: source),
              let lowerScalar = swiftRange.lowerBound.samePosition(in: source.unicodeScalars),
              let upperScalar = swiftRange.upperBound.samePosition(in: source.unicodeScalars),
              let lower = AttributedString.Index(lowerScalar, within: attributed),
              let upper = AttributedString.Index(upperScalar, within: attributed) else {
            return nil
        }
        return lower..<upper
    }

    private static func applyBaseColorToLeadingLineNumberPrefixes(
        in source: String,
        palette: Palette,
        attributed: inout AttributedString
    ) {
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        let regex = try? NSRegularExpression(pattern: #"^\s*\d+(\t| +)"#, options: [.anchorsMatchLines])
        regex?.matches(in: source, options: [], range: fullRange).forEach {
            apply(palette.base, to: $0.range, in: source, attributed: &attributed)
        }
    }
}
private struct TokenMatch {
    let range: NSRange
    let color: Color
}

extension SyntaxHighlighter {
    struct Rule {
        let pattern: String
        let options: NSRegularExpression.Options
        let color: Color
    }

    struct Palette {
        let base: Color
        let keyword: Color
        let string: Color
        let comment: Color
        let number: Color
        let symbol: Color

        init(for colorScheme: ColorScheme) {
            base = .primary
            switch colorScheme {
            case .dark:
                keyword = Color(red: 0.64, green: 0.74, blue: 1.0)
                string = Color(red: 0.98, green: 0.72, blue: 0.68)
                comment = Color(red: 0.53, green: 0.57, blue: 0.60)
                number = Color(red: 0.82, green: 0.82, blue: 0.88)
                symbol = Color(red: 0.74, green: 0.78, blue: 0.86)
            default:
                keyword = Color(red: 0.64, green: 0.08, blue: 0.50)
                string = Color(red: 0.77, green: 0.10, blue: 0.10)
                comment = Color(red: 0.25, green: 0.45, blue: 0.12)
                number = Color(red: 0.10, green: 0.31, blue: 0.60)
                symbol = Color(red: 0.33, green: 0.36, blue: 0.42)
            }
        }
    }

    struct LanguageSpec {
        let commentPatterns: [String]
        let stringPatterns: [String]
        let keywords: [String]
        let annotationPattern: String?
        let extraKeywordPatterns: [String]
        let symbolPatterns: [String]
        let numberPattern: String

        init(
            commentPatterns: [String],
            stringPatterns: [String],
            keywords: [String],
            annotationPattern: String? = nil,
            extraKeywordPatterns: [String] = [],
            symbolPatterns: [String] = [],
            numberPattern: String = #"\b-?\d+(\.\d+)?\b"#
        ) {
            self.commentPatterns = commentPatterns
            self.stringPatterns = stringPatterns
            self.keywords = keywords
            self.annotationPattern = annotationPattern
            self.extraKeywordPatterns = extraKeywordPatterns
            self.symbolPatterns = symbolPatterns
            self.numberPattern = numberPattern
        }

        func protectedRules(palette: Palette) -> [Rule] {
            stringPatterns.map { Rule(pattern: $0, options: [.anchorsMatchLines], color: palette.string) }
                + commentPatterns.map { Rule(pattern: $0, options: [.anchorsMatchLines], color: palette.comment) }
        }

        func nonProtectedRules(palette: Palette) -> [Rule] {
            var rules: [Rule] = []
            if let annotationPattern {
                rules.append(Rule(pattern: annotationPattern, options: [.anchorsMatchLines], color: palette.keyword))
            }
            if !keywords.isEmpty {
                let escapedKeywords = keywords
                    .map(NSRegularExpression.escapedPattern(for:))
                    .joined(separator: "|")
                rules.append(
                    Rule(
                        pattern: #"\b("# + escapedKeywords + #")\b"#,
                        options: [.caseInsensitive],
                        color: palette.keyword
                    )
                )
            }
            for pattern in extraKeywordPatterns {
                rules.append(Rule(pattern: pattern, options: [.anchorsMatchLines, .caseInsensitive], color: palette.keyword))
            }
            for pattern in symbolPatterns {
                rules.append(Rule(pattern: pattern, options: [.anchorsMatchLines], color: palette.symbol))
            }
            rules.append(Rule(pattern: numberPattern, options: [.caseInsensitive], color: palette.number))
            return rules
        }
    }
}

private extension [NSRange] {
    func intersects(_ range: NSRange) -> Bool {
        contains { NSIntersectionRange($0, range).length > 0 }
    }
}
