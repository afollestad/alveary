import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import Alveary

final class DiffImagePreviewLoaderTests: XCTestCase {
    func testLoadsDownsampledPreviewAndRecordsBlobCall() async throws {
        let cacheDirectory = temporaryDirectory().appendingPathComponent("cache", isDirectory: true)
        let loader = DiffImagePreviewLoader(cacheDirectory: cacheDirectory)
        let imageData = try Self.pngData(width: 32, height: 16)
        let gitService = DiffViewerMockGitService(
            statusResults: [.success([])],
            imageBlobResults: [.success(imageData)]
        )
        let version = DiffImageVersion(
            source: .commit(hash: "abc123", path: "Assets/logo.png"),
            side: .new,
            identityPrefix: "abc123",
            fileIdentity: "Assets/logo.png",
            fileExtension: "png",
            needsContentHash: false
        )

        let output = try await loader.loadPreview(version: version, directory: "/tmp/project", gitService: gitService)

        XCTAssertEqual(output.pixelSize, CGSize(width: 32, height: 16))
        let calls = await gitService.imageBlobCalls()
        XCTAssertEqual(calls.map(\.source), [.commit(hash: "abc123", path: "Assets/logo.png")])
    }

    func testStablePreviewUsesDiskCacheWithoutReloadingBlob() async throws {
        let root = temporaryDirectory()
        let cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)
        let imageData = try Self.pngData(width: 12, height: 12)
        let version = DiffImageVersion(
            source: .commit(hash: "abc123", path: "Assets/logo.png"),
            side: .new,
            identityPrefix: "abc123",
            fileIdentity: "Assets/logo.png",
            fileExtension: "png",
            needsContentHash: false
        )

        let firstLoader = DiffImagePreviewLoader(cacheDirectory: cacheDirectory)
        let firstGitService = DiffViewerMockGitService(
            statusResults: [.success([])],
            imageBlobResults: [.success(imageData)]
        )
        _ = try await firstLoader.loadPreview(version: version, directory: "/tmp/project", gitService: firstGitService)
        await waitForDiskCacheFile(
            named: DiffImagePreviewIdentity.fileName(for: version, contentHash: nil, extension: "png"),
            in: cacheDirectory
        )

        let secondLoader = DiffImagePreviewLoader(cacheDirectory: cacheDirectory)
        let secondGitService = DiffViewerMockGitService(
            statusResults: [.success([])],
            imageBlobResults: [.failure(GitError.commandFailed("should not load"))]
        )
        let cached = try await secondLoader.loadPreview(version: version, directory: "/tmp/project", gitService: secondGitService)

