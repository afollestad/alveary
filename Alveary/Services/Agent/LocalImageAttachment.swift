import Foundation
import UniformTypeIdentifiers

struct LocalImageAttachment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let fileURL: URL
    let label: String
    let createdAt: Date

    var markdownImageLink: String {
        "![\(Self.escapeMarkdownLabel(label))](<\(Self.escapeMarkdownDestination(fileURL.path))>)"
    }

    private static func escapeMarkdownLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func escapeMarkdownDestination(_ destination: String) -> String {
        destination.replacingOccurrences(of: ">", with: "%3E")
    }
}

protocol ConversationAttachmentStore: Sendable {
    func conversationRootDirectory(conversationId: String) -> URL
    func copyLocalImages(_ urls: [URL], conversationId: String) async throws -> [LocalImageAttachment]
    func storeAppShotScreenshot(_ data: Data, conversationId: String, label: String) async throws -> LocalImageAttachment
    func cleanupUnreferenced(conversationId: String, keeping retainedURLs: Set<URL>, olderThan age: TimeInterval) async
}

actor DefaultConversationAttachmentStore: ConversationAttachmentStore {
    static let defaultRootDirectory = SessionComponent.appSupportDirectory
        .appendingPathComponent("ConversationAttachments", isDirectory: true)

    private let rootDirectory: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.rootDirectory = Self.defaultRootDirectory
        self.fileManager = fileManager
    }

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    nonisolated func conversationRootDirectory(conversationId: String) -> URL {
        directory(for: conversationId)
    }

    func copyLocalImages(_ urls: [URL], conversationId: String) async throws -> [LocalImageAttachment] {
        guard !urls.isEmpty else { return [] }

        let conversationDirectory = directory(for: conversationId)
        try fileManager.createDirectory(at: conversationDirectory, withIntermediateDirectories: true, attributes: nil)

        return try urls.map { sourceURL in
            let canonicalSourceURL = sourceURL.standardizedFileURL
            guard Self.isSupportedImageURL(canonicalSourceURL) else {
                throw AttachmentStoreError.unsupportedImage(canonicalSourceURL.path)
            }

            let id = UUID().uuidString
            let fileExtension = canonicalSourceURL.pathExtension
            let filename = fileExtension.isEmpty ? id : "\(id).\(fileExtension)"
            let destinationURL = conversationDirectory.appendingPathComponent(filename, isDirectory: false)
            try fileManager.copyItem(at: canonicalSourceURL, to: destinationURL)
            return LocalImageAttachment(
                id: id,
                fileURL: destinationURL,
                label: canonicalSourceURL.lastPathComponent,
                createdAt: Date()
            )
        }
    }

    func storeAppShotScreenshot(_ data: Data, conversationId: String, label: String) async throws -> LocalImageAttachment {
        let appShotDirectory = directory(for: conversationId)
            .appendingPathComponent("appshots", isDirectory: true)
        try fileManager.createDirectory(at: appShotDirectory, withIntermediateDirectories: true, attributes: nil)

        let id = UUID().uuidString
        let destinationURL = appShotDirectory.appendingPathComponent("\(id).png", isDirectory: false)
        try data.write(to: destinationURL, options: [.atomic])
        return LocalImageAttachment(
            id: id,
            fileURL: destinationURL,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Appshot screenshot.png" : label,
            createdAt: Date()
        )
    }

    func cleanupUnreferenced(conversationId: String, keeping retainedURLs: Set<URL>, olderThan age: TimeInterval) async {
        cleanupUnreferenced(in: directory(for: conversationId), keeping: retainedURLs, olderThan: age)
    }

    private func cleanupUnreferenced(in directory: URL, keeping retainedURLs: Set<URL>, olderThan age: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-age)
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else {
            return
        }

        let fileURLs = enumerator.allObjects.compactMap { $0 as? URL }
        for fileURL in fileURLs {
            guard !retainedURLs.contains(fileURL.standardizedFileURL),
                  let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) <= cutoff else {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    nonisolated static func isSupportedImageURL(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .image)
        }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    nonisolated private func directory(for conversationId: String) -> URL {
        rootDirectory
            .appendingPathComponent("conversations", isDirectory: true)
            .appendingPathComponent(conversationId, isDirectory: true)
    }
}

enum AttachmentStoreError: LocalizedError, Equatable {
    case unsupportedImage(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedImage(let path):
            return "Unsupported image attachment: \(path)"
        }
    }
}
