import Foundation
import SwiftUI

/// Regex-based syntax highlighter that produces an `AttributedString` suitable for
/// SwiftUI `Text`. It is intentionally lightweight: comments, strings, keywords,
/// numbers, and a few language-specific structural tokens are colored well enough to
/// make code scan quickly, while unknown languages render as plain monospaced text.
enum SyntaxHighlighter {
    static func highlighted(_ source: String, language: String, colorScheme: ColorScheme,
                            preserveLineNumberPrefixes: Bool = false) -> AttributedString {
        var attributed = AttributedString(source)
        let normalizedLanguage = normalizedLanguage(language)
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

private extension SyntaxHighlighter {
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

private extension SyntaxHighlighter {
    static let stringDoubleSingle = [
        #""([^"\\]|\\.)*""#,
        #"'([^'\\]|\\.)*'"#
    ]

    static let stringDoubleOnly = [#""([^"\\]|\\.)*""#]
    static let cLikeComments = [#"//.*$"#, #"/\*[\s\S]*?\*/"#]
    static let cLikeStrings = stringDoubleSingle + [#"'([^'\\]|\\.)'"#]

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

    static let cKeywords = [
        "auto", "break", "case", "char", "const", "continue", "default", "do",
        "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline",
        "int", "long", "register", "restrict", "return", "short", "signed", "sizeof",
        "static", "struct", "switch", "typedef", "union", "unsigned", "void",
        "volatile", "while", "_Bool", "_Complex", "_Imaginary"
    ]

    static let cppKeywords = cKeywords + [
        "alignas", "alignof", "and", "and_eq", "asm", "bitand", "bitor", "bool",
        "catch", "char16_t", "char32_t", "class", "compl", "concept", "constexpr",
        "const_cast", "decltype", "delete", "dynamic_cast", "explicit", "export",
        "false", "friend", "mutable", "namespace", "new", "noexcept", "not",
        "not_eq", "nullptr", "operator", "or", "or_eq", "private", "protected",
        "public", "reinterpret_cast", "requires", "static_assert", "static_cast",
        "template", "this", "thread_local", "throw", "true", "try", "typename",
        "using", "virtual", "xor", "xor_eq"
    ]

    static let objectiveCKeywords = cKeywords + [
        "id", "instancetype", "nil", "Nil", "NULL", "YES", "NO", "self", "super",
        "atomic", "nonatomic", "strong", "weak", "copy", "assign", "readonly",
        "readwrite", "nullable", "nonnull"
    ]

    static let sqlKeywords = [
        "select", "from", "where", "join", "inner", "left", "right", "full", "outer",
        "on", "group", "by", "order", "having", "limit", "offset", "insert", "into",
        "values", "update", "set", "delete", "create", "alter", "drop", "table",
        "view", "index", "primary", "key", "foreign", "references", "constraint",
        "and", "or", "not", "null", "is", "in", "exists", "case", "when", "then",
        "else", "end", "as", "distinct", "union", "all", "with", "recursive",
        "transaction", "begin", "commit", "rollback", "returning", "true", "false"
    ]

    static let languageAliases: [String: String] = [
        "js": "javascript", "mjs": "javascript", "cjs": "javascript",
        "ts": "typescript", "jsx": "jsx", "tsx": "tsx",
        "sh": "bash", "zsh": "bash", "shell": "bash",
        "yml": "yaml",
        "md": "markdown",
        "m": "objectivec", "mm": "objectivec", "objc": "objectivec", "objective-c": "objectivec", "obj-c": "objectivec",
        "c++": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hxx": "cpp",
        "htm": "html",
        "plist": "xml"
    ]

    static let languageSpecs: [String: LanguageSpec] = [
        "swift": LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: stringDoubleOnly,
            keywords: swiftKeywords,
            annotationPattern: #"@[A-Za-z_][A-Za-z0-9_]*"#
        ),
        "python": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: [
                #"\"\"\"[\s\S]*?\"\"\""#,
                #"'''[\s\S]*?'''"#,
                #""([^"\\]|\\.)*""#,
                #"'([^'\\]|\\.)*'"#
            ],
            keywords: pythonKeywords,
            annotationPattern: #"@[A-Za-z_][A-Za-z0-9_]*"#
        ),
        "javascript": jsSpec(),
        "typescript": jsSpec(),
        "jsx": jsSpec(),
        "tsx": jsSpec(),
        "json": LanguageSpec(
            commentPatterns: [],
            stringPatterns: [#""([^"\\]|\\.)*""#],
            keywords: ["true", "false", "null"],
            extraKeywordPatterns: [#""([^"\\]|\\.)*"\s*(?=:)"#]
        ),
        "bash": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: [#""([^"\\]|\\.)*""#, #"'[^']*'"#],
            keywords: bashKeywords,
            extraKeywordPatterns: [#"\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*"#]
        ),
        "ruby": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: stringDoubleSingle,
            keywords: rubyKeywords,
            extraKeywordPatterns: [#":[A-Za-z_][A-Za-z0-9_]*"#]
        ),
        "go": LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: [#"`[^`]*`"#, #""([^"\\]|\\.)*""#],
            keywords: goKeywords
        ),
        "rust": LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: stringDoubleOnly,
            keywords: rustKeywords,
            annotationPattern: #"#\[[\s\S]*?\]"#
        ),
        "kotlin": jvmSpec(),
        "java": jvmSpec(),
        "yaml": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: [#""([^"\\]|\\.)*""#, #"'[^']*'"#],
            keywords: ["true", "false", "null", "~"],
            extraKeywordPatterns: [#"^[\s-]*([A-Za-z_][A-Za-z0-9_-]*)\s*:"#]
        ),
        "c": cSpec(keywords: cKeywords),
        "cpp": cSpec(keywords: cppKeywords),
        "objectivec": cSpec(
            keywords: objectiveCKeywords,
            annotationPattern: #"@[A-Za-z_][A-Za-z0-9_]*"#
        ),
        "html": markupSpec(),
        "xml": markupSpec(),
        "css": LanguageSpec(
            commentPatterns: [#"/\*[\s\S]*?\*/"#],
            stringPatterns: stringDoubleSingle,
            keywords: ["important", "inherit", "initial", "unset", "revert"],
            extraKeywordPatterns: [
                #"@[A-Za-z-]+"#,
                #"(^|[;\{\s])[-A-Za-z_][-\w]*\s*(?=:)"#,
                #"#[0-9A-Fa-f]{3,8}\b"#,
                #"\b[-A-Za-z_][-\w]*(?=\()"#
            ],
            symbolPatterns: [#"[{}();:,]"#],
            numberPattern: #"\b-?\d+(\.\d+)?(px|em|rem|vh|vw|%|s|ms|deg)?\b"#
        ),
        "sql": LanguageSpec(
            commentPatterns: [#"--.*$"#, #"/\*[\s\S]*?\*/"#],
            stringPatterns: [#"'([^'\\]|\\.|'')*'"#, #""([^"\\]|\\.)*""#, #"`[^`]*`"#],
            keywords: sqlKeywords,
            extraKeywordPatterns: [#"\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\()"#]
        ),
        "toml": LanguageSpec(
            commentPatterns: ["#.*$"],
            stringPatterns: [
                #"\"\"\"[\s\S]*?\"\"\""#,
                #"'''[\s\S]*?'''"#,
                #""([^"\\]|\\.)*""#,
                #"'[^']*'"#
            ],
            keywords: ["true", "false"],
            extraKeywordPatterns: [
                #"^\s*\[+[^\]]+\]+"#,
                #"(^|\s)[A-Za-z0-9_.-]+\s*(?==)"#,
                #"\b\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})?)?\b"#
            ]
        ),
        "markdown": LanguageSpec(
            commentPatterns: [],
            stringPatterns: [#"`{1,3}[\s\S]*?`{1,3}"#],
            keywords: [],
            extraKeywordPatterns: [
                #"^\s{0,3}#{1,6}\s+.+"#,
                #"^\s{0,3}>\s?"#,
                #"^\s*([-*+]|\d+\.)\s+"#,
                #"\[[^\]]+\]\([^)]+\)"#,
                #"\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?"#
            ],
            symbolPatterns: [#"[*_~>#|\[\]()`-]"#]
        )
    ]

    static func jsSpec() -> LanguageSpec {
        LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: stringDoubleSingle + [#"`([^`\\]|\\.)*`"#],
            keywords: javascriptKeywords
        )
    }

    static func jvmSpec() -> LanguageSpec {
        LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: stringDoubleOnly,
            keywords: jvmKeywords,
            annotationPattern: #"@[A-Za-z_][A-Za-z0-9_]*"#
        )
    }

    static func cSpec(
        keywords: [String],
        annotationPattern: String? = nil
    ) -> LanguageSpec {
        LanguageSpec(
            commentPatterns: cLikeComments,
            stringPatterns: cLikeStrings,
            keywords: keywords,
            annotationPattern: annotationPattern,
            extraKeywordPatterns: [#"^\s*#\s*[A-Za-z_][A-Za-z0-9_]*"#]
        )
    }

    static func markupSpec() -> LanguageSpec {
        LanguageSpec(
            commentPatterns: [#"<!--[\s\S]*?-->"#],
            stringPatterns: stringDoubleSingle,
            keywords: [],
            extraKeywordPatterns: [
                #"</?[A-Za-z_][A-Za-z0-9:._-]*"#,
                #"\s[A-Za-z_:][A-Za-z0-9:._-]*(?=\s*=)"#,
                #"&[A-Za-z0-9#]+;"#,
                #"<!DOCTYPE[\s\S]*?>"#,
                #"<\?xml[\s\S]*?\?>"#
            ],
            symbolPatterns: [#"[<>/=]"#]
        )
    }
}

private extension [NSRange] {
    func intersects(_ range: NSRange) -> Bool {
        contains { NSIntersectionRange($0, range).length > 0 }
    }
}
