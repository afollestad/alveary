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

    func testTableImageCellFitsItsColumnInsteadOfRenderingInline() throws {
        let view = try imageTableView()

        let imageViews = descendants(ofType: AppKitMarkdownImageBlockView.self, in: view)
        XCTAssertEqual(imageViews.count, 2)
        for imageView in imageViews {
            XCTAssertLessThanOrEqual(imageView.frame.width, appMarkdownTableImageCellMaxSize.width)
            XCTAssertLessThanOrEqual(imageView.frame.height, appMarkdownTableImageCellMaxSize.height)
            XCTAssertEqual(
                imageView.frame.width / imageView.frame.height,
                Self.tallImageSize.width / Self.tallImageSize.height,
                accuracy: 0.01
            )
        }

        // Rendered inline this row alone costs 1565pt plus a ~778pt phantom baseline drop.
        XCTAssertLessThan(view.intrinsicContentSize.height, 600)

        // Both columns stay reachable: the fitted cells no longer push the table into its
        // horizontal-scroll variant, which is what hid the "After" column.
        let table = try XCTUnwrap(descendants(ofType: AppKitMarkdownTableView.self, in: view).first)
        XCTAssertLessThanOrEqual(
            table.tableDocumentFrameForTesting.width,
            table.tableChromeFrameForTesting.width + 0.5
        )
    }

    func testTableImageCellHeightMatchesHydratedRenderer() throws {
        let store = try imageTableStore()
        let document = AppMarkdownParser().documentPreservingSource(for: Self.imageTableMarkdown)

        let measured = AppKitMarkdownLayoutMeasurer(document: document, imageStore: store).measure(width: 520)
        let hydrated = try imageTableView(store: store)

        XCTAssertEqual(measured.contentHeight, hydrated.intrinsicContentSize.height, accuracy: 0.5)
    }

    func testTableImageCellGrowsWhenItsImageLoads() async throws {
        let store = AppMarkdownImageStore(
            loader: SizedMarkdownImageLoader(
                width: Int(Self.tallImageSize.width),
                height: Int(Self.tallImageSize.height)
            ),
            diskCache: nil
        )
        let view = try imageTableView(store: store)
        let placeholderHeight = view.intrinsicContentSize.height

        try await waitForInlineImage(source: "https://example.com/before.png", in: store)
        try await waitForInlineImage(source: "https://example.com/after.png", in: store)
        await Task.yield()
        view.layoutSubtreeIfNeeded()

        // The portrait capture fits to 420pt against a 147pt 16:9 placeholder, so a cell still
        // sized from the pre-load fallback would leave the row barely taller than it started.
        XCTAssertGreaterThan(view.intrinsicContentSize.height, placeholderHeight + 200)
    }

    func testTableImageCellOpensItsWrapperLink() throws {
        var openedURLs: [URL] = []
        let view = try imageTableView(onOpenLink: { openedURLs.append($0) })

        // The document-level image-open handler must not reach into the cell and displace the
        // wrapper link; the transcript sets one on every markdown view.
        var previewedImages: [BlockInputImage] = []
        view.onOpenImage = { image, _ in previewedImages.append(image) }

        let imageView = try XCTUnwrap(descendants(ofType: AppKitMarkdownImageBlockView.self, in: view).first)
        XCTAssertTrue(imageView.performOpenForTesting())

        // The thumbnail points at the demo video, not at its own PNG.
        XCTAssertEqual(openedURLs, [URL(string: "https://example.com/before.mp4")])
        XCTAssertTrue(previewedImages.isEmpty)
    }

    private static let tallImageSize = CGSize(width: 720, height: 1_565)

    private static let imageTableMarkdown = """
    | Before | After |
    | --- | --- |
    | [![Before](https://example.com/before.png)](https://example.com/before.mp4) | \
    [![After](https://example.com/after.png)](https://example.com/after.mp4) |
    """

    private func imageTableStore() throws -> AppMarkdownImageStore {
        let store = AppMarkdownImageStore(loader: SuspendedMarkdownImageLoader(), diskCache: nil)
        let data = try appMarkdownTestPNGData(
            width: Int(Self.tallImageSize.width),
            height: Int(Self.tallImageSize.height)
        )
        for source in ["https://example.com/before.png", "https://example.com/after.png"] {
            store.preloadForTesting(source: source, image: try XCTUnwrap(NSImage(data: data)))
        }
        return store
    }

    private func imageTableView(
        store: AppMarkdownImageStore? = nil,
        onOpenLink: ((URL) -> Void)? = nil
    ) throws -> AppKitMarkdownView {
        let view = AppKitMarkdownView(
            document: AppMarkdownParser().documentPreservingSource(for: Self.imageTableMarkdown),
            imageStore: try store ?? imageTableStore(),
            onOpenLink: onOpenLink
        )
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 2_000)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func descendants<T: NSView>(ofType type: T.Type, in view: NSView) -> [T] {
        view.subviews.flatMap { child -> [T] in
            var matches = descendants(ofType: type, in: child)
            if let match = child as? T {
                matches.insert(match, at: 0)
            }
            return matches
        }
    }

    private func preloadedStore(source: String, width: Int, height: Int) throws -> AppMarkdownImageStore {
        let store = AppMarkdownImageStore(loader: SuspendedMarkdownImageLoader(), diskCache: nil)
        let image = try XCTUnwrap(NSImage(data: appMarkdownTestPNGData(width: width, height: height)))
        store.preloadForTesting(source: source, image: image)
        return store
    }

    private func renderedText(in view: AppKitMarkdownView) -> String {
        descendants(ofType: NSTextView.self, in: view).map(\.string).joined(separator: "\n")
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
