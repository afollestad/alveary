import AppKit
import BlockInputKit
import XCTest
@testable import Alveary

@MainActor
final class AppMarkdownImageStoreTests: XCTestCase {
    func testEnsureLoadStoresLoadedImage() async throws {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .success), diskCache: nil)

        store.ensureLoad(for: BlockInputImage(source: "https://example.com/p1.png"), baseURL: nil)
        try await waitForResolution(of: "https://example.com/p1.png", in: store)

        XCTAssertNotNil(store.image(forSource: "https://example.com/p1.png"))
        XCTAssertFalse(store.hasFailed(source: "https://example.com/p1.png"))
    }

    func testEnsureLoadRecordsFailure() async throws {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .failure), diskCache: nil)

        store.ensureLoad(for: BlockInputImage(source: "https://example.com/p1.png"), baseURL: nil)
        try await waitForResolution(of: "https://example.com/p1.png", in: store)

        XCTAssertNil(store.image(forSource: "https://example.com/p1.png"))
        XCTAssertTrue(store.hasFailed(source: "https://example.com/p1.png"))
    }

    func testEnsureLoadLoadsEachSourceOnce() async throws {
        let loader = StubImageLoader(result: .success)
        let store = AppMarkdownImageStore(loader: loader, diskCache: nil)
        let image = BlockInputImage(source: "https://example.com/p1.png")

        store.ensureLoad(for: image, baseURL: nil)
        store.ensureLoad(for: image, baseURL: nil)
        try await waitForResolution(of: image.source, in: store)
        store.ensureLoad(for: image, baseURL: nil)

        XCTAssertEqual(loader.requestCount.value, 1)
    }

    func testUnresolvableSourceFailsImmediately() {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .success), diskCache: nil)

        store.ensureLoad(for: BlockInputImage(source: ""), baseURL: nil)

        XCTAssertTrue(store.hasFailed(source: ""))
    }

    private func waitForResolution(of source: String, in store: AppMarkdownImageStore) async throws {
        for _ in 0..<40 {
            if store.image(forSource: source) != nil || store.hasFailed(source: source) {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Image state did not resolve for \(source).")
    }
}

private struct StubImageLoader: BlockInputImageLoading {
    enum Result {
        case success
        case failure
    }

    let result: Result
    let requestCount = StubLoadCounter()

    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        requestCount.increment()
        switch result {
        case .success:
            return try BlockInputLoadedImage(
                data: appMarkdownTestPNGData(width: 40, height: 20),
                dimensions: BlockInputImageDimensions(width: 40, height: 20)
            )
        case .failure:
            throw StubImageLoaderError.failed
        }
    }
}

private enum StubImageLoaderError: Error {
    case failed
}

private final class StubLoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

/// Builds a solid-color PNG whose pixel size equals its point size (72 DPI).
func appMarkdownTestPNGData(width: Int, height: Int, color: NSColor = .systemTeal) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw AppMarkdownImageFixtureError.invalidFixture
    }
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
        NSGraphicsContext.current = context
        color.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        context.flushGraphics()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw AppMarkdownImageFixtureError.invalidFixture
    }
    return data
}

enum AppMarkdownImageFixtureError: Error {
    case invalidFixture
}
