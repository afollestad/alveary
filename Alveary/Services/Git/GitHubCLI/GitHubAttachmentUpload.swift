import Foundation

/// An uploaded file and the reference inserted into the draft and used to seed image caches.
struct GitHubAttachmentUpload: Sendable, Equatable {
    let fileURL: URL
    let markdownReference: String

    var referenceURL: URL? {
        if let range = markdownReference.range(of: #"\]\(([^)]+)\)$"#, options: .regularExpression) {
            let inner = markdownReference[range].dropFirst("](".count).dropLast()
            return URL(string: String(inner))
        }
        let trimmed = markdownReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("https://") else {
            return nil
        }
        return URL(string: trimmed)
    }
}

/// Uploads cannot be undone. A failed batch retains its successful prefix, including on cancellation.
struct GitHubAttachmentUploadBatch: Sendable, Equatable {
    let uploads: [GitHubAttachmentUpload]
    let failure: GitHubAttachmentUploadError?

    init(uploads: [GitHubAttachmentUpload], failure: GitHubAttachmentUploadError? = nil) {
        self.uploads = uploads
        self.failure = failure
    }
}

/// One validated media file; the picker and uploader share this format allowlist.
struct GitHubAttachmentFile {
    static var supportedExtensions: [String] {
        formats.map(\.extensionName)
    }

    let fileURL: URL
    let contentType: String

    init(_ fileURL: URL) throws {
        // Picker URLs can cache metadata; every attempt must see the file's current size and kind.
        var uncachedURL = fileURL
        uncachedURL.removeAllCachedResourceValues()
        guard fileURL.isFileURL,
              let values = try? uncachedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw GitHubAttachmentUploadError.invalidFile("\(fileURL.lastPathComponent) must be a readable regular file.")
        }
        guard size > 0 else {
            throw GitHubAttachmentUploadError.invalidFile("\(fileURL.lastPathComponent) is empty.")
        }
        guard let format = Self.formats.first(where: { $0.extensionName == fileURL.pathExtension.lowercased() }) else {
            throw GitHubAttachmentUploadError.unsupportedFile(fileURL.lastPathComponent)
        }
        let isVideo = format.contentType.hasPrefix("video/")
        let limit = (isVideo ? 100 : 10) * 1024 * 1024
        guard size <= limit else {
            let kind = isVideo ? "videos up to 100 MiB" : "images up to 10 MiB"
            throw GitHubAttachmentUploadError.fileTooLarge("\(fileURL.lastPathComponent) is too large. GitHub allows \(kind).")
        }
        self.fileURL = fileURL
        self.contentType = format.contentType
    }

    func upload(at url: URL) -> GitHubAttachmentUpload {
        let reference: String
        if contentType.hasPrefix("video/") {
            reference = url.absoluteString
        } else {
            let alt = fileURL.lastPathComponent
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            reference = "![\(alt)](\(url.absoluteString))"
        }
        return GitHubAttachmentUpload(fileURL: fileURL, markdownReference: reference)
    }

    private static let formats: [(extensionName: String, contentType: String)] = [
        ("png", "image/png"), ("jpg", "image/jpeg"), ("jpeg", "image/jpeg"),
        ("gif", "image/gif"), ("webp", "image/webp"), ("svg", "image/svg+xml"),
        ("mp4", "video/mp4"), ("mov", "video/quicktime"), ("webm", "video/webm")
    ]
}