        XCTAssertEqual(cached.pixelSize, CGSize(width: 12, height: 12))
        let imageBlobCalls = await secondGitService.imageBlobCalls()
        XCTAssertTrue(imageBlobCalls.isEmpty)
    }

    func testParallelLoadsDoNotBlockEachOther() async throws {
        let cacheDirectory = temporaryDirectory().appendingPathComponent("cache", isDirectory: true)
        let loader = DiffImagePreviewLoader(cacheDirectory: cacheDirectory)
        let first = Self.version(path: "Assets/first.png")
        let second = Self.version(path: "Assets/second.png")
        let gitService = DiffViewerMockGitService(
            statusResults: [.success([])],
            imageBlobResults: [
                .success(try Self.pngData(width: 10, height: 10)),
                .success(try Self.pngData(width: 12, height: 12))
            ]
        )

        async let firstOutput = loader.loadPreview(version: first, directory: "/tmp/project", gitService: gitService)
        async let secondOutput = loader.loadPreview(version: second, directory: "/tmp/project", gitService: gitService)
        let outputs = try await [firstOutput.pixelSize, secondOutput.pixelSize]

        XCTAssertEqual(Set(outputs), [CGSize(width: 10, height: 10), CGSize(width: 12, height: 12)])
        let calls = await gitService.imageBlobCalls()
        XCTAssertEqual(calls.count, 2)
    }

    func testLoadCancellationStopsBeforeDecodeAndCacheWrite() async throws {
        let cacheDirectory = temporaryDirectory().appendingPathComponent("cache", isDirectory: true)
        let loader = DiffImagePreviewLoader(cacheDirectory: cacheDirectory)
        let version = Self.version(path: "Assets/cancelled.png")
        let gitService = DiffViewerMockGitService(
            statusResults: [.success([])],
            imageBlobResults: [.success(try Self.pngData(width: 10, height: 10))],
            imageBlobDelays: [.milliseconds(200)]
        )

        let task = Task {
            try await loader.loadPreview(version: version, directory: "/tmp/project", gitService: gitService)
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        let fileName = DiffImagePreviewIdentity.fileName(for: version, contentHash: nil, extension: "png")
        await waitForDiskCacheAbsence(named: fileName, in: cacheDirectory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent(fileName).path))
    }

    func testDiskCachePrunesOldEntriesInBackground() async throws {
        let cacheDirectory = temporaryDirectory().appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let staleURL = cacheDirectory.appendingPathComponent("stale.png")
        try Data(repeating: 1, count: 128).write(to: staleURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: staleURL.path
        )
        let cache = DiffImagePreviewDiskCache(
            cacheDirectory: cacheDirectory,
            tempDirectory: temporaryDirectory(),
            maxDiskBytes: 1
        )
        let imageData = try Self.pngData(width: 4, height: 4)
        let image = try XCTUnwrap(CGImageSourceCreateWithData(imageData as CFData, nil).flatMap {
            CGImageSourceCreateImageAtIndex($0, 0, nil)
        })

        cache.store(image: image, named: "fresh.png")

        await waitForDiskCacheAbsence(named: "stale.png", in: cacheDirectory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleURL.path))
    }

    func testMaterializeUsesFullPathIdentityAndStableHashForLongNames() async throws {
        let root = temporaryDirectory()
        let loader = DiffImagePreviewLoader(tempDirectory: root.appendingPathComponent("open", isDirectory: true))
        let version = DiffImageVersion(
            source: .commit(hash: "abc123", path: "Sources/Assets/logo.png"),
            side: .new,
            identityPrefix: "abc123",
            fileIdentity: String(repeating: "VeryLongFolderName/", count: 20) + "logo.png",
            fileExtension: "png",
            needsContentHash: false
        )
        let gitService = DiffViewerMockGitService(
            statusResults: [.success([])],
            imageBlobResults: [.success(try Self.pngData(width: 2, height: 2))]
        )

        let url = try await loader.materializeForOpening(version: version, directory: "/tmp/project", gitService: gitService)

        XCTAssertLessThanOrEqual(url.lastPathComponent.count, 180)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("abc123-VeryLongFolderName"))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".png"))
    }

    func testFileNameIncludesStableHashForSanitizedPathCollisions() {
        let slashPath = DiffImageVersion(
            source: .commit(hash: "abc123", path: "Assets/a/b.png"),
            side: .new,
            identityPrefix: "abc123",
            fileIdentity: "Assets/a/b.png",
            fileExtension: "png",
            needsContentHash: false
        )
        let dashPath = DiffImageVersion(
            source: .commit(hash: "abc123", path: "Assets/a-b.png"),
            side: .new,
            identityPrefix: "abc123",
            fileIdentity: "Assets/a-b.png",
            fileExtension: "png",
            needsContentHash: false
        )

        let slashName = DiffImagePreviewIdentity.fileName(for: slashPath, contentHash: nil, extension: "png")
        let dashName = DiffImagePreviewIdentity.fileName(for: dashPath, contentHash: nil, extension: "png")

        XCTAssertNotEqual(slashName, dashName)
        XCTAssertTrue(slashName.hasPrefix("abc123-Assets-a-b.png-new-"))
        XCTAssertTrue(dashName.hasPrefix("abc123-Assets-a-b.png-new-"))
    }

    func testFileNameSanitizesAndBoundsPathologicalExtensions() {
        let version = DiffImageVersion(
            source: .commit(hash: "abc123", path: "Assets/logo.png"),
            side: .new,
            identityPrefix: "abc123",
            fileIdentity: String(repeating: "Folder/", count: 30) + "logo.png",
            fileExtension: String(repeating: "bad extension/", count: 20),
            needsContentHash: false
        )

        let fileName = DiffImagePreviewIdentity.fileName(for: version, contentHash: nil, extension: version.fileExtension)

        XCTAssertLessThanOrEqual(fileName.count, 180)
        XCTAssertFalse(fileName.contains("/"))
        XCTAssertTrue(fileName.hasSuffix(".bad-extension-bad-extens"))
    }

    func testMaterializeOpensWorktreeImageDirectlyWithoutTempCopy() async throws {
        let root = temporaryDirectory()
        let tempDirectory = root.appendingPathComponent("open", isDirectory: true)
        let loader = DiffImagePreviewLoader(tempDirectory: tempDirectory)
        let version = DiffImageVersion(
            source: .worktree(path: "Assets/new-logo.png"),
            side: .new,
            identityPrefix: "abc123-worktree",
            fileIdentity: "Assets/new-logo.png",
            fileExtension: "png",
            needsContentHash: true
        )
        let gitService = DiffViewerMockGitService(
            statusResults: [.success([])],
            imageBlobResults: [.failure(GitError.commandFailed("should not load"))]
        )

        let url = try await loader.materializeForOpening(version: version, directory: "/tmp/project", gitService: gitService)

        XCTAssertEqual(url.path, "/tmp/project/Assets/new-logo.png")
        let imageBlobCalls = await gitService.imageBlobCalls()
        XCTAssertTrue(imageBlobCalls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func waitForDiskCacheFile(named fileName: String, in directory: URL) async {
        let fileURL = directory.appendingPathComponent(fileName)
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: fileURL.path) {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitForDiskCacheAbsence(named fileName: String, in directory: URL) async {
        let fileURL = directory.appendingPathComponent(fileName)
        for _ in 0..<100 where FileManager.default.fileExists(atPath: fileURL.path) {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func version(path: String) -> DiffImageVersion {
        DiffImageVersion(
            source: .commit(hash: "abc123", path: path),
            side: .new,
            identityPrefix: "abc123",
            fileIdentity: path,
            fileExtension: "png",
            needsContentHash: false
        )
    }

    private static func pngData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DiffImagePreviewLoaderError.unsupportedImage
        }

        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw DiffImagePreviewLoaderError.unsupportedImage
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw DiffImagePreviewLoaderError.unsupportedImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DiffImagePreviewLoaderError.unsupportedImage
        }
        return data as Data
    }
}
