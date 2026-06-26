@preconcurrency import AppKit
import BlockInputKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct AppImagePreviewLoadedImage {
    let image: NSImage
    let pixelSize: CGSize
}

final class AppImagePreviewLoader {
    static let maximumSourceBytes = 20 * 1024 * 1024
    static let maximumPixelDimension = 8_192

    private let blockInputLoader = BlockInputDefaultImageLoader()
    private let diskCache = BlockInputDefaultImageDiskCache()

    func load(_ request: AppImagePreviewRequest) async throws -> AppImagePreviewLoadedImage {
        switch request.source {
        case .fileURL(let url):
            return try await loadFileURL(url)
        case .remoteURL(let url):
            return try await loadRemoteURL(url)
        case .markdownImage(let image, let baseURL):
            return try await loadMarkdownImage(image, baseURL: baseURL)
        case .dataURL(let value):
            return try Self.decode(data: Self.data(fromDataURL: value), label: request.title)
        case .base64ImageData(let data):
            return try Self.decode(data: data, label: request.title)
        case .toolResultImage(_, let payload, let baseURL):
            return try await loadToolResultPayload(payload, baseURL: baseURL, title: request.title)
        }
    }

    private func loadFileURL(_ url: URL) async throws -> AppImagePreviewLoadedImage {
        let data = try Self.data(fromFileURL: url)
        return try Self.decode(data: data, label: url.lastPathComponent)
    }

    private func loadRemoteURL(_ url: URL) async throws -> AppImagePreviewLoadedImage {
        let image = BlockInputImage(source: url.absoluteString)
        return try await loadMarkdownImage(image, baseURL: nil)
    }

    private func loadMarkdownImage(
        _ image: BlockInputImage,
        baseURL: URL?
    ) async throws -> AppImagePreviewLoadedImage {
        guard let resolvedURL = AppMarkdownImageSourceResolver.resolvedURL(for: image.source, baseURL: baseURL) else {
            throw AppImagePreviewError.unsupportedSource
        }
        if resolvedURL.scheme?.lowercased() == "data" {
            return try Self.decode(data: Self.data(fromDataURL: resolvedURL.absoluteString), label: image.altText)
        }
        let request = BlockInputImageLoadRequest(
            image: image,
            resolvedURL: resolvedURL,
            cacheKey: image.cacheKey(resolvedURL: resolvedURL, maximumPixelDimension: Self.maximumPixelDimension),
            maxSourceBytes: Self.maximumSourceBytes,
            maxPixelDimension: Self.maximumPixelDimension,
            diskCache: diskCache
        )
        let loaded = try await blockInputLoader.loadImage(request)
        return try Self.decode(data: loaded.data, label: image.altText)
    }

    private func loadToolResultPayload(
        _ payload: String,
        baseURL: URL?,
        title: String
    ) async throws -> AppImagePreviewLoadedImage {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppImagePreviewError.unsupportedSource
        }

        if trimmed.lowercased().hasPrefix("data:image/") {
            return try Self.decode(data: Self.data(fromDataURL: trimmed), label: title)
        }
        if let url = AppMarkdownImageSourceResolver.resolvedURL(for: trimmed, baseURL: baseURL),
           let preview = AppImagePreviewRequest.supportedURL(url, title: title) {
            return try await load(preview)
        }
        if let data = Data(base64Encoded: trimmed.appImagePreviewBase64Body) {
            return try Self.decode(data: data, label: title)
        }
        throw AppImagePreviewError.unsupportedSource
    }

    private static func data(fromFileURL fileURL: URL) throws -> Data {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        if values.isRegularFile == false {
            throw AppImagePreviewError.unsupportedSource
        }
        if let fileSize = values.fileSize,
           fileSize > maximumSourceBytes {
            throw AppImagePreviewError.sourceTooLarge(maximumSourceBytes)
        }
        return try Data(contentsOf: fileURL)
    }

    private static func decode(data: Data, label: String) throws -> AppImagePreviewLoadedImage {
        guard data.count <= maximumSourceBytes else {
            throw AppImagePreviewError.sourceTooLarge(maximumSourceBytes)
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            throw AppImagePreviewError.decodeFailed
        }
        return try decode(source: source, label: label)
    }

    private static func decode(source: CGImageSource, label: String) throws -> AppImagePreviewLoadedImage {
        guard let type = CGImageSourceGetType(source),
              UTType(type as String)?.conforms(to: .image) == true else {
            throw AppImagePreviewError.unsupportedSource
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw AppImagePreviewError.decodeFailed
        }
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: pixelSize)
        image.accessibilityDescription = label
        return AppImagePreviewLoadedImage(image: image, pixelSize: pixelSize)
    }

    private static func data(fromDataURL value: String) throws -> Data {
        guard let commaIndex = value.firstIndex(of: ",") else {
            throw AppImagePreviewError.unsupportedSource
        }
        let header = value[..<commaIndex].lowercased()
        guard header.hasPrefix("data:image/") else {
            throw AppImagePreviewError.unsupportedSource
        }
        let body = String(value[value.index(after: commaIndex)...])
        if header.contains(";base64") {
            guard let data = Data(base64Encoded: body.appImagePreviewBase64Body) else {
                throw AppImagePreviewError.decodeFailed
            }
            return data
        }
        guard let decoded = body.removingPercentEncoding,
              let data = decoded.data(using: .utf8) else {
            throw AppImagePreviewError.decodeFailed
        }
        return data
    }
}

enum AppImagePreviewError: LocalizedError, Equatable {
    case unsupportedSource
    case sourceTooLarge(Int)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            return "This image source is not supported."
        case .sourceTooLarge(let bytes):
            return "This image is larger than the \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) preview limit."
        case .decodeFailed:
            return "The image could not be decoded."
        }
    }
}

private extension String {
    var appImagePreviewBase64Body: String {
        components(separatedBy: .whitespacesAndNewlines).joined()
    }
}
