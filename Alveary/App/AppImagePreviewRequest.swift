import BlockInputKit
import Foundation
import UniformTypeIdentifiers

struct AppImagePreviewRequest: Identifiable, Equatable {
    let id: UUID
    let title: String
    let source: Source
    let textPayload: AppImagePreviewTextPayload?

    init(
        id: UUID = UUID(),
        title: String,
        source: Source,
        textPayload: AppImagePreviewTextPayload? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.textPayload = textPayload
    }

    enum Source: Equatable {
        case fileURL(URL)
        case remoteURL(URL)
        case markdownImage(BlockInputImage, baseURL: URL?)
        case dataURL(String)
        case base64ImageData(Data)
        case toolResultImage(toolName: String, payload: String, baseURL: URL?)
    }

    static func fileURL(
        _ url: URL,
        title: String? = nil,
        textPayload: AppImagePreviewTextPayload? = nil
    ) -> AppImagePreviewRequest {
        AppImagePreviewRequest(
            title: title ?? imageTitle(for: url),
            source: .fileURL(url.standardizedFileURL),
            textPayload: textPayload
        )
    }

    static func appShotFileURL(
        _ url: URL,
        title: String,
        axTreeText: String?
    ) -> AppImagePreviewRequest {
        fileURL(
            url,
            title: title,
            textPayload: AppImagePreviewTextPayload(text: axTreeText)
        )
    }

    static func transcriptImageAttachment(_ attachment: TranscriptImageAttachment) -> AppImagePreviewRequest {
        guard let appShot = attachment.appShot else {
            return fileURL(attachment.image.fileURL, title: attachment.image.label)
        }
        return appShotFileURL(
            attachment.image.fileURL,
            title: appShot.displayTitle,
            axTreeText: appShot.axTreeText
        )
    }

    static func remoteURL(_ url: URL, title: String? = nil) -> AppImagePreviewRequest {
        AppImagePreviewRequest(
            title: title ?? imageTitle(for: url),
            source: .remoteURL(url)
        )
    }

    static func dataURL(
        _ value: String,
        title: String = "Image",
        textPayload: AppImagePreviewTextPayload? = nil
    ) -> AppImagePreviewRequest {
        AppImagePreviewRequest(title: title, source: .dataURL(value), textPayload: textPayload)
    }

    static func base64ImageData(
        _ data: Data,
        title: String = "Image",
        textPayload: AppImagePreviewTextPayload? = nil
    ) -> AppImagePreviewRequest {
        AppImagePreviewRequest(title: title, source: .base64ImageData(data), textPayload: textPayload)
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

struct AppImagePreviewTextPayload: Equatable, Sendable {
    let title: String
    let text: String

    init?(title: String = "App shot accessibility tree", text: String?) {
        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.title = title
        self.text = text
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
