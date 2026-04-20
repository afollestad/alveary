@preconcurrency import AppKit
import Foundation
import SwiftUI

/// Regex-based syntax highlighter that produces an `AttributedString` suitable for
/// SwiftUI `Text`. Intentionally lightweight — it colours keywords, strings, numbers,
/// and comments for a handful of common languages, and falls back to plain text for
/// anything else. Good enough to make tool output scan like code; not a full parser.
enum SyntaxHighlighter {
    static func highlighted(
        _ source: String,
        language: String,
        colorScheme: ColorScheme
    ) -> AttributedString {
        let palette = Palette(for: colorScheme)
        let rules = rules(for: language, palette: palette)

        let mutable = NSMutableAttributedString(string: source, attributes: [
            .foregroundColor: palette.base
        ])

        guard !rules.isEmpty else {
            return AttributedString(mutable)
        }

        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }
            regex.enumerateMatches(in: source, options: [], range: fullRange) { match, _, _ in
                guard let match else {
                    return
                }
                mutable.addAttribute(.foregroundColor, value: rule.color, range: match.range)
            }
        }

        return AttributedString(mutable)
    }
}

private extension SyntaxHighlighter {
    struct Rule {
        let pattern: String
        let options: NSRegularExpression.Options
        let color: NSColor
    }

    struct Palette {
        let base: NSColor
        let keyword: NSColor
        let string: NSColor
        let comment: NSColor
        let number: NSColor

        init(for colorScheme: ColorScheme) {
            base = NSColor.labelColor
            switch colorScheme {
            case .dark:
                keyword = NSColor(srgbRed: 0.64, green: 0.74, blue: 1.0, alpha: 1.0)
                string = NSColor(srgbRed: 0.98, green: 0.72, blue: 0.68, alpha: 1.0)
                comment = NSColor(srgbRed: 0.53, green: 0.57, blue: 0.60, alpha: 1.0)
                number = NSColor(srgbRed: 0.82, green: 0.82, blue: 0.88, alpha: 1.0)
            default:
                keyword = NSColor(srgbRed: 0.64, green: 0.08, blue: 0.50, alpha: 1.0)
                string = NSColor(srgbRed: 0.77, green: 0.10, blue: 0.10, alpha: 1.0)
                comment = NSColor(srgbRed: 0.25, green: 0.45, blue: 0.12, alpha: 1.0)
                number = NSColor(srgbRed: 0.10, green: 0.31, blue: 0.60, alpha: 1.0)
            }
        }
    }

    static func rules(for language: String, palette: Palette) -> [Rule] {
        guard let spec = languageSpecs[language] else {
            return []
        }
        return spec.rules(palette: palette)
    }
}

private extension SyntaxHighlighter {
    struct LanguageSpec {
        let commentPatterns: [String]
        let stringPatterns: [String]
        let keywords: [String]
        let annotationPattern: String?
        let extraKeywordPatterns: [String]

        func rules(palette: Palette) -> [Rule] {
            var rules: [Rule] = []
            for pattern in commentPatterns {
                rules.append(Rule(pattern: pattern, options: [.anchorsMatchLines], color: palette.comment))
            }
            for pattern in stringPatterns {
                rules.append(Rule(pattern: pattern, options: [], color: palette.string))
            }
            if let annotationPattern {
                rules.append(Rule(pattern: annotationPattern, options: [], color: palette.keyword))
            }
            if !keywords.isEmpty {
                let joined = keywords.joined(separator: "|")
                rules.append(Rule(pattern: "\\b(\(joined))\\b", options: [], color: palette.keyword))
            }
            for pattern in extraKeywordPatterns {
                rules.append(Rule(pattern: pattern, options: [], color: palette.keyword))
            }
            rules.append(Rule(pattern: "\\b-?\\d+(\\.\\d+)?\\b", options: [], color: palette.number))
            return rules
        }
    }

    static let stringDoubleSingle = [
        "\"([^\"\\\\]|\\\\.)*\"",
        "'([^'\\\\]|\\\\.)*'"
    ]

    static let stringDoubleOnly = ["\"([^\"\\\\]|\\\\.)*\""]

    static let swiftKeywords = [
        "func", "var", "let", "if", "else", "for", "while", "guard", "return",
        "class", "struct", "enum", "protocol", "import", "extension", "public",
        "private", "internal", "static", "final", "override", "init", "self",
        "Self", "throws", "throw", "try", "catch", "do", "in", "as", "is", "nil",
        "true", "false", "where", "case", "switch", "break", "continue", "default",
        "typealias", "associatedtype", "lazy", "weak", "strong", "unowned",
        "mutating", "nonmutating", "fileprivate", "open", "some", "any",
        "async", "await", "defer", "repeat", "required", "convenience", "inout",
        "subscript", "operator", "precedencegroup"
    ]

    static let pythonKeywords = [
        "def", "class", "if", "elif", "else", "for", "while", "return", "import",
        "from", "as", "try", "except", "finally", "raise", "with", "in", "is",
        "not", "and", "or", "True", "False", "None", "lambda", "pass", "break",
        "continue", "yield", "global", "nonlocal", "async", "await", "del", "assert"
    ]

    static let javascriptKeywords = [
        "function", "var", "let", "const", "if", "else", "for", "while", "return",
        "class", "extends", "import", "export", "from", "as", "try", "catch",
        "finally", "throw", "switch", "case", "default", "break", "continue",
        "new", "this", "super", "typeof", "instanceof", "in", "of", "null",
        "undefined", "true", "false", "async", "await", "yield", "interface",
        "type", "enum", "namespace", "readonly", "public", "private", "protected",
        "static", "abstract"
    ]

