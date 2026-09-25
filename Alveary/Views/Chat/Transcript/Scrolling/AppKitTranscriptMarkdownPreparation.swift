import Foundation

/// Renderer inputs that must match the text row's document-cache context before exact measurement.
struct AppKitTranscriptMarkdownPrepRequest: Equatable, Hashable {
    let rowID: String
    let markdown: String
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    let composerChipMode: AppMarkdownComposerChipMode

    /// Hashes the markdown by length only. The coordinator rebuilds and hashes one request per
    /// text bubble on every transcript update, so hashing the bodies scanned every byte of the
    /// transcript per update; `==` still compares them in full on a bucket match.
    func hash(into hasher: inout Hasher) {
        hasher.combine(rowID)
        hasher.combine(markdown.utf8.count)
        hasher.combine(inlineCodeStyle)
        hasher.combine(composerChipMode)
    }
}

extension AppKitTranscriptMarkdownPrepRequest {
    var documentCacheContext: AppMarkdownDocumentCacheContext {
        AppMarkdownDocumentCacheContext(
            baseURL: nil,
            inlineCodeStyle: inlineCodeStyle,
            composerChipMode: composerChipMode,
            taskStateScope: rowID
        )
    }
}
