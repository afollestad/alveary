import Foundation

/// Renderer inputs that must match the text row's document-cache context before exact measurement.
struct AppKitTranscriptMarkdownPrepRequest: Equatable, Hashable {
    let rowID: String
    let markdown: String
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    let composerChipMode: AppMarkdownComposerChipMode
}

/// Prepares transcript markdown documents ahead of AppKit row installation.
enum AppKitTranscriptMarkdownPreparation {
    static func missingRequests(_ requests: [AppKitTranscriptMarkdownPrepRequest]) -> [AppKitTranscriptMarkdownPrepRequest] {
        deduplicated(requests).filter { request in
            AppMarkdownDocumentCache.cachedDocument(markdown: request.markdown, context: request.documentCacheContext) == nil
        }
    }

    static func prepare(_ requests: [AppKitTranscriptMarkdownPrepRequest]) async {
        for request in deduplicated(requests) {
            _ = await AppMarkdownDocumentCache.document(markdown: request.markdown, context: request.documentCacheContext)
            if Task.isCancelled {
                return
            }
        }
    }

    private static func deduplicated(
        _ requests: [AppKitTranscriptMarkdownPrepRequest]
    ) -> [AppKitTranscriptMarkdownPrepRequest] {
        var seen: Set<AppKitTranscriptMarkdownPrepRequest> = []
        return requests.filter { seen.insert($0).inserted }
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
