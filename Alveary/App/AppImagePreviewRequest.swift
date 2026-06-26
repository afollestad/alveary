import BlockInputKit
import Foundation
import UniformTypeIdentifiers

struct AppImagePreviewRequest: Identifiable, Equatable {
    let id: UUID
    let title: String
    let source: Source

    init(
        id: UUID = UUID(),
        title: String,
        source: Source
    ) {
        self.id = id
        self.title = title
        self.source = source
    }

    enum Source: Equatable {
        case fileURL(URL)
        case remoteURL(URL)
        case markdownImage(BlockInputImage, baseURL: URL?)
        case dataURL(String)
        case base64ImageData(Data)
        case toolResultImage(toolName: String, payload: String, baseURL: URL?)
    }

    static func fileURL(_ url: URL, title: String? = nil) -> AppImagePreviewRequest {
        AppImagePreviewRequest(
            title: title ?? imageTitle(for: url),
            source: .fileURL(url.standardizedFileURL)
        )
    }

    static func remoteURL(_ url: URL, title: String? = nil) -> AppImagePreviewRequest {
        AppImagePreviewRequest(
            title: title ?? imageTitle(for: url),
            source: .remoteURL(url)
        )
    }

    static func dataURL(_ value: String, title: String = "Image") -> AppImagePreviewRequest {
        AppImagePreviewRequest(title: title, source: .dataURL(value))
    }

    static func base64ImageData(_ data: Data, title: String = "Image") -> AppImagePreviewRequest {
        AppImagePreviewRequest(title: title, source: .base64ImageData(data))
    }

    static func markdownImage(
        _ image: BlockInputImage,
        baseURL: URL?,
        title: String? = nil
    ) -> AppImagePreviewRequest {
        AppImagePreviewRequest(
            title: title ?? image.altText.nonEmptyTrimmed ?? image.source.nonEmptyTrimmed ?? "Image",
            source: .markdownImage(image, baseURL: baseURL)
        )
    }

    static func toolImageOutput(
        tool: ToolEntry,
        baseURL: URL? = nil
    ) -> AppImagePreviewRequest? {
        guard let payload = tool.output?.trimmingCharacters(in: .whitespacesAndNewlines),
              !payload.isEmpty else {
            return nil
        }
        return AppImagePreviewRequest(
            title: tool.name.isEmpty ? "Image output" : "\(tool.name) image output",
            source: .toolResultImage(toolName: tool.name, payload: payload, baseURL: baseURL)
        )
    }

    static func supportedURL(_ url: URL, title: String? = nil) -> AppImagePreviewRequest? {
        if url.isFileURL {
            guard isSupportedLocalImageURL(url) else {
                return nil
            }
            return fileURL(url, title: title)
        }

        guard let scheme = url.scheme?.lowercased() else {
            return nil
        }

        switch scheme {
        case "http", "https":
            guard isSupportedImagePathExtension(url.pathExtension) else {
                return nil
            }
            return remoteURL(url, title: title)
        case "data":
            let value = url.absoluteString
            guard value.lowercased().hasPrefix("data:image/") else {
                return nil
            }
            return dataURL(value, title: title ?? "Image")
        default:
            return nil
        }
    }

    static func isSupportedLocalImageURL(_ url: URL) -> Bool {
        if DefaultConversationAttachmentStore.isSupportedImageURL(url) {
            return true
        }
        return isSupportedImagePathExtension(url.pathExtension)
    }

    static func isSupportedImagePathExtension(_ pathExtension: String) -> Bool {
        let normalized = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return false
        }
        if UTType(filenameExtension: normalized)?.conforms(to: .image) == true {
            return true
        }
        return fallbackImageExtensions.contains(normalized)
    }

    private static func imageTitle(for url: URL) -> String {
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Image" : name
    }

    private static let fallbackImageExtensions: Set<String> = [
        "apng", "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg",
        "png", "tif", "tiff", "webp"
    ]
}

private extension String {
    var nonEmptyTrimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
