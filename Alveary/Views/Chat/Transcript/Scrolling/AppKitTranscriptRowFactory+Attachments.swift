import Foundation

@MainActor
extension AppKitTranscriptRowFactory {
    func imageAttachments(
        for id: String,
        configuration: Configuration
    ) -> [TranscriptImageAttachment] {
        configuration.transcriptImageAttachmentsByMessageID[id] ?? []
    }

    func fileAttachments(
        for id: String,
        role: AppKitTranscriptTextBubbleRowView.Role,
        configuration: Configuration
    ) -> [LocalFileAttachment] {
        guard role == .user else {
            return []
        }
        return configuration.transcriptFileAttachmentsByMessageID[id] ?? []
    }

    func displayMarkdown(_ markdown: String, fileAttachments: [LocalFileAttachment]) -> String {
        guard !fileAttachments.isEmpty else {
            return markdown
        }
        let attachmentMarkdown = fileAttachments.map(\.markdownLink).joined(separator: "\n")
        if markdown == attachmentMarkdown {
            return ""
        }
        let suffix = "\n\n\(attachmentMarkdown)"
        guard markdown.hasSuffix(suffix) else {
            return markdown
        }
        return String(markdown.dropLast(suffix.count))
    }
}
