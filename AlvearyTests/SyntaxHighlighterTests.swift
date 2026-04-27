import SwiftUI
import XCTest

@testable import Alveary

final class SyntaxHighlighterTests: XCTestCase {
    func testHighlightsEverySupportedLanguageFixture() {
        for fixture in languageFixtures {
            let highlighted = SyntaxHighlighter.highlighted(
                fixture.source,
                language: fixture.language,
                colorScheme: .light
            )

            XCTAssertGreaterThan(
                runCount(in: highlighted),
                1,
                "Expected \(fixture.language) to produce highlighted runs."
            )
        }
    }

    func testUnknownLanguageFallsBackToPlainCode() {
        let highlighted = SyntaxHighlighter.highlighted(
            "plain text with 123",
            language: "made-up-language",
            colorScheme: .light
        )

        XCTAssertEqual(String(highlighted.characters), "plain text with 123")
        XCTAssertEqual(runCount(in: highlighted), 1)
    }

    func testNormalizesCommonAliases() {
        XCTAssertEqual(SyntaxHighlighter.normalizedLanguage("js"), "javascript")
        XCTAssertEqual(SyntaxHighlighter.normalizedLanguage("ts"), "typescript")
        XCTAssertEqual(SyntaxHighlighter.normalizedLanguage("sh"), "bash")
        XCTAssertEqual(SyntaxHighlighter.normalizedLanguage("yml"), "yaml")
        XCTAssertEqual(SyntaxHighlighter.normalizedLanguage("md"), "markdown")
        XCTAssertEqual(SyntaxHighlighter.normalizedLanguage("mm"), "objectivec")
        XCTAssertEqual(SyntaxHighlighter.normalizedLanguage("objective-c"), "objectivec")
        XCTAssertEqual(SyntaxHighlighter.normalizedLanguage("c++"), "cpp")
        XCTAssertEqual(SyntaxHighlighter.normalizedLanguage("htm"), "html")
        XCTAssertEqual(SyntaxHighlighter.normalizedLanguage("plist"), "xml")
    }

    private func runCount(in attributed: AttributedString) -> Int {
        attributed.runs.reduce(0) { count, _ in count + 1 }
    }
}

private struct SyntaxFixture {
    let language: String
    let source: String
}

private let languageFixtures: [SyntaxFixture] = [
    .init(language: "swift", source: #"let value = "hello" // comment"#),
    .init(language: "python", source: #"def run(): return "hello" 42 # comment"#),
    .init(language: "javascript", source: #"const value = "hello"; // comment"#),
    .init(language: "typescript", source: #"interface User { name: string }"#),
    .init(language: "json", source: #"{"enabled": true, "count": 2}"#),
    .init(language: "bash", source: #"if [ "$value" = 1 ]; then echo "$HOME"; fi"#),
    .init(language: "ruby", source: #"def run; puts "hello"; end # comment"#),
    .init(language: "go", source: #"func main() { var count = 2 } // comment"#),
    .init(language: "rust", source: #"fn main() { let value = "hello"; } // comment"#),
    .init(language: "kotlin", source: #"fun main() { val value = "hello" }"#),
    .init(language: "java", source: #"class Main { public static void main(String[] args) {} }"#),
    .init(language: "yaml", source: #"enabled: true # comment"#),
    .init(language: "c", source: #"#include <stdio.h>\nint main(void) { return 0; }"#),
    .init(language: "cpp", source: #"template <typename T> class Box { public: T value; }"#),
    .init(language: "objectivec", source: #"@interface App : NSObject\n@property(nonatomic) BOOL enabled;\n@end"#),
    .init(language: "html", source: #"<section class="hero">Hello</section>"#),
    .init(language: "css", source: #".hero { color: #ffcc00; margin: 12px !important; }"#),
    .init(language: "xml", source: #"<?xml version="1.0"?><root enabled="true" />"#),
    .init(language: "sql", source: #"SELECT count(*) FROM users WHERE enabled = true;"#),
    .init(language: "toml", source: #"[tool]\nenabled = true\ncount = 2"#),
    .init(language: "markdown", source: #"# Title\n\n- [link](https://example.com)\n\n`code`"#)
]
