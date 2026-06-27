import AppKit
import UniformTypeIdentifiers
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

    func testAppShotRequestsExposeTextAndPlainImageRequestsDoNot() {
        let plain = AppImagePreviewRequest.fileURL(URL(fileURLWithPath: "/tmp/plain.png"))
        let appShot = AppImagePreviewRequest.appShotFileURL(
            URL(fileURLWithPath: "/tmp/appshot.png"),
            title: "App shot",
            axTreeText: "AX tree"
        )
        let whitespaceOnly = AppImagePreviewRequest.appShotFileURL(
            URL(fileURLWithPath: "/tmp/empty-appshot.png"),
            title: "App shot",
            axTreeText: " \n\t "
        )

        XCTAssertNil(plain.textPayload)
        XCTAssertEqual(appShot.textPayload?.text, "AX tree")
        XCTAssertNil(whitespaceOnly.textPayload)
    }

    func testPreviewLayoutUsesCurrentModalSizingPolicy() {
        XCTAssertEqual(
            AppImagePreviewLayout.viewportSize(for: CGSize(width: 2_000, height: 1_400)),
            CGSize(width: 1_120, height: 820)
        )
        XCTAssertEqual(
            AppImagePreviewLayout.viewportSize(for: CGSize(width: 300, height: 200)),
            CGSize(width: 320, height: 260)
        )
        XCTAssertEqual(
            AppImagePreviewLayout.viewportSize(for: CGSize(width: 900, height: 700)),
            CGSize(width: 820, height: 620)
        )
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
            0.4,
            accuracy: 0.01
        )
        XCTAssertEqual(
            try XCTUnwrap(view.fittedMagnificationForTesting(
                imageSize: NSSize(width: 50, height: 50),
                visibleSize: NSSize(width: 100, height: 100)
            )),
            0.8,
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

    func testZoomViewActualSizeCommandResetsToOneHundredPercent() {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.magnification, 0.4, accuracy: 0.01)

        view.perform(.actualSize)

        XCTAssertEqual(view.magnification, 1, accuracy: 0.01)
    }

    func testZoomDisplayScaleUsesModalBaselineAsOneHundredPercent() {
        XCTAssertEqual(
            AppImagePreviewZoomState(magnification: 0.8, fittedMagnification: 0.8).displayScale,
            1,
            accuracy: 0.01
        )
        XCTAssertEqual(
            AppImagePreviewZoomState(magnification: 0.96, fittedMagnification: 0.8).displayScale,
            1.2,
            accuracy: 0.01
        )
        XCTAssertEqual(
            AppImagePreviewZoomState(magnification: 1, fittedMagnification: 0.8).displayScale,
            1.25,
            accuracy: 0.01
        )
    }

    func testZoomViewReportsMagnificationChanges() async throws {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        var reportedStates: [AppImagePreviewZoomState] = []
        view.onZoomStateChanged = { reportedStates.append($0) }
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))

        view.layoutSubtreeIfNeeded()
        try await waitUntil("expected initial fitted magnification report", timeout: .seconds(1)) {
            reportedStates.containsMagnification(0.4) && reportedStates.containsDisplayScale(1)
        }

        view.perform(.zoomIn)
        try await waitUntil("expected zoom-in magnification report", timeout: .seconds(1)) {
            reportedStates.containsMagnification(0.48) && reportedStates.containsDisplayScale(1.2)
        }

        view.perform(.zoomOut)
        try await waitUntil("expected zoom-out magnification report", timeout: .seconds(1)) {
            reportedStates.lastMatchesMagnification(0.4) && reportedStates.lastMatchesDisplayScale(1)
        }

        view.perform(.actualSize)
        try await waitUntil("expected actual-size magnification report", timeout: .seconds(1)) {
            reportedStates.containsMagnification(1) && reportedStates.containsDisplayScale(2.5)
        }
    }

    func testZoomViewReportsDirectMagnificationChanges() async throws {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        var reportedStates: [AppImagePreviewZoomState] = []
        view.onZoomStateChanged = { reportedStates.append($0) }
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))
        view.layoutSubtreeIfNeeded()
        try await waitUntil("expected initial fitted magnification report", timeout: .seconds(1)) {
            reportedStates.containsMagnification(0.4)
        }

        view.setMagnification(0.75, centeredAt: view.visibleDocumentCenterForTesting)

        try await waitUntil("expected direct magnification report", timeout: .seconds(1)) {
            reportedStates.containsMagnification(0.75) && reportedStates.containsDisplayScale(1.875)
        }
    }

    func testZoomViewFitCommandDefersUntilVisibleBoundsExist() {
        let view = AppImagePreviewScrollView()
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))

        view.perform(.fit)

        XCTAssertTrue(view.hasPendingFitAfterLayoutForTesting)
    }

    func testZoomViewFitCommandWaitsForLaidOutBounds() {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))

        view.perform(.fit)

        XCTAssertTrue(view.hasPendingFitAfterLayoutForTesting)

        view.layoutSubtreeIfNeeded()

        XCTAssertFalse(view.hasPendingFitAfterLayoutForTesting)
        XCTAssertEqual(view.magnification, 0.4, accuracy: 0.01)
    }

    func testZoomViewFitCommandWaitsWhenScrollViewBoundsChangeBeforeLayout() {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.magnification, 0.4, accuracy: 0.01)

        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.perform(.fit)

        XCTAssertTrue(view.hasPendingFitAfterLayoutForTesting)

        view.layoutSubtreeIfNeeded()

        XCTAssertFalse(view.hasPendingFitAfterLayoutForTesting)
        XCTAssertEqual(view.magnification, 0.8, accuracy: 0.01)
    }

    func testZoomViewInitialLayoutFitsImageToVisibleBounds() {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))

        view.layoutSubtreeIfNeeded()

        XCTAssertFalse(view.hasPendingFitAfterLayoutForTesting)
        XCTAssertEqual(view.magnification, 0.4, accuracy: 0.01)
    }

    func testZoomViewFitCommandUsesViewportFrameAfterZooming() {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))
        view.layoutSubtreeIfNeeded()

        view.perform(.zoomIn)
        view.perform(.fit)

        XCTAssertFalse(view.hasPendingFitAfterLayoutForTesting)
        XCTAssertEqual(view.magnification, 0.4, accuracy: 0.01)
    }

    func testZoomViewFitCentersImageInViewport() {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.configure(image: NSImage(size: NSSize(width: 200, height: 100)))
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.visibleDocumentCenterForTesting.x, 100, accuracy: 0.01)
        XCTAssertEqual(view.visibleDocumentCenterForTesting.y, 50, accuracy: 0.01)
    }

    func testZoomViewBackgroundClickDismissesOnlyOutsideImage() {
        let view = AppImagePreviewScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.configure(image: NSImage(size: NSSize(width: 100, height: 100)))
        view.layoutSubtreeIfNeeded()

        let imagePoint = NSPoint(x: 100, y: 100)
        let backgroundPoint = NSPoint(x: 10, y: 10)
        XCTAssertTrue(view.imageContainsScrollViewPointForTesting(imagePoint))
        XCTAssertFalse(view.imageContainsScrollViewPointForTesting(backgroundPoint))

        var backgroundClickCount = 0
        view.onBackgroundClick = { backgroundClickCount += 1 }

        XCTAssertFalse(view.handleMouseDownInScrollViewForTesting(imagePoint))
        XCTAssertEqual(backgroundClickCount, 0)

        XCTAssertTrue(view.handleMouseDownInScrollViewForTesting(backgroundPoint))
        XCTAssertEqual(backgroundClickCount, 1)
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

    func testSaveDestinationDefaultsUseLocalTypePNGOrUnresolvedOriginalExtension() {
        let pngSource = URL(fileURLWithPath: "/tmp/source.png")
        let unresolvedSource = URL(fileURLWithPath: "/tmp/source.unknown-image-extension")

        let pngRequest = AppImagePreviewSaver.destinationRequest(
            for: .fileURL(pngSource),
            localSource: pngSource
        )
        let fallbackRequest = AppImagePreviewSaver.destinationRequest(
            for: .remoteURL(URL(string: "https://example.com/source")!, title: "Remote/Image"),
            localSource: nil
        )
        let fallbackWithExtensionRequest = AppImagePreviewSaver.destinationRequest(
            for: .remoteURL(URL(string: "https://example.com/source")!, title: "Remote.jpg"),
            localSource: nil
        )
        let unresolvedRequest = AppImagePreviewSaver.destinationRequest(
            for: .fileURL(unresolvedSource),
            localSource: unresolvedSource
        )

        XCTAssertEqual(pngRequest.suggestedFileName, "source.png")
        XCTAssertEqual(pngRequest.allowedContentTypes, [.png])
        XCTAssertEqual(fallbackRequest.suggestedFileName, "Remote-Image.png")
        XCTAssertEqual(fallbackRequest.allowedContentTypes, [.png])
        XCTAssertEqual(fallbackWithExtensionRequest.suggestedFileName, "Remote.png")
        XCTAssertEqual(fallbackWithExtensionRequest.allowedContentTypes, [.png])
        XCTAssertEqual(unresolvedRequest.suggestedFileName, "source.unknown-image-extension")
        XCTAssertNil(unresolvedRequest.allowedContentTypes)
    }

    func testSaveCancellationIsNoOp() async throws {
        let saver = AppImagePreviewSaver(destinationPicker: { _ in nil })

        let result = try await saver.save(
            request: .base64ImageData(Self.tinyPNGData),
            loadedImage: Self.loadedImage()
        )

        XCTAssertFalse(result)
    }

    func testSaveToSameLocalFileIsSuccessfulNoOp() async throws {
        let sourceURL = try Self.temporaryFileURL(named: "same-file.png", data: Self.tinyPNGData)
        let saver = AppImagePreviewSaver(destinationPicker: { _ in sourceURL })

        let result = try await saver.save(
            request: .fileURL(sourceURL),
            loadedImage: Self.loadedImage()
        )

        XCTAssertTrue(result)
        XCTAssertEqual(try Data(contentsOf: sourceURL), Self.tinyPNGData)
    }

    func testSaveReplacesExistingDestinationWhenCopyingLocalFile() async throws {
        let sourceData = Data("source-data".utf8)
        let sourceURL = try Self.temporaryFileURL(named: "copy-source.png", data: sourceData)
        let destinationURL = try Self.temporaryFileURL(named: "copy-destination.png", data: Data("old-data".utf8))
        let saver = AppImagePreviewSaver(destinationPicker: { _ in destinationURL })

        let result = try await saver.save(
            request: .fileURL(sourceURL),
            loadedImage: Self.loadedImage()
        )

        XCTAssertTrue(result)
        XCTAssertEqual(try Data(contentsOf: destinationURL), sourceData)
    }

    func testSaveWritesPNGWhenOriginalFileIsUnavailable() async throws {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlvearyTests-\(UUID().uuidString)")
            .appendingPathComponent("fallback-output.png")
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let saver = AppImagePreviewSaver(destinationPicker: { _ in destinationURL })

        let result = try await saver.save(
            request: .fileURL(URL(fileURLWithPath: "/tmp/missing-source.png")),
            loadedImage: Self.loadedImage()
        )

        XCTAssertTrue(result)
        XCTAssertTrue(try Data(contentsOf: destinationURL).starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    private static let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lC6x4wAAAABJRU5ErkJggg=="

    private static var tinyPNGData: Data {
        Data(base64Encoded: tinyPNGBase64)!
    }

    private static func loadedImage() -> AppImagePreviewLoadedImage {
        let image = NSImage(size: NSSize(width: 12, height: 10))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 10).fill()
        image.unlockFocus()
        return AppImagePreviewLoadedImage(
            image: image,
            pixelSize: CGSize(width: 12, height: 10)
        )
    }

    private static func temporaryFileURL(named filename: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlvearyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
}

private extension [AppImagePreviewZoomState] {
    func containsMagnification(_ expectedMagnification: CGFloat) -> Bool {
        contains { abs($0.magnification - expectedMagnification) <= 0.01 }
    }

    func containsDisplayScale(_ expectedDisplayScale: CGFloat) -> Bool {
        contains { abs($0.displayScale - expectedDisplayScale) <= 0.01 }
    }

    func lastMatchesMagnification(_ expectedMagnification: CGFloat) -> Bool {
        guard let last = last else {
            return false
        }
        return abs(last.magnification - expectedMagnification) <= 0.01
    }

    func lastMatchesDisplayScale(_ expectedDisplayScale: CGFloat) -> Bool {
        guard let last = last else {
            return false
        }
        return abs(last.displayScale - expectedDisplayScale) <= 0.01
    }
}
