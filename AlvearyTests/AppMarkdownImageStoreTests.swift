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

    /// Header-only probing is what lets a local image reserve its real box on
    /// the first layout pass, before any load runs.
    func testNaturalSizeProbesLocalFileWithoutLoading() throws {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .success), diskCache: nil)
        let fileURL = try temporaryPNGURL(width: 120, height: 45)

        let size = store.naturalSize(for: BlockInputImage(source: fileURL.path), baseURL: nil)

        XCTAssertEqual(size, CGSize(width: 120, height: 45))
        XCTAssertNil(store.image(forSource: fileURL.path))
    }

    func testNaturalSizeResolvesRelativeSourceAgainstBaseURL() throws {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .success), diskCache: nil)
        let fileURL = try temporaryPNGURL(width: 64, height: 96)
        let baseURL = fileURL.deletingLastPathComponent()

        let size = store.naturalSize(for: BlockInputImage(source: fileURL.lastPathComponent), baseURL: baseURL)

        XCTAssertEqual(size, CGSize(width: 64, height: 96))
    }

    /// Declared dimensions are the author's intent, so probing for them would be
    /// wasted I/O; `appMarkdownResolved(naturalSize:)` ignores the answer anyway.
    func testNaturalSizeSkipsProbeWhenBothDimensionsAreDeclared() throws {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .success), diskCache: nil)
        let fileURL = try temporaryPNGURL(width: 120, height: 45)

        let image = BlockInputImage(source: fileURL.path, altText: "", width: 30, height: 20, sourceStyle: .html)

        XCTAssertNil(store.naturalSize(for: image, baseURL: nil))
    }

    func testNaturalSizeIsNilForRemoteSourceUntilItLoads() async throws {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .success), diskCache: nil)
        let image = BlockInputImage(source: "https://example.com/p1.png")
        XCTAssertNil(store.naturalSize(for: image, baseURL: nil))

        store.ensureLoad(for: image, baseURL: nil)
        try await waitForLoadedImage(of: image.source, in: store)

        XCTAssertEqual(store.naturalSize(for: image, baseURL: nil), CGSize(width: 40, height: 20))
    }

    /// A path the agent has not written yet must not be re-probed on every
    /// layout pass; the load path records the size once the file exists.
    func testMissingFileIsProbedOnlyOnce() throws {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .success), diskCache: nil)
        let directoryURL = try temporaryDirectoryURL()
        let fileURL = directoryURL.appendingPathComponent("later.png")
        let image = BlockInputImage(source: fileURL.path)
        XCTAssertNil(store.naturalSize(for: image, baseURL: nil))

        try appMarkdownTestPNGData(width: 30, height: 10).write(to: fileURL)

        XCTAssertNil(store.naturalSize(for: image, baseURL: nil))
    }

    /// Prepared-measurement keys carry this digest, so it has to move the moment
    /// a size resolves or the pre-resolution measurement sticks.
    func testLoadStateFingerprintCarriesResolvedDimensions() throws {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .success), diskCache: nil)
        let fileURL = try temporaryPNGURL(width: 120, height: 45)
        let markdown = "![Local](\(fileURL.lastPathComponent))"
        let baseURL = fileURL.deletingLastPathComponent()

        let unresolved = store.loadStateFingerprint(forMarkdown: markdown, baseURL: nil)
        let resolved = store.loadStateFingerprint(forMarkdown: markdown, baseURL: baseURL)

        XCTAssertEqual(unresolved, "n")
        XCTAssertEqual(resolved, "n120x45")
    }

    func testLoadStateFingerprintChangesWhenARemoteImageLoads() async throws {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .success), diskCache: nil)
        let markdown = "![Remote](https://example.com/p1.png)"
        let before = store.loadStateFingerprint(forMarkdown: markdown)

        store.ensureLoad(for: BlockInputImage(source: "https://example.com/p1.png"), baseURL: nil)
        try await waitForLoadedImage(of: "https://example.com/p1.png", in: store)

        XCTAssertEqual(before, "n")
        XCTAssertEqual(store.loadStateFingerprint(forMarkdown: markdown), "l40x20")
    }

    /// The SwiftUI table's grid layout caches column widths and keys them on this overload, so an
    /// image cell that resolves has to move the digest just as the markdown variant does.
    func testLoadStateFingerprintForImagesTracksALoad() async throws {
        let store = AppMarkdownImageStore(loader: StubImageLoader(result: .success), diskCache: nil)
        let image = BlockInputImage(source: "https://example.com/p1.png")
        let before = store.loadStateFingerprint(forImages: [image])

        store.ensureLoad(for: image, baseURL: nil)
        try await waitForLoadedImage(of: "https://example.com/p1.png", in: store)

        XCTAssertEqual(before, "n")
        XCTAssertEqual(store.loadStateFingerprint(forImages: [image]), "l40x20")
        XCTAssertEqual(store.loadStateFingerprint(forImages: []), "")
    }

    /// The invariant every snapshot baseline holding a fixture image depends on: a dark-mode host
    /// records the same bytes a light-mode CI runner renders. Filling with the dynamic color
    /// directly baked the host's variant in, and the two disagreed over the whole image area.
    func testFixturePNGBytesDoNotDependOnTheHostAppearance() throws {
        var perAppearance: [Data] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            var data: Data?
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                data = try? appMarkdownTestPNGData(width: 4, height: 4, color: .systemIndigo)
            }
            perAppearance.append(try XCTUnwrap(data))
        }

        XCTAssertEqual(perAppearance.first, perAppearance.last)
    }

    private func temporaryDirectoryURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL
    }

    private func temporaryPNGURL(width: Int, height: Int) throws -> URL {
        let fileURL = try temporaryDirectoryURL().appendingPathComponent("fixture.png")
        try appMarkdownTestPNGData(width: width, height: height).write(to: fileURL)
        return fileURL
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

/// Loader that never resolves, so a test can assert the box an image reserves
/// before its bitmap exists without any surface reaching the network.
struct AppMarkdownPendingImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw CancellationError()
    }
}

/// Builds a solid-color PNG whose pixel size equals its point size (72 DPI).
///
/// The fill resolves through `appearanceStableFixtureFillColor(_:)`, so the bytes are the same on
/// every machine — a snapshot baseline holding one of these images is compared pixel for pixel
/// against a CI run of the same test.
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
        appearanceStableFixtureFillColor(color).setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        context.flushGraphics()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw AppMarkdownImageFixtureError.invalidFixture
    }
    return data
}

/// Flattens a fill to concrete sRGB components under Aqua, because `NSColor.systemIndigo` and every
/// other system color is dynamic: a fixture built on a dark-mode machine bakes the dark variant into
/// its bytes, and a snapshot recorded there disagrees with a light-mode CI runner over the whole
/// image area — far past the perceptual tolerance for a saturated hue.
func appearanceStableFixtureFillColor(_ color: NSColor) -> NSColor {
    var resolved = color
    NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
        resolved = color.usingColorSpace(.sRGB) ?? color
    }
    return resolved
}

enum AppMarkdownImageFixtureError: Error {
    case invalidFixture
}
