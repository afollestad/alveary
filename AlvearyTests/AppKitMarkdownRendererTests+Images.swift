@preconcurrency import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitMarkdownRendererTests {
    func testRendererBuildsImageViewsForMarkdownAndHTMLImages() throws {
        let baseURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let document = AppMarkdownParser().documentPreservingSource(
            for: """
            ![Diagram](images/diagram.png)

            <img src="file:///tmp/photo.jpg" alt="Photo" width="262" height="174" />
            """
        )

        let view = AppKitMarkdownView(document: document, imageBaseURL: baseURL, imageStore: makeStubStore())
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        view.layoutSubtreeIfNeeded()

        let imageViews = view.descendants(of: AppKitMarkdownImageBlockView.self)
        XCTAssertEqual(imageViews.count, 2)
        // No file behind `images/diagram.png`, so the default aspect ratio still applies.
        XCTAssertEqual(imageViews[0].displaySizeForTesting.width, 420, accuracy: 0.5)
        XCTAssertEqual(imageViews[1].displaySizeForTesting, CGSize(width: 262, height: 174))
        XCTAssertFalse(view.descendants(of: NSTextView.self).map(\.string).contains { $0.contains("<img") })
    }

    /// A local source is sized from its header before any load runs, so the box
    /// the reader first sees is the box the bitmap lands in.
    func testLocalImageWrapsItsAspectRatioBeforeLoading() throws {
        let imageView = try localImageBlockView(pixelSize: CGSize(width: 200, height: 400), viewWidth: 320)

        XCTAssertNil(imageView.loadedImageForTesting)
        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 200, height: 400))
    }

    func testWideLocalImageDownscalesToAvailableWidth() throws {
        let imageView = try localImageBlockView(pixelSize: CGSize(width: 800, height: 200), viewWidth: 320)

        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 320, height: 80))
    }

    /// The old fixed box stretched every image to the full bubble width, which
    /// blew a small screenshot up past its pixels.
    func testSmallLocalImageIsNotUpscaledToTheAvailableWidth() throws {
        let imageView = try localImageBlockView(pixelSize: CGSize(width: 60, height: 40), viewWidth: 320)

        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 60, height: 40))
    }

    /// The whole point of probing before the load: the bitmap arriving must not
    /// move the transcript.
    func testLocalImageLoadDoesNotInvalidateMarkdownHeight() async throws {
        let imageURL = try temporaryPNGURL(named: "tiny.png", pixelSize: CGSize(width: 200, height: 400))
        let imageBaseURL = URL(fileURLWithPath: imageURL.deletingLastPathComponent().path, isDirectory: true)
        let document = AppMarkdownParser().documentPreservingSource(for: "![Tiny](tiny.png)")
        let view = AppKitMarkdownView(
            document: document,
            imageBaseURL: imageBaseURL,
            imageStore: AppMarkdownImageStore(loader: BlockInputDefaultImageLoader(), diskCache: nil)
        )
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 500)
        view.layoutSubtreeIfNeeded()
        let imageView = try XCTUnwrap(view.descendants(of: AppKitMarkdownImageBlockView.self).first)
        let initialHeight = view.intrinsicContentSize.height
        var invalidationCount = 0
        view.onHeightInvalidated = {
            invalidationCount += 1
        }

        try await waitForLoadedImage(in: imageView)
        view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(imageView.loadedImageForTesting)
        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 200, height: 400))
        XCTAssertEqual(view.intrinsicContentSize.height, initialHeight, accuracy: 0.5)
        XCTAssertEqual(invalidationCount, 0)
    }

    /// A remote source nobody has fetched has no knowable aspect ratio, so it
    /// reserves the default box and corrects itself exactly once.
    func testRemoteImageReservesDefaultAspectRatioThenCorrectsOnce() async throws {
        let store = makeStubStore(pixelSize: CGSize(width: 800, height: 200))
        let document = AppMarkdownParser().documentPreservingSource(for: "![Remote](https://example.com/wide.png)")
        let view = AppKitMarkdownView(document: document, imageStore: store)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 500)
        view.layoutSubtreeIfNeeded()
        let imageView = try XCTUnwrap(view.descendants(of: AppKitMarkdownImageBlockView.self).first)
        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 320, height: 180))

        var invalidationCount = 0
        view.onHeightInvalidated = {
            invalidationCount += 1
        }
        try await waitForLoadedImage(in: imageView)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(imageView.displaySizeForTesting, CGSize(width: 320, height: 80))
        XCTAssertEqual(invalidationCount, 1)
    }

    func testImageBlockOpenCallbackReceivesImageAndBaseURL() throws {
        let baseURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let document = AppMarkdownParser().documentPreservingSource(for: "![Diagram](images/diagram.png)")
        var openedSource: String?
        var openedBaseURL: URL?
        let view = AppKitMarkdownView(
            document: document,
            imageBaseURL: baseURL,
            imageStore: makeStubStore(),
            onOpenImage: { image, baseURL in
                openedSource = image.source
                openedBaseURL = baseURL
            }
        )
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        view.layoutSubtreeIfNeeded()

        let imageView = try XCTUnwrap(view.descendants(of: AppKitMarkdownImageBlockView.self).first)
        XCTAssertTrue(imageView.performOpenForTesting())
        XCTAssertEqual(openedSource, "images/diagram.png")
        XCTAssertEqual(openedBaseURL, baseURL)
    }

    private func localImageBlockView(
        pixelSize: CGSize,
        viewWidth: CGFloat
    ) throws -> AppKitMarkdownImageBlockView {
        let imageURL = try temporaryPNGURL(named: "local.png", pixelSize: pixelSize)
        let imageBaseURL = URL(fileURLWithPath: imageURL.deletingLastPathComponent().path, isDirectory: true)
        let document = AppMarkdownParser().documentPreservingSource(for: "![Local](local.png)")
        // A never-resolving loader keeps the assertion on the pre-load box.
        let view = AppKitMarkdownView(
            document: document,
            imageBaseURL: imageBaseURL,
            imageStore: AppMarkdownImageStore(loader: AppMarkdownPendingImageLoader(), diskCache: nil)
        )
        view.frame = NSRect(x: 0, y: 0, width: viewWidth, height: 900)
        view.layoutSubtreeIfNeeded()
        return try XCTUnwrap(view.descendants(of: AppKitMarkdownImageBlockView.self).first)
    }

    private func makeStubStore(pixelSize: CGSize = CGSize(width: 40, height: 20)) -> AppMarkdownImageStore {
        AppMarkdownImageStore(loader: FixedSizeImageLoader(pixelSize: pixelSize), diskCache: nil)
    }

    private func temporaryPNGURL(named filename: String, pixelSize: CGSize) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let imageURL = directoryURL.appendingPathComponent(filename)
        try appMarkdownTestPNGData(width: Int(pixelSize.width), height: Int(pixelSize.height)).write(to: imageURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return imageURL
    }

    private func waitForLoadedImage(
        in imageView: AppKitMarkdownImageBlockView
    ) async throws {
        for _ in 0..<50 {
            if imageView.loadedImageForTesting != nil {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Image did not load.")
    }
}

/// Loader that always answers with a bitmap of a chosen pixel size.
private struct FixedSizeImageLoader: BlockInputImageLoading {
    let pixelSize: CGSize

    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        return try BlockInputLoadedImage(
            data: appMarkdownTestPNGData(width: width, height: height),
            dimensions: BlockInputImageDimensions(width: width, height: height)
        )
    }
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
