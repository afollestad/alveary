@preconcurrency import AppKit
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

        let view = AppKitMarkdownView(document: document, imageBaseURL: baseURL)
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        view.layoutSubtreeIfNeeded()

        let imageViews = view.descendants(of: AppKitMarkdownImageBlockView.self)
        XCTAssertEqual(imageViews.count, 2)
        XCTAssertEqual(imageViews[0].displaySizeForTesting.width, 420, accuracy: 0.5)
        XCTAssertEqual(imageViews[1].displaySizeForTesting, CGSize(width: 262, height: 174))
        XCTAssertFalse(view.descendants(of: NSTextView.self).map(\.string).contains { $0.contains("<img") })
    }

    func testImageLoadDoesNotInvalidateMarkdownHeight() async throws {
        let imageURL = try temporaryPNGURL(named: "tiny.png")
        let imageBaseURL = URL(fileURLWithPath: imageURL.deletingLastPathComponent().path, isDirectory: true)
        let document = AppMarkdownParser().documentPreservingSource(for: "![Tiny](tiny.png)")
        let view = AppKitMarkdownView(
            document: document,
            imageBaseURL: imageBaseURL
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
        XCTAssertEqual(view.intrinsicContentSize.height, initialHeight, accuracy: 0.5)
        XCTAssertEqual(invalidationCount, 0)
    }

    func testImageBlockOpenCallbackReceivesImageAndBaseURL() throws {
        let baseURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let document = AppMarkdownParser().documentPreservingSource(for: "![Diagram](images/diagram.png)")
        var openedSource: String?
        var openedBaseURL: URL?
        let view = AppKitMarkdownView(
            document: document,
            imageBaseURL: baseURL,
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

    private func temporaryPNGURL(named filename: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let imageURL = directoryURL.appendingPathComponent(filename)
        try Self.pngData().write(to: imageURL)
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

    private static func pngData() throws -> Data {
        try XCTUnwrap(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lC6x4wAAAABJRU5ErkJggg==")
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
