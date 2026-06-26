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
        view.perform(.actualSize)
        XCTAssertEqual(view.magnification, 1, accuracy: 0.01)

        view.perform(.zoomIn)
        XCTAssertEqual(view.magnification, 1.2, accuracy: 0.01)

        view.perform(.zoomOut)
        XCTAssertEqual(view.magnification, 1, accuracy: 0.01)
    }

    private static let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lC6x4wAAAABJRU5ErkJggg=="
}
