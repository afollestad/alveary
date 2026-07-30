@preconcurrency import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitMarkdownRendererTests {
    private static let badgeMarkdown = "**![P1](https://example.com/p1.png) Add the required commit trailer** now"

    func testBuilderSwapsLoadedInlineImageRunForAttachment() throws {
        let store = try preloadedStore(source: "https://example.com/p1.png", width: 40, height: 20)
        let document = AppMarkdownParser().documentPreservingSource(for: Self.badgeMarkdown)
        guard case let .markdown(content) = document.blocks[0] else {
            return XCTFail("Expected a markdown block.")
        }

        let attributed = AppKitMarkdownAttributedStringBuilder.attributedString(
            from: content,
            baseFont: .systemFont(ofSize: 13),
            inlineCodeStyle: .standard,
            imageStore: store
        )

        let text = attributed.string
        XCTAssertTrue(text.contains("\u{FFFC}"))
        XCTAssertFalse(text.contains("P1"))
        let attachmentLocation = (text as NSString).range(of: "\u{FFFC}").location
        let attachment = try XCTUnwrap(
            attributed.attribute(.attachment, at: attachmentLocation, effectiveRange: nil) as? NSTextAttachment
        )
        XCTAssertEqual(attachment.bounds.size, CGSize(width: 40, height: 20))
        // Centered on the cap-height midline: the attachment dips below the baseline.
        let expectedDrop = AppMarkdownInlineImageInfo.baselineDrop(
            forDisplayHeight: 20,
            capHeight: NSFont.systemFont(ofSize: 13).capHeight
        )
        XCTAssertEqual(attachment.bounds.origin.y, -expectedDrop, accuracy: 0.01)
    }

    func testBuilderKeepsAltTextAndStartsLoadWhenImageUnloaded() throws {
        let store = AppMarkdownImageStore(loader: SuspendedMarkdownImageLoader(), diskCache: nil)
        let document = AppMarkdownParser().documentPreservingSource(for: Self.badgeMarkdown)
        guard case let .markdown(content) = document.blocks[0] else {
            return XCTFail("Expected a markdown block.")
        }

        let attributed = AppKitMarkdownAttributedStringBuilder.attributedString(
            from: content,
            baseFont: .systemFont(ofSize: 13),
            inlineCodeStyle: .standard,
            imageStore: store
        )

        XCTAssertTrue(attributed.string.contains("P1"))
        XCTAssertFalse(attributed.string.contains("\u{FFFC}"))
        XCTAssertNil(store.image(forSource: "https://example.com/p1.png"))
        XCTAssertFalse(store.hasFailed(source: "https://example.com/p1.png"))
    }

    func testInlineImageHeightMatchesHydratedRendererWhenLoaded() throws {
        let store = try preloadedStore(source: "https://example.com/p1.png", width: 40, height: 72)
        let document = AppMarkdownParser().documentPreservingSource(for: Self.badgeMarkdown)

        let measured = AppKitMarkdownLayoutMeasurer(document: document, imageStore: store).measure(width: 420)
        let hydrated = AppKitMarkdownView(document: document, imageStore: store)
        hydrated.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hydrated.layoutSubtreeIfNeeded()

        XCTAssertGreaterThanOrEqual(measured.contentHeight, 72)
        XCTAssertEqual(measured.contentHeight, hydrated.intrinsicContentSize.height, accuracy: 0.5)
    }

    func testMarkdownViewRebuildsWhenInlineImageLoads() async throws {
        let store = AppMarkdownImageStore(
            loader: SizedMarkdownImageLoader(width: 40, height: 20),
            diskCache: nil
        )
        let document = AppMarkdownParser().documentPreservingSource(for: Self.badgeMarkdown)
        let view = AppKitMarkdownView(document: document, imageStore: store)
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        view.layoutSubtreeIfNeeded()
        var invalidationCount = 0
        view.onHeightInvalidated = {
            invalidationCount += 1
        }
        XCTAssertTrue(renderedText(in: view).contains("P1"))

        try await waitForInlineImage(source: "https://example.com/p1.png", in: store)
        await Task.yield()
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(renderedText(in: view).contains("\u{FFFC}"))
        XCTAssertFalse(renderedText(in: view).contains("P1"))
        XCTAssertGreaterThan(invalidationCount, 0)
    }

    func testLoadStateFingerprintTracksInlineImageStates() throws {
        let store = AppMarkdownImageStore(loader: SuspendedMarkdownImageLoader(), diskCache: nil)

        XCTAssertEqual(store.loadStateFingerprint(forMarkdown: "No images here"), "")
        XCTAssertEqual(store.loadStateFingerprint(forMarkdown: Self.badgeMarkdown), "n")

        let image = try XCTUnwrap(NSImage(data: appMarkdownTestPNGData(width: 40, height: 20)))
        store.preloadForTesting(source: "https://example.com/p1.png", image: image)
        XCTAssertEqual(store.loadStateFingerprint(forMarkdown: Self.badgeMarkdown), "l40x20")
    }

    func testPreparedLayoutKeyVariesWithInlineImageFingerprint() {
        func key(fingerprint: String) -> AppKitMarkdownPreparedLayoutKey {
            AppKitMarkdownPreparedLayoutKey(
                rowID: "row",
                markdown: Self.badgeMarkdown,
                role: "assistant",
                availableWidth: 420,
                bubbleMaxWidth: 720,
                typography: .default,
                inlineCodeStyle: .assistantBubble,
                appearanceName: NSAppearance.Name.aqua.rawValue,
                isExpanded: false,
                showsRetry: false,
                inlineImageFingerprint: fingerprint
            )
        }

        // A load changes measured heights, so it must miss the measurement cache.
        XCTAssertNotEqual(key(fingerprint: "n"), key(fingerprint: "l40x20"))
    }

    private func preloadedStore(source: String, width: Int, height: Int) throws -> AppMarkdownImageStore {
        let store = AppMarkdownImageStore(loader: SuspendedMarkdownImageLoader(), diskCache: nil)
        let image = try XCTUnwrap(NSImage(data: appMarkdownTestPNGData(width: width, height: height)))
        store.preloadForTesting(source: source, image: image)
        return store
    }

    private func renderedText(in view: AppKitMarkdownView) -> String {
        textViews(in: view).map(\.string).joined(separator: "\n")
    }

    private func textViews(in view: NSView) -> [NSTextView] {
        view.subviews.flatMap { child -> [NSTextView] in
            var matches = textViews(in: child)
            if let textView = child as? NSTextView {
                matches.insert(textView, at: 0)
            }
            return matches
        }
    }

    private func waitForInlineImage(source: String, in store: AppMarkdownImageStore) async throws {
        for _ in 0..<40 {
            if store.image(forSource: source) != nil {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Inline image did not load.")
    }
}

private struct SuspendedMarkdownImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw CancellationError()
    }
}

private struct SizedMarkdownImageLoader: BlockInputImageLoading {
    let width: Int
    let height: Int

    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try BlockInputLoadedImage(
            data: appMarkdownTestPNGData(width: width, height: height),
            dimensions: BlockInputImageDimensions(width: width, height: height)
        )
    }
}