    static let bashKeywords = [
        "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case",
        "esac", "in", "function", "return", "exit", "break", "continue", "export",
        "local", "readonly"
    ]

    static let rubyKeywords = [
        "def", "end", "class", "module", "if", "elsif", "else", "unless", "for",
        "while", "until", "do", "return", "require", "require_relative", "include",
        "extend", "begin", "rescue", "ensure", "raise", "yield", "lambda", "proc",
        "self", "nil", "true", "false", "and", "or", "not", "in", "when", "case",
        "then", "break", "next", "redo", "retry", "super"
    ]

    static let goKeywords = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else",
        "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
        "map", "package", "range", "return", "select", "struct", "switch", "type",
        "var", "true", "false", "nil", "iota"
    ]

    static let rustKeywords = [
        "as", "async", "await", "break", "const", "continue", "crate", "dyn",
        "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let",
        "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self",
        "Self", "static", "struct", "super", "trait", "true", "type", "union",
        "unsafe", "use", "where", "while"
    ]

    static let jvmKeywords = [
        "abstract", "as", "break", "case", "catch", "class", "companion", "const",
        "continue", "crossinline", "data", "default", "do", "else", "enum",
        "extends", "final", "finally", "for", "fun", "if", "implements", "import",
        "in", "infix", "inline", "inner", "interface", "internal", "is",
        "lateinit", "new", "null", "object", "open", "operator", "out", "override",
        "package", "private", "protected", "public", "reified", "return", "sealed",
        "static", "super", "suspend", "switch", "synchronized", "this", "throw",
        "throws", "transient", "true", "try", "typealias", "val", "var", "void",
        "volatile", "when", "while", "yield"
    ]

    static let languageSpecs: [String: LanguageSpec] = [
        "swift": LanguageSpec(
            commentPatterns: ["//.*$", "/\\*[\\s\\S]*?\\*/"],
            stringPatterns: stringDoubleOnly,
            keywords: swiftKeywords,
            annotationPattern: "@[A-Za-z_][A-Za-z0-9_]*",
            extraKeywordPatterns: []
        ),
        "python": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: [
                "\"\"\"[\\s\\S]*?\"\"\"",
                "'''[\\s\\S]*?'''",
                "\"([^\"\\\\]|\\\\.)*\"",
                "'([^'\\\\]|\\\\.)*'"
            ],
            keywords: pythonKeywords,
            annotationPattern: nil,
            extraKeywordPatterns: []
        ),
        "javascript": jsSpec(),
        "typescript": jsSpec(),
        "jsx": jsSpec(),
        "tsx": jsSpec(),
        "json": LanguageSpec(
            commentPatterns: [],
            stringPatterns: ["\"([^\"\\\\]|\\\\.)*\""],
            keywords: ["true", "false", "null"],
            annotationPattern: nil,
            extraKeywordPatterns: ["\"([^\"\\\\]|\\\\.)*\"\\s*(?=:)"]
        ),
        "bash": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: ["\"([^\"\\\\]|\\\\.)*\"", "'[^']*'"],
            keywords: bashKeywords,
            annotationPattern: nil,
            extraKeywordPatterns: ["\\$\\{[^}]+\\}|\\$[A-Za-z_][A-Za-z0-9_]*"]
        ),
        "ruby": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: stringDoubleSingle,
            keywords: rubyKeywords,
            annotationPattern: nil,
            extraKeywordPatterns: [":[A-Za-z_][A-Za-z0-9_]*"]
        ),
        "go": LanguageSpec(
            commentPatterns: ["//.*$", "/\\*[\\s\\S]*?\\*/"],
            stringPatterns: ["`[^`]*`", "\"([^\"\\\\]|\\\\.)*\""],
            keywords: goKeywords,
            annotationPattern: nil,
            extraKeywordPatterns: []
        ),
        "rust": LanguageSpec(
            commentPatterns: ["//.*$", "/\\*[\\s\\S]*?\\*/"],
            stringPatterns: stringDoubleOnly,
            keywords: rustKeywords,
            annotationPattern: nil,
            extraKeywordPatterns: []
        ),
        "kotlin": jvmSpec(),
        "java": jvmSpec(),
        "yaml": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: ["\"([^\"\\\\]|\\\\.)*\"", "'[^']*'"],
            keywords: ["true", "false", "null", "~"],
            annotationPattern: nil,
            extraKeywordPatterns: ["^[\\s-]*([A-Za-z_][A-Za-z0-9_-]*)\\s*:"]
        )
    ]

    static func jsSpec() -> LanguageSpec {
        LanguageSpec(
            commentPatterns: ["//.*$", "/\\*[\\s\\S]*?\\*/"],
            stringPatterns: stringDoubleSingle + ["`([^`\\\\]|\\\\.)*`"],
            keywords: javascriptKeywords,
            annotationPattern: nil,
            extraKeywordPatterns: []
        )
    }

    static func jvmSpec() -> LanguageSpec {
        LanguageSpec(
            commentPatterns: ["//.*$", "/\\*[\\s\\S]*?\\*/"],
            stringPatterns: stringDoubleOnly,
            keywords: jvmKeywords,
            annotationPattern: "@[A-Za-z_][A-Za-z0-9_]*",
            extraKeywordPatterns: []
        )
    }
}
