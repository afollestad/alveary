import Foundation

struct LocalFileAttachment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let fileURL: URL
    let label: String
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        fileURL: URL,
        label: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.label = label ?? fileURL.lastPathComponent
        self.createdAt = createdAt
    }

    var typeLabel: String {
        let fileExtension = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return fileExtension.isEmpty ? "FILE" : fileExtension.uppercased()
    }

    var markdownLink: String {
        "[\(Self.escapeMarkdownLabel(label))](<\(Self.escapeMarkdownDestination(fileURL.path))>)"
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
