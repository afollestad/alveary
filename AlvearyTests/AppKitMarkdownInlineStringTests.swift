import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitMarkdownInlineStringTests: XCTestCase {
    private let baseFont = NSFont.systemFont(ofSize: 12)

    func testPlainStringRoundTripsThroughTheFastPath() {
        let attributed = AppKitMarkdownInlineString.attributedString(
            for: "Retry transient GitHub failures",
            baseFont: baseFont,
            foregroundColor: .secondaryLabelColor
        )

        XCTAssertEqual(attributed.string, "Retry transient GitHub failures")
        let attributes = attributed.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(attributes[.font] as? NSFont, baseFont)
        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, .secondaryLabelColor)
        XCTAssertNil(attributes[.backgroundColor])
    }

    func testInlineCodeLosesItsBackticksAndGainsAMonospacedRun() {
        let attributed = AppKitMarkdownInlineString.attributedString(
            for: "Add `arkivanov/parcelize-darwin` to Serializer section",
            baseFont: baseFont,
            foregroundColor: .secondaryLabelColor
        )

        XCTAssertEqual(attributed.string, "Add arkivanov/parcelize-darwin to Serializer section")

        let codeRange = (attributed.string as NSString).range(of: "arkivanov/parcelize-darwin")
        let codeAttributes = attributed.attributes(at: codeRange.location, effectiveRange: nil)
        let codeFont = codeAttributes[.font] as? NSFont
        XCTAssertEqual(codeFont?.pointSize, baseFont.pointSize * markdownInlineCodeFontScale)
        XCTAssertEqual(codeFont?.fontDescriptor.symbolicTraits.contains(.monoSpace), true)
        XCTAssertNotNil(codeAttributes[.backgroundColor])

        // Plain runs carry no fill, so the chip reads as a distinct span.
        XCTAssertNil(attributed.attributes(at: 0, effectiveRange: nil)[.backgroundColor])
    }

    func testCallerForegroundColorSurvivesTheBuildersOwnLabelColorPass() {
        let attributed = AppKitMarkdownInlineString.attributedString(
            for: "Fix `Array<String>` bridging",
            baseFont: baseFont,
            foregroundColor: .secondaryLabelColor
        )

        attributed.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            XCTAssertEqual(value as? NSColor, .secondaryLabelColor)
        }
    }

    func testInlineCodeFillHonorsTheRequestedOverride() {
        let fill = AppKitMarkdownInlineString.mutedInlineCodeFill(over: .secondaryLabelColor)
        let attributed = AppKitMarkdownInlineString.attributedString(
            for: "Cache `resolvePath` results",
            baseFont: baseFont,
            foregroundColor: .secondaryLabelColor,
            inlineCodeFill: fill
        )

        let codeRange = (attributed.string as NSString).range(of: "resolvePath")
        let codeAttributes = attributed.attributes(at: codeRange.location, effectiveRange: nil)
        XCTAssertEqual(codeAttributes[.backgroundColor] as? NSColor, fill)
    }

    func testTitlesAreNotChippedAsMentionsOrSlashCommands() {
        // The distinction from `TranscriptToolSummaryFormatter`: third-party prose must keep
        // `@username` and `/api/users` verbatim rather than having them chipped.
        for markdown in ["Thanks @octocat for the fix", "Fix /api/users endpoint"] {
            let attributed = AppKitMarkdownInlineString.attributedString(
                for: markdown,
                baseFont: baseFont,
                foregroundColor: .secondaryLabelColor
            )
            XCTAssertEqual(attributed.string, markdown)
            attributed.enumerateAttribute(
                .backgroundColor,
                in: NSRange(location: 0, length: attributed.length)
            ) { value, _, _ in
                XCTAssertNil(value)
            }
        }
    }

    /// The parse is shared with the SwiftUI labels through `AppMarkdownInlineParseCache`,
    /// and each caller re-tints the result, so a second call must not come back carrying
    /// the first caller's color.
    func testCachedParseDoesNotLeakTheFirstCallersStyling() {
        let markdown = "Harden `retry` handling"
        let secondary = AppKitMarkdownInlineString.attributedString(
            for: markdown,
            baseFont: baseFont,
            foregroundColor: .secondaryLabelColor
        )
        let label = AppKitMarkdownInlineString.attributedString(
            for: markdown,
            baseFont: baseFont,
            foregroundColor: .labelColor
        )

        XCTAssertEqual(secondary.string, "Harden retry handling")
        XCTAssertEqual(label.string, "Harden retry handling")
        XCTAssertEqual(
            secondary.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            .secondaryLabelColor
        )
        XCTAssertEqual(
            label.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            .labelColor
        )
    }

    func testTruncationIsCarriedByTheParagraphStyleOnBothPaths() {
        for markdown in ["Plain title", "Title with `code`"] {
            let attributed = AppKitMarkdownInlineString.attributedString(
                for: markdown,
                baseFont: baseFont,
                foregroundColor: .labelColor
            )
            let style = attributed.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
            XCTAssertEqual(style?.lineBreakMode, .byTruncatingTail, "for \(markdown)")
        }
    }
}
