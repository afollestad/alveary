@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class AppKitMarkdownLayoutMeasurerTests: XCTestCase {
    func testTextMarkdownHeightMatchesHydratedRenderer() {
        assertMarkdownMeasurementParity(
            """
            # Heading

            Paragraph with **bold**, *italic*, [link](https://example.com), and `code`.

            ## Smaller heading
            """
        )
    }

    func testListAndQuoteHeightMatchesHydratedRenderer() {
        assertMarkdownMeasurementParity(
            """
            Ordered

            1. First item
            2. Second item
               - Nested bullet
               - [x] Nested task

            > Quote with `inline code`
            > and another line.
            """
        )
    }

    func testCodeBlockHeightMatchesHydratedRenderer() {
        assertMarkdownMeasurementParity(
            """
            ```swift
            let value = "\(String(repeating: "wide ", count: 40))"
            print(value)
            ```
            """,
            width: 240
        )
    }

    func testTableHeightMatchesHydratedRenderer() {
        assertMarkdownMeasurementParity(
            """
            | Name | Color | Animal | Food | City | Sport | Season | Music |
            | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
            | Alice | Red | Cat | Pizza | Paris | Tennis | Summer | Jazz |
            | Bob | Blue | Dog | Pasta | Tokyo | Soccer | Winter | Rock |
            """,
            width: 520
        )
    }

    func testImageHeightMatchesHydratedRendererWithoutLoading() {
        assertMarkdownMeasurementParity(
            #"""
            Intro text

            <img src="file:///tmp/photo.jpg" alt="Photo" width="262" height="174" />

            ![Diagram](images/diagram.png)
            """#,
            width: 420
        )
    }

    func testNaturalWidthMatchesHydratedRendererForShortTextAndTables() {
        assertNaturalWidthParity("Short message", width: 320)
        assertNaturalWidthParity(
            """
            | Name | Done |
            | :--- | :--- |
            | Alice | Yes |
            """,
            width: 520
        )
        assertNaturalWidthParity(String(repeating: "wrapping text ", count: 80), width: 260)
    }

    func testPreparedLayoutKeyInvalidatesForLayoutInputs() {
        let base = preparedLayoutKey()

        XCTAssertNotEqual(base, preparedLayoutKey(width: 321))
        XCTAssertNotEqual(base, preparedLayoutKey(typography: AppKitMarkdownTypography(body: .systemFont(ofSize: 19))))
        XCTAssertNotEqual(base, preparedLayoutKey(appearanceName: NSAppearance.Name.darkAqua.rawValue))
        XCTAssertNotEqual(base, preparedLayoutKey(isExpanded: true))
        XCTAssertNotEqual(base, preparedLayoutKey(showsRetry: true))
    }

    func testPreparedLayoutCacheEvictsByCountLimit() {
        let cache = AppKitMarkdownPreparedLayoutCache(countLimit: 1, costLimit: 10_000)
        let firstKey = preparedLayoutKey(markdown: "one")
        let secondKey = preparedLayoutKey(markdown: "two")
        cache.insert(.init(contentHeight: 20, naturalContentWidth: 40, fallbackRequired: false), for: firstKey, cost: 1)
        cache.insert(.init(contentHeight: 30, naturalContentWidth: 50, fallbackRequired: false), for: secondKey, cost: 1)

        XCTAssertNil(cache.measurement(for: firstKey))
        XCTAssertEqual(cache.measurement(for: secondKey)?.contentHeight, 30)
        XCTAssertEqual(cache.countForTesting, 1)
    }

    func testPreparedLayoutCacheEvictsByCostLimit() {
        let cache = AppKitMarkdownPreparedLayoutCache(countLimit: 10, costLimit: 5)
        let firstKey = preparedLayoutKey(markdown: "one")
        let secondKey = preparedLayoutKey(markdown: "two")
        cache.insert(.init(contentHeight: 20, naturalContentWidth: 40, fallbackRequired: false), for: firstKey, cost: 4)
        cache.insert(.init(contentHeight: 30, naturalContentWidth: 50, fallbackRequired: false), for: secondKey, cost: 4)

        XCTAssertNil(cache.measurement(for: firstKey))
        XCTAssertEqual(cache.measurement(for: secondKey)?.contentHeight, 30)
        XCTAssertEqual(cache.countForTesting, 1)
    }

    /// The measurer resolves natural sizes through the same store the renderer
    /// draws from; if the two ever disagree a row reserves one height and paints
    /// another.
    func testLocalImageHeightMatchesHydratedRenderer() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try appMarkdownTestPNGData(width: 200, height: 400)
            .write(to: directoryURL.appendingPathComponent("local.png"))

        let store = AppMarkdownImageStore(loader: AppMarkdownPendingImageLoader(), diskCache: nil)
        let document = AppMarkdownParser().documentPreservingSource(for: "![Local](local.png)")
        let measured = AppKitMarkdownLayoutMeasurer(
            document: document,
            imageStore: store,
            imageBaseURL: directoryURL
        )
        .measure(width: 320)

        let view = AppKitMarkdownView(document: document, imageBaseURL: directoryURL, imageStore: store)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 2_000)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(measured.contentHeight, 400, accuracy: 0.5)
        XCTAssertEqual(measured.contentHeight, view.intrinsicContentSize.height, accuracy: 0.5)
    }

    /// A remote source with nothing known yet must reserve the same default box
    /// in both paths, or the correction on load lands on a mismatched height.
    func testUnknownRemoteImageHeightMatchesHydratedRenderer() {
        let store = AppMarkdownImageStore(loader: AppMarkdownPendingImageLoader(), diskCache: nil)
        let document = AppMarkdownParser().documentPreservingSource(for: "![Remote](https://example.com/a.png)")

        let measured = AppKitMarkdownLayoutMeasurer(document: document, imageStore: store).measure(width: 320)
        let view = AppKitMarkdownView(document: document, imageStore: store)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 2_000)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(measured.contentHeight, 180, accuracy: 0.5)
        XCTAssertEqual(measured.contentHeight, view.intrinsicContentSize.height, accuracy: 0.5)
    }

    func testLoadedRemoteImageHeightMatchesHydratedRenderer() throws {
        let store = AppMarkdownImageStore(loader: AppMarkdownPendingImageLoader(), diskCache: nil)
        let document = AppMarkdownParser().documentPreservingSource(for: "![Remote](https://example.com/a.png)")
        store.preloadForTesting(
            source: "https://example.com/a.png",
            image: try XCTUnwrap(NSImage(data: appMarkdownTestPNGData(width: 800, height: 200)))
        )

        let measured = AppKitMarkdownLayoutMeasurer(document: document, imageStore: store).measure(width: 320)
        let view = AppKitMarkdownView(document: document, imageStore: store)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 2_000)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(measured.contentHeight, 80, accuracy: 0.5)
        XCTAssertEqual(measured.contentHeight, view.intrinsicContentSize.height, accuracy: 0.5)
    }

    private func assertMarkdownMeasurementParity(
        _ markdown: String,
        width: CGFloat = 420,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let document = AppMarkdownParser().documentPreservingSource(for: markdown)
        let measured = AppKitMarkdownLayoutMeasurer(document: document).measure(width: width)
        let hydrated = hydratedMarkdownView(document: document, width: width)

        XCTAssertFalse(measured.fallbackRequired, file: file, line: line)
        XCTAssertEqual(measured.contentHeight, hydrated.intrinsicContentSize.height, accuracy: 0.5, file: file, line: line)
    }

    private func assertNaturalWidthParity(
        _ markdown: String,
        width: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let document = AppMarkdownParser().documentPreservingSource(for: markdown)
        let measured = AppKitMarkdownLayoutMeasurer(document: document).measure(width: width)
        let hydrated = hydratedMarkdownView(document: document, width: width)
        let hydratedNaturalWidth = naturalMarkdownWidth(in: hydrated, constrainedTo: width)

        XCTAssertEqual(measured.naturalContentWidth, hydratedNaturalWidth, accuracy: 0.5, file: file, line: line)
    }

    private func hydratedMarkdownView(document: AppMarkdownDocument, width: CGFloat) -> AppKitMarkdownView {
        let view = AppKitMarkdownView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: width, height: 2_000)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func naturalMarkdownWidth(in view: AppKitMarkdownView, constrainedTo maxContentWidth: CGFloat) -> CGFloat {
        let textWidths = view.transcriptMarkdownTextViews.map { textView in
            textView.transcriptNaturalTextWidth(constrainedTo: maxContentWidth)
        }
        let viewWidths = view.transcriptNonTextMarkdownViews.map { view in
            if let tableView = view as? AppKitMarkdownTableView {
                return tableView.naturalViewportWidth(constrainedTo: maxContentWidth)
            }
            return view.fittingSize.width
        }
        return ceil(max((textWidths + viewWidths).max() ?? 0, 0))
    }

    private func preparedLayoutKey(
        markdown: String = "Hello",
        width: CGFloat = 320,
        typography: AppKitMarkdownTypography = .default,
        appearanceName: String = NSAppearance.Name.aqua.rawValue,
        isExpanded: Bool = false,
        showsRetry: Bool = false
    ) -> AppKitMarkdownPreparedLayoutKey {
        AppKitMarkdownPreparedLayoutKey(
            rowID: "row",
            markdown: markdown,
            role: "assistant",
            availableWidth: width,
            bubbleMaxWidth: 420,
            typography: typography,
            inlineCodeStyle: .standard,
            appearanceName: appearanceName,
            isExpanded: isExpanded,
            showsRetry: showsRetry
        )
    }
}
