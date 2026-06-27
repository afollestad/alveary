@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitMarkdownRendererTests: XCTestCase {
    func testRendererBuildsViewsForTranscriptRequiredMarkdown() {
        let document = AppMarkdownParser(baseURL: URL(string: "https://example.com/"))
            .documentPreservingSource(
                for: """
                # Heading

                Paragraph with [link](/docs) and `code`.

                - [x] Complete task
                - Plain item

                > Quote

                ```swift
                let value = 1
                ```

                ---

                | Name | Count |
                | --- | ---: |
                | A | 1 |
                """
            )

        let view = AppKitMarkdownView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        view.layoutSubtreeIfNeeded()

        let textValues = view.descendants(of: NSTextView.self).map(\.string)
        XCTAssertTrue(textValues.contains { $0.contains("Heading") })
        XCTAssertTrue(textValues.contains { $0.contains("Paragraph with link and code") })
        XCTAssertTrue(textValues.contains { $0.contains("Complete task") })
        XCTAssertTrue(textValues.contains { $0.contains("Quote") })
        XCTAssertTrue(textValues.contains { $0.contains("let value = 1") })
        XCTAssertTrue(textValues.contains { $0.contains("Count") })
        XCTAssertTrue(textValues.contains { $0.contains("1") })
        XCTAssertFalse(textValues.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertFalse(view.descendants(of: AppKitMarkdownTaskCheckbox.self).isEmpty)
        XCTAssertFalse(view.descendants(of: AppKitMarkdownCodeBlockView.self).isEmpty)
        XCTAssertFalse(view.descendants(of: AppKitMarkdownTableView.self).isEmpty)
        XCTAssertFalse(view.descendants(of: AppKitMarkdownRuleView.self).isEmpty)
    }

    func testAttributedBuilderPreservesInlineCodeAndLinkMetadata() throws {
        let attributed = try AppMarkdownParser(baseURL: URL(string: "https://example.com/"))
            .attributedString(for: "Open [docs](/docs) and run `pwd`.")
        let rendered = AppKitMarkdownAttributedStringBuilder.attributedString(
            from: attributed,
            baseFont: .preferredFont(forTextStyle: .body),
            inlineCodeStyle: .standard
        )

        let codeRange = (rendered.string as NSString).range(of: "pwd")
        let linkRange = (rendered.string as NSString).range(of: "docs")
        XCTAssertEqual(
            rendered.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil) as? NSColor,
            AppMarkdownCodeBlockPalette.inlineFillNSColor
        )
        XCTAssertEqual(
            (rendered.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL)?.absoluteURL,
            URL(string: "https://example.com/docs")
        )
        XCTAssertEqual(
            rendered.attribute(.foregroundColor, at: linkRange.location, effectiveRange: nil) as? NSColor,
            .controlAccentColor
        )
    }

    func testCodeBlockTextViewKeepsHorizontalLayout() {
        let codeBlock = AppKitMarkdownCodeBlockView(
            code: "let value = \"\(String(repeating: "wide ", count: 80))\"",
            languageHint: "swift"
        )
        codeBlock.frame = NSRect(x: 0, y: 0, width: 220, height: 120)
        codeBlock.layoutSubtreeIfNeeded()

        guard let textView = codeBlock.descendants(of: AppKitMarkdownTextView.self).first else {
            return XCTFail("Expected code block to contain an AppKit markdown text view")
        }
        XCTAssertEqual(textView.textContainer?.widthTracksTextView, false)
        XCTAssertGreaterThan(textView.textContainer?.containerSize.width ?? 0, 1_000)
    }

    func testCodeBlockReservesSpaceForHorizontalScrollbar() throws {
        let codeBlock = AppKitMarkdownCodeBlockView(
            code: "let value = \"\(String(repeating: "wide ", count: 80))\"",
            languageHint: "swift"
        )
        codeBlock.frame = NSRect(x: 0, y: 0, width: 220, height: 120)
        codeBlock.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(codeBlock.descendants(of: AppKitMarkdownTextView.self).first)
        let scrollView = try XCTUnwrap(codeBlock.descendants(of: NSScrollView.self).first)

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertGreaterThanOrEqual(
            codeBlock.intrinsicContentSize.height,
            textView.frame.height + appKitHorizontalOverflowScrollbarReserve
        )
    }

    func testScrollbarReserveOnlyAppliesToLegacyScrollers() {
        XCTAssertEqual(appKitHorizontalOverflowScrollbarReserveValue(for: .overlay), 0)
        XCTAssertGreaterThan(appKitHorizontalOverflowScrollbarReserveValue(for: .legacy), 0)
    }

    func testCodeBlockDoesNotMeasureTrailingBlankLines() throws {
        let codeBlock = AppKitMarkdownCodeBlockView(
            code: "let value = 1\n   \n\t\n",
            languageHint: "swift"
        )
        codeBlock.frame = NSRect(x: 0, y: 0, width: 220, height: 120)
        codeBlock.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(codeBlock.descendants(of: AppKitMarkdownTextView.self).first)

        XCTAssertEqual(textView.string, "let value = 1")
    }

    func testCodeDisplayPreservesTrailingSpacesOnFinalContentLine() {
        XCTAssertEqual(appMarkdownCodeDisplayContent("let value = 1   \n"), "let value = 1   ")
    }

    func testCodeBlockAppliesAppKitSyntaxHighlightingColors() throws {
        let codeBlock = AppKitMarkdownCodeBlockView(
            code: "let value = \"hello\"",
            languageHint: "swift"
        )
        codeBlock.appearance = NSAppearance(named: .darkAqua)
        codeBlock.frame = NSRect(x: 0, y: 0, width: 320, height: 140)
        codeBlock.layoutSubtreeIfNeeded()

        let textStorage = try XCTUnwrap(codeBlock.descendants(of: AppKitMarkdownTextView.self).first?.textStorage)
        let keywordRange = (textStorage.string as NSString).range(of: "let")
        let keywordColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: keywordRange.location, effectiveRange: nil) as? NSColor)

        XCTAssertNotEqual(keywordColor, NSColor.labelColor)
    }

    func testCodeBlockRefreshesLayerColorsWhenAppearanceChanges() throws {
        let codeBlock = AppKitMarkdownCodeBlockView(
            code: "let value = \"hello\"",
            languageHint: "swift"
        )
        codeBlock.wantsLayer = true
        codeBlock.appearance = NSAppearance(named: .darkAqua)
        codeBlock.frame = NSRect(x: 0, y: 0, width: 320, height: 140)
        codeBlock.layoutSubtreeIfNeeded()
        let darkBackground = try XCTUnwrap(codeBlock.layer?.backgroundColor)

        codeBlock.appearance = NSAppearance(named: .aqua)
        codeBlock.viewDidChangeEffectiveAppearance()
        let lightBackground = try XCTUnwrap(codeBlock.layer?.backgroundColor)

        XCTAssertNotEqual(darkBackground, lightBackground)
        XCTAssertEqual(
            lightBackground,
            AppMarkdownCodeBlockPalette.fillNSColor(isDark: false).cgColor
        )
    }

    func testParagraphTextWrapsToMarkdownViewWidth() {
        let document = AppMarkdownParser().documentPreservingSource(
            for: String(repeating: "wrapping text ", count: 80)
        )
        let view = AppKitMarkdownView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 180, height: 1_000)
        view.layoutSubtreeIfNeeded()

        guard let textView = view.descendants(of: AppKitMarkdownTextView.self).first else {
            return XCTFail("Expected paragraph to render with an AppKit markdown text view")
        }
        XCTAssertEqual(textView.textContainer?.widthTracksTextView, true)
        XCTAssertLessThanOrEqual(textView.bounds.width, 180)
        XCTAssertGreaterThan(textView.intrinsicContentSize.height, textView.font?.pointSize ?? 0)
    }

    func testListMarkersUseRendererTypography() throws {
        let document = AppMarkdownParser().documentPreservingSource(
            for: """
            - First item
            1. Second item
            """
        )
        let typography = AppKitMarkdownTypography(
            body: .systemFont(ofSize: 24),
            inlineCode: .monospacedSystemFont(ofSize: 24, weight: .regular)
        )
        let view = AppKitMarkdownView(document: document, typography: typography)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        view.layoutSubtreeIfNeeded()

        let bullets = view.descendants(of: AppKitMarkdownBulletMarkerView.self)
        let orderedMarkers = view.descendants(of: AppKitMarkdownMarkerLabel.self)
        let unorderedMarker = try XCTUnwrap(bullets.first)
        let orderedMarker = try XCTUnwrap(orderedMarkers.first { $0.stringValue == "1." })
        XCTAssertEqual(unorderedMarker.bulletDiameterForTesting, ceil(24 * AppKitMarkdownMetrics.unorderedBulletDiameterScale))
        XCTAssertEqual(orderedMarker.font?.pointSize, 24)
        XCTAssertEqual(unorderedMarker.color, orderedMarker.textColor)
        XCTAssertEqual(unorderedMarker.color, .secondaryLabelColor)
        XCTAssertEqual(unorderedMarker.frame.width, orderedMarker.frame.width)
        XCTAssertEqual(unorderedMarker.bulletRectForTesting.minX, AppKitMarkdownMetrics.unorderedBulletLeadingInset)
        XCTAssertLessThan(unorderedMarker.bulletRectForTesting.maxX, unorderedMarker.bounds.maxX)
    }

    func testUnorderedListsRenderBulletsAndOrderedListsRenderOrdinals() throws {
        let document = AppMarkdownParser().documentPreservingSource(
            for: """
            - First unordered
            - Second unordered

            1. First ordered
            2. Second ordered
            """
        )
        let view = AppKitMarkdownView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 300)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.descendants(of: AppKitMarkdownBulletMarkerView.self).count, 2)
        let markerValues = view.descendants(of: AppKitMarkdownMarkerLabel.self).map(\.stringValue)
        XCTAssertEqual(markerValues, ["1.", "2."])
    }

    func testLinkClickInvokesCurrentHandler() throws {
        let document = AppMarkdownParser().documentPreservingSource(
            for: "Open [docs](README.md)."
        )
        let view = AppKitMarkdownView(document: document)
        var openedURL: URL?
        view.onOpenLink = { openedURL = $0 }
        view.frame = NSRect(x: 0, y: 0, width: 240, height: 200)
        view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(view.descendants(of: AppKitMarkdownTextView.self).first)
        let link = try XCTUnwrap(linkAttribute(in: textView, matching: "docs"))

        XCTAssertTrue(textView.textView(textView, clickedOnLink: link, at: 0))
        XCTAssertEqual(openedURL?.relativeString, "README.md")
    }

    func testLinkHoverHitTestingOnlyMatchesLinkGlyphs() throws {
        let attributed = try AppMarkdownParser().attributedString(
            for: "Open [docs](README.md) now."
        )
        let textView = AppKitMarkdownTextView(
            content: AppKitMarkdownAttributedStringBuilder.attributedString(
                from: attributed,
                baseFont: .preferredFont(forTextStyle: .body),
                inlineCodeStyle: .standard
            ),
            heightInvalidationHandler: { }
        )
        textView.frame = NSRect(x: 0, y: 0, width: 240, height: 80)
        textView.layoutSubtreeIfNeeded()

        let linkRect = try XCTUnwrap(textView.linkCursorRectsForTesting.first)

        XCTAssertEqual(
            textView.cursorURLForTesting(at: NSPoint(x: linkRect.midX, y: linkRect.midY))?.relativeString,
            "README.md"
        )
        XCTAssertNil(textView.cursorURLForTesting(at: NSPoint(x: linkRect.maxX + 24, y: linkRect.midY)))
    }

    func testMarkdownTextViewDoesNotRegisterAsDragDestination() {
        let textView = AppKitMarkdownTextView(
            content: NSAttributedString(string: "Display only"),
            heightInvalidationHandler: { }
        )
        XCTAssertTrue(textView.registeredDraggedTypes.isEmpty)

        textView.registerForDraggedTypes([.string, .fileURL])

        textView.updateDragTypeRegistration()

        XCTAssertTrue(textView.registeredDraggedTypes.isEmpty)
    }

    func testTableChromeHugsRowsWithoutTrailingBlankArea() throws {
        let table = try markdownTable(
            """
            | Task | Result |
            | :--- | :--- |
            | Read `index.html` | Valid HTML5 document |
            | Count CSS files in `styles/` | 4 files |
            """
        )

        XCTAssertEqual(table.tableChromeFrameForTesting.height, table.bounds.height, accuracy: 0.5)
        XCTAssertEqual(table.tableChromeFrameForTesting.height, table.tableDocumentFrameForTesting.height, accuracy: 0.5)
    }

    func testTableUsesTextBubbleCornerRadiusAndSharedSubtleBorders() throws {
        let table = try markdownTable(
            """
            | Task | Result |
            | :--- | :--- |
            | Read `index.html` | Valid HTML5 document |
            """
        )
        table.appearance = NSAppearance(named: .darkAqua)
        table.frame = NSRect(x: 0, y: 0, width: 420, height: 400)
        table.layoutSubtreeIfNeeded()

        XCTAssertEqual(table.tableCornerRadiusForTesting, markdownTableCornerRadius)
        XCTAssertEqual(markdownTableCornerRadius, chatBubbleCornerRadius)
        XCTAssertEqual(
            table.tableCellBorderColorsForTesting.compactMap(\.self).first,
            table.tableBorderColorForTesting
        )
    }

    func testWideTableUsesInternalHorizontalOverflow() throws {
        let table = try markdownTable(
            """
            | Name | Color | Animal | Food | City | Sport | Season | Music |
            | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
            | Alice | Red | Cat | Pizza | Paris | Tennis | Summer | Jazz |
            """
        )
        table.frame = .zero

        XCTAssertEqual(table.fittingSize.width, 520)

        table.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
        table.layoutSubtreeIfNeeded()

        XCTAssertEqual(table.fittingSize.width, 520)
        XCTAssertEqual(table.tableChromeFrameForTesting.width, 520)
        XCTAssertGreaterThan(table.tableDocumentFrameForTesting.width, table.tableChromeFrameForTesting.width)
        XCTAssertEqual(
            table.tableChromeFrameForTesting.height,
            table.tableDocumentFrameForTesting.height + ceil(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)),
            accuracy: 0.5
        )
    }

    func testNarrowTableHugsNaturalWidthBeforeBubbleCap() throws {
        let table = try markdownTable(
            """
            | Name | Done |
            | :--- | :--- |
            | Alice | Yes |
            """
        )
        table.frame = .zero

        XCTAssertEqual(table.fittingSize.width, 240)
        XCTAssertEqual(table.naturalViewportWidth(constrainedTo: 520), 240)

        table.frame = NSRect(x: 0, y: 0, width: 240, height: 400)
        table.layoutSubtreeIfNeeded()

        XCTAssertEqual(table.tableChromeFrameForTesting.width, 240)
        XCTAssertEqual(table.tableDocumentFrameForTesting.width, 240)
        XCTAssertEqual(table.tableChromeFrameForTesting.height, table.tableDocumentFrameForTesting.height, accuracy: 0.5)
    }

    func testTableLinkClickInvokesHandler() throws {
        let document = AppMarkdownParser().documentPreservingSource(
            for: """
            | Name |
            | --- |
            | [docs](README.md) |
            """
        )
        var openedURL: URL?
        let view = AppKitMarkdownView(document: document, onOpenLink: { openedURL = $0 })
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(
            view.descendants(of: AppKitMarkdownTextView.self).first { $0.string.contains("docs") }
        )
        let link = try XCTUnwrap(linkAttribute(in: textView, matching: "docs"))

        XCTAssertTrue(textView.textView(textView, clickedOnLink: link, at: 0))
        XCTAssertEqual(openedURL?.relativeString, "README.md")
    }

    func testTableBodyCellsDoNotRenderOpaqueClearBackground() throws {
        let document = AppMarkdownParser().documentPreservingSource(
            for: """
            | Name |
            | --- |
            | A |
            """
        )
        let view = AppKitMarkdownView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        view.layoutSubtreeIfNeeded()

        let bodyTextView = try XCTUnwrap(
            view.descendants(of: AppKitMarkdownTextView.self).first { $0.string == "A" }
        )

        XCTAssertNil(bodyTextView.superview?.layer?.backgroundColor)
    }

    private func markdownTable(_ markdown: String) throws -> AppKitMarkdownTableView {
        let document = AppMarkdownParser().documentPreservingSource(for: markdown)
        let view = AppKitMarkdownView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 600)
        view.layoutSubtreeIfNeeded()
        return try XCTUnwrap(view.descendants(of: AppKitMarkdownTableView.self).first)
    }

}

@MainActor
private func linkAttribute(in textView: AppKitMarkdownTextView, matching text: String) -> Any? {
    let range = (textView.string as NSString).range(of: text)
    guard range.location != NSNotFound else {
        return nil
    }
    return textView.textStorage?.attribute(.link, at: range.location, effectiveRange: nil)
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
