import Foundation

/// Renderer inputs that must match the text row's document-cache context before exact measurement.
struct AppKitTranscriptMarkdownPrepRequest: Equatable, Hashable {
    let rowID: String
    let markdown: String
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    let composerChipMode: AppMarkdownComposerChipMode
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
