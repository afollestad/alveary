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

    /// A remote image that 404s can start existing later (GitHub attachments
    /// stay session-gated until their embedding content propagates), so a
    /// failure must become retryable once the retry interval passes.
    func testFailedSourceRetriesAfterTheRetryInterval() async throws {
        let clock = MutableTestClock()
        let loader = SwitchableImageLoader(result: .failure)
        let store = AppMarkdownImageStore(loader: loader, diskCache: nil, now: { clock.now })
        let image = BlockInputImage(source: "https://example.com/p1.png")

        store.ensureLoad(for: image, baseURL: nil)
        try await waitForResolution(of: image.source, in: store)
        XCTAssertTrue(store.hasFailed(source: image.source))

        // Inside the window the cached failure is authoritative.
        store.ensureLoad(for: image, baseURL: nil)
        XCTAssertEqual(loader.requests.value.count, 1)

        clock.advance(by: 31)
        loader.result.set(.success)
        store.ensureLoad(for: image, baseURL: nil)
        try await waitForLoadedImage(of: image.source, in: store)

        XCTAssertNotNil(store.image(forSource: image.source))
        XCTAssertEqual(loader.requests.value.count, 2)
    }

    /// A failed direct fetch consults the fallback provider (signed GitHub
    /// attachment URLs) and retries under the *original* cache key, so the
    /// bytes persist for the plain source on future launches.
    func testFallbackURLProviderRescuesFailedRemoteLoad() async throws {
        let loader = FallbackHostImageLoader(succeedingHost: "fallback.example")
        let store = AppMarkdownImageStore(loader: loader, diskCache: nil)
        store.remoteFallbackURLProvider = { _ in
            URL(string: "https://fallback.example/signed.png")
        }
        let image = BlockInputImage(source: "https://example.com/gated.png")

        store.ensureLoad(for: image, baseURL: nil)
        try await waitForLoadedImage(of: image.source, in: store)

        XCTAssertNotNil(store.image(forSource: image.source))
        let requests = loader.requests.value
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.resolvedURL.host(), "fallback.example")
        XCTAssertEqual(requests.first?.cacheKey, requests.last?.cacheKey)
    }

    func testSeedRemoteImageMarksSourceLoadedAndWritesTheSharedDiskCacheKey() async throws {
        let diskCache = RecordingImageDiskCache()
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .failure), diskCache: diskCache)
        let data = try appMarkdownTestPNGData(width: 12, height: 8)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString).png")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let source = "https://github.com/user-attachments/assets/abc"

        await store.seedRemoteImage(source: source, fileURL: fileURL)

        XCTAssertNotNil(store.image(forSource: source))
        let stored = await diskCache.storedEntries
        // The exact key every default consumer derives (store, BlockInputKit
        // editors, preview modal) — a drift here silently unshares the cache.
        XCTAssertEqual(stored.first?.key, "default-v1|\(source)|8192")
        XCTAssertEqual(stored.first?.entry.data, data)
        XCTAssertEqual(stored.first?.entry.dimensions, BlockInputImageDimensions(width: 12, height: 8))
    }

    /// The reported upload flow: render fails while the fresh asset is still
    /// session-gated, then the upload completion seeds the local bytes.
    func testSeedRemoteImageReplacesAnEarlierFailure() async throws {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .failure), diskCache: nil)
        let source = "https://github.com/user-attachments/assets/abc"
        store.ensureLoad(for: BlockInputImage(source: source), baseURL: nil)
        try await waitForResolution(of: source, in: store)
        XCTAssertTrue(store.hasFailed(source: source))

        let data = try appMarkdownTestPNGData(width: 4, height: 4)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString).png")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await store.seedRemoteImage(source: source, fileURL: fileURL)

        XCTAssertFalse(store.hasFailed(source: source))
        XCTAssertNotNil(store.image(forSource: source))
    }

    private func waitForLoadedImage(of source: String, in store: AppMarkdownImageStore) async throws {
        for _ in 0..<40 {
            if store.image(forSource: source) != nil {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Image did not load for \(source).")
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

/// Injectable clock so retry-interval tests advance time without sleeping.
private final class MutableTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000)

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Loader whose result can flip between calls, recording every request.
private struct SwitchableImageLoader: BlockInputImageLoading {
    let result: LockedBox<StubImageLoader.Result>
    let requests = LockedBox<[BlockInputImageLoadRequest]>([])

    init(result: StubImageLoader.Result) {
        self.result = LockedBox(result)
    }

    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        requests.mutate { $0.append(request) }
        switch result.value {
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

/// Loader that succeeds only for one host, so fallback-URL retries are
/// distinguishable from the failing direct fetch.
private struct FallbackHostImageLoader: BlockInputImageLoading {
    let succeedingHost: String
    let requests = LockedBox<[BlockInputImageLoadRequest]>([])

    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        requests.mutate { $0.append(request) }
        guard request.resolvedURL.host() == succeedingHost else {
            throw StubImageLoaderError.failed
        }
        return try BlockInputLoadedImage(
            data: appMarkdownTestPNGData(width: 40, height: 20),
            dimensions: BlockInputImageDimensions(width: 40, height: 20)
        )
    }
}

private actor RecordingImageDiskCache: BlockInputImageDiskCaching {
    private(set) var storedEntries: [(key: String, entry: BlockInputImageDiskCacheEntry)] = []

    func cachedImage(forKey key: String) async throws -> BlockInputImageDiskCacheEntry? {
        nil
    }

    func storeImage(_ entry: BlockInputImageDiskCacheEntry, forKey key: String) async throws {
        storedEntries.append((key: key, entry: entry))
    }

    func cleanup() async throws {}
}

/// Lock-guarded mutable box usable from `Sendable` loader stubs.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.withLock { storage }
    }

    func set(_ value: Value) {
        lock.withLock { storage = value }
    }

    func mutate(_ change: (inout Value) -> Void) {
        lock.withLock { change(&storage) }
    }
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
