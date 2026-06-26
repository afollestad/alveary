import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppImagePreviewTests: XCTestCase {
    func testAppStatePresentsAndDismissesImagePreviewRequest() {
        let appState = AppState()
        let request = AppImagePreviewRequest.fileURL(URL(fileURLWithPath: "/tmp/example.png"))

        appState.presentImagePreview(request)
        XCTAssertEqual(appState.imagePreviewRequest, request)

        appState.dismissImagePreview()
        XCTAssertNil(appState.imagePreviewRequest)
    }

    func testSupportedURLReturnsPreviewOnlyForImageSources() throws {
        XCTAssertNotNil(AppImagePreviewRequest.supportedURL(URL(fileURLWithPath: "/tmp/example.png")))
        XCTAssertNotNil(AppImagePreviewRequest.supportedURL(try XCTUnwrap(URL(string: "https://example.com/image.jpg"))))
        XCTAssertNil(AppImagePreviewRequest.supportedURL(try XCTUnwrap(URL(string: "https://example.com/download"))))
        XCTAssertNil(AppImagePreviewRequest.supportedURL(try XCTUnwrap(URL(string: "mailto:test@example.com"))))
    }

    func testLoaderDecodesDataURL() async throws {
        let request = AppImagePreviewRequest.dataURL("data:image/png;base64,\(Self.tinyPNGBase64)")

        let loaded = try await AppImagePreviewLoader().load(request)

        XCTAssertEqual(loaded.pixelSize, CGSize(width: 1, height: 1))
        XCTAssertEqual(loaded.image.size, CGSize(width: 1, height: 1))
    }

    func testLoaderRejectsUnsupportedDataURL() async {
        let request = AppImagePreviewRequest.dataURL("data:text/plain;base64,SGVsbG8=")

        do {
            _ = try await AppImagePreviewLoader().load(request)
            XCTFail("Expected unsupported source error.")
        } catch {
            XCTAssertEqual(error as? AppImagePreviewError, .unsupportedSource)
        }
    }

    func testZoomViewFitMagnificationUsesVisibleBounds() throws {
        let view = AppImagePreviewScrollView()

        XCTAssertEqual(
            try XCTUnwrap(view.fittedMagnificationForTesting(
                imageSize: NSSize(width: 200, height: 100),
                visibleSize: NSSize(width: 100, height: 100)
            )),
            0.5,
            accuracy: 0.01
        )
        XCTAssertEqual(
            try XCTUnwrap(view.fittedMagnificationForTesting(
                imageSize: NSSize(width: 50, height: 50),
                visibleSize: NSSize(width: 100, height: 100)
            )),
            1,
            accuracy: 0.01
        )
        XCTAssertNil(
            view.fittedMagnificationForTesting(
                imageSize: NSSize(width: 0, height: 100),
                visibleSize: NSSize(width: 100, height: 100)
            )
        )
    }

    func testZoomViewCommandsUpdateMagnification() {
        let view = AppImagePreviewScrollView()

        view.perform(.zoomIn)
        XCTAssertEqual(view.magnification, 1.2, accuracy: 0.01)

        view.perform(.zoomOut)
        XCTAssertEqual(view.magnification, 1, accuracy: 0.01)
    }

    func testZoomViewFitCommandDefersUntilVisibleBoundsExist() {
        let view = AppImagePreviewScrollView()
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))

        view.perform(.fit)

        XCTAssertTrue(view.hasPendingFitAfterLayoutForTesting)
    }

    func testZoomViewInitialLayoutFitsImageToVisibleBounds() {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))

        view.layoutSubtreeIfNeeded()

        XCTAssertFalse(view.hasPendingFitAfterLayoutForTesting)
        XCTAssertEqual(view.magnification, 0.5, accuracy: 0.01)
    }

    func testZoomViewFitCommandUsesViewportFrameAfterZooming() {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))
        view.layoutSubtreeIfNeeded()

        view.perform(.zoomIn)
        view.perform(.fit)

        XCTAssertFalse(view.hasPendingFitAfterLayoutForTesting)
        XCTAssertEqual(view.magnification, 0.5, accuracy: 0.01)
    }

    func testZoomViewFitCentersImageInViewport() {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.visibleDocumentCenterForTesting.x, 100, accuracy: 0.01)
        XCTAssertEqual(view.visibleDocumentCenterForTesting.y, 50, accuracy: 0.01)
    }

    func testZoomViewZoomOutKeepsImageCenteredWhenSmallerThanViewport() {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))
        view.layoutSubtreeIfNeeded()

        view.perform(.zoomOut)

        XCTAssertEqual(view.visibleDocumentCenterForTesting.x, 100, accuracy: 0.01)
        XCTAssertEqual(view.visibleDocumentCenterForTesting.y, 50, accuracy: 0.01)
    }

    func testZoomViewSizesDocumentUsingImageDisplaySize() throws {
        let image = NSImage(size: NSSize(width: 100, height: 50))
        let representation = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 200,
            pixelsHigh: 100,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        representation.size = image.size
        image.addRepresentation(representation)
        let view = AppImagePreviewScrollView()

        view.configure(image: image)

        XCTAssertEqual(view.documentViewSizeForTesting, image.size)
    }

    private static let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lC6x4wAAAABJRU5ErkJggg=="
}
