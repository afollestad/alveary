import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct DiffImagePreviewOutput: @unchecked Sendable {
    let image: CGImage
    let pixelSize: CGSize
}

final class DiffImagePreviewLoader: @unchecked Sendable {
    static let shared = DiffImagePreviewLoader()

    private let memoryCache = NSCache<NSString, DiffImagePreviewCacheBox>()
    private let diskCache: DiffImagePreviewDiskCache

    init(
        cacheDirectory: URL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Alveary/DiffImagePreviews", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("AlvearyDiffImagePreviews", isDirectory: true),
        tempDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("AlvearyDiffImagePreviewOpen", isDirectory: true),
        diskCacheMaxBytes: Int = 256 * 1024 * 1024
    ) {
        memoryCache.totalCostLimit = DiffImagePreviewSupport.memoryCacheCostLimit
        diskCache = DiffImagePreviewDiskCache(
            cacheDirectory: cacheDirectory,
            tempDirectory: tempDirectory,
            maxDiskBytes: diskCacheMaxBytes
        )
    }

    func loadPreview(
        version: DiffImageVersion,
        directory: String,
        gitService: GitService
    ) async throws -> DiffImagePreviewOutput {
        let stableFileName = version.needsContentHash
            ? nil
            : DiffImagePreviewIdentity.fileName(for: version, contentHash: nil, extension: "png")

        if let stableFileName,
           let cached = await cachedPreview(named: stableFileName) {
            return cached
        }

        // Mutable sources need their content hash before we can address the
        // disk cache, so they intentionally pay one bounded blob read first.
        let data = try await gitService.imageBlob(
            source: version.source,
            maxBytes: DiffImagePreviewSupport.maxSourceBytes,
            in: directory
        )
        try Task.checkCancellation()

        let contentHash = version.needsContentHash ? DiffImagePreviewIdentity.contentHash(for: data) : nil
        let cacheFileName = DiffImagePreviewIdentity.fileName(for: version, contentHash: contentHash, extension: "png")
        if let cached = await cachedPreview(named: cacheFileName) {
            return cached
        }

        let decoded = try await decodePreview(data: data)
        try Task.checkCancellation()
        memoryCache.setObject(
            DiffImagePreviewCacheBox(output: decoded),
            forKey: cacheFileName as NSString,
            cost: decoded.memoryCost
        )
        diskCache.store(image: decoded.image, named: cacheFileName)
        return decoded
    }

    func materializeForOpening(
        version: DiffImageVersion,
        directory: String,
        gitService: GitService
    ) async throws -> URL {
        if case .worktree(let path) = version.source {
            return URL(fileURLWithPath: directory).appendingPathComponent(path)
        }

        let data = try await gitService.imageBlob(
            source: version.source,
            maxBytes: DiffImagePreviewSupport.maxSourceBytes,
            in: directory
        )
        try Task.checkCancellation()

        let contentHash = version.needsContentHash ? DiffImagePreviewIdentity.contentHash(for: data) : nil
        let fileName = DiffImagePreviewIdentity.fileName(
            for: version,
            contentHash: contentHash,
            extension: version.fileExtension
        )
        return try await diskCache.materializeTempFile(data: data, named: fileName)
    }

    func cachedPreview(named fileName: String) async -> DiffImagePreviewOutput? {
        if let cached = memoryCache.object(forKey: fileName as NSString)?.output {
            return cached
        }

        guard let output = await diskCache.load(named: fileName) else {
            return nil
        }

        memoryCache.setObject(
            DiffImagePreviewCacheBox(output: output),
            forKey: fileName as NSString,
            cost: output.memoryCost
        )
        return output
    }

    private func decodePreview(data: Data) async throws -> DiffImagePreviewOutput {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, options),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                  let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
                  width > 0,
                  height > 0,
                  width.isFinite,
                  height.isFinite else {
                throw DiffImagePreviewLoaderError.unsupportedImage
            }

            let maxDimension = max(width, height)
            let boundedThumbnailDimension = min(maxDimension, CGFloat(DiffImagePreviewSupport.maxPreviewPixelDimension))
            let thumbnailDimension = Int(boundedThumbnailDimension.rounded(.up))
            let decodeOptions = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: thumbnailDimension
            ] as CFDictionary

            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions) else {
                throw DiffImagePreviewLoaderError.unsupportedImage
            }

            try Task.checkCancellation()
            return DiffImagePreviewOutput(
                image: image,
                pixelSize: CGSize(width: image.width, height: image.height)
            )
        }.value
    }
}

enum DiffImagePreviewLoaderError: Error, LocalizedError {
    case unsupportedImage

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            return "This image could not be decoded."
        }
    }
}

private final class DiffImagePreviewCacheBox {
    let output: DiffImagePreviewOutput

    init(output: DiffImagePreviewOutput) {
        self.output = output
    }
}

private extension DiffImagePreviewOutput {
    var memoryCost: Int {
        image.width * image.height * 4
    }
}

final class DiffImagePreviewDiskCache: @unchecked Sendable {
    private let cacheDirectory: URL
    private let tempDirectory: URL
    private let maxDiskBytes: Int

    init(cacheDirectory: URL, tempDirectory: URL, maxDiskBytes: Int = 256 * 1024 * 1024) {
        self.cacheDirectory = cacheDirectory
        self.tempDirectory = tempDirectory
        self.maxDiskBytes = maxDiskBytes
    }

    func load(named fileName: String) async -> DiffImagePreviewOutput? {
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        return await Task.detached(priority: .utility) {
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, options),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
                return nil
            }
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
            return DiffImagePreviewOutput(
                image: image,
                pixelSize: CGSize(width: image.width, height: image.height)
            )
        }.value
    }

    func store(image: CGImage, named fileName: String) {
        Task.detached(priority: .utility) { [cacheDirectory, maxDiskBytes] in
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let fileURL = cacheDirectory.appendingPathComponent(fileName)
            guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                return
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                return
            }

            Self.prune(directory: cacheDirectory, maxBytes: maxDiskBytes)
        }
    }

    func materializeTempFile(data: Data, named fileName: String) async throws -> URL {
        try await Task.detached(priority: .utility) { [tempDirectory] in
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            let fileURL = tempDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        }.value
    }

    private static func prune(directory: URL, maxBytes: Int) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let entries = files.compactMap { url -> DiffImagePreviewDiskCacheEntry? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return nil
            }
            return DiffImagePreviewDiskCacheEntry(
                url: url,
                modified: values.contentModificationDate ?? .distantPast,
                size: values.fileSize ?? 0
            )
        }

        var totalBytes = entries.reduce(0) { $0 + $1.size }
        for entry in entries.sorted(by: { $0.modified < $1.modified }) where totalBytes > maxBytes {
            try? fileManager.removeItem(at: entry.url)
            totalBytes -= entry.size
        }
    }
}

private struct DiffImagePreviewDiskCacheEntry {
    let url: URL
    let modified: Date
    let size: Int
}
