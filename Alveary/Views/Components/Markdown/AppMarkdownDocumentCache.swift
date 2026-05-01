import Foundation

enum AppMarkdownDocumentCache {
    nonisolated(unsafe) private static let cache: NSCache<NSString, AppMarkdownDocumentBox> = {
        let cache = NSCache<NSString, AppMarkdownDocumentBox>()
        cache.countLimit = 240
        return cache
    }()

    static func document(
        markdown: String,
        context: AppMarkdownDocumentCacheContext,
        parse: () -> AppMarkdownDocument
    ) -> AppMarkdownDocument {
        let key = cacheKey(
            markdown: markdown,
            context: context
        )
        if let cached = cache.object(forKey: key) {
            return document(
                content: cached.document.content,
                cacheKey: key,
                taskStateScope: context.taskStateScope
            )
        }

        let parsedDocument = parse()
        cache.setObject(AppMarkdownDocumentBox(parsedDocument), forKey: key, cost: markdown.count)
        return document(
            content: parsedDocument.content,
            cacheKey: key,
            taskStateScope: context.taskStateScope
        )
    }

    static func document(
        markdown: String,
        context: AppMarkdownDocumentCacheContext
    ) async -> AppMarkdownDocument {
        let key = cacheKey(markdown: markdown, context: context)
        if let cached = cache.object(forKey: key) {
            return document(
                content: cached.document.content,
                cacheKey: key,
                taskStateScope: context.taskStateScope
            )
        }

        let parsedContent = await Task.detached(priority: .userInitiated) {
            let parser = AppMarkdownParser(
                baseURL: context.baseURL,
                composerChipProvider: context.composerChipMode.composerChipProvider
            )
            return parser.documentPreservingSource(for: markdown).content
        }.value

        let parsedDocument = AppMarkdownDocument(content: parsedContent)
        cache.setObject(AppMarkdownDocumentBox(parsedDocument), forKey: key, cost: markdown.count)
        return document(
            content: parsedContent,
            cacheKey: key,
            taskStateScope: context.taskStateScope
        )
    }

    private static func document(
        content: AttributedString,
        cacheKey: NSString,
        taskStateScope: String?
    ) -> AppMarkdownDocument {
        AppMarkdownDocument(
            content: content,
            taskStateNamespace: taskStateNamespace(cacheKey: cacheKey as String, taskStateScope: taskStateScope)
        )
    }

    private static func taskStateNamespace(
        cacheKey: String,
        taskStateScope: String?
    ) -> String {
        guard let taskStateScope, !taskStateScope.isEmpty else {
            return cacheKey
        }
        return component(taskStateScope) + "|" + cacheKey
    }

    private static func cacheKey(
        markdown: String,
        context: AppMarkdownDocumentCacheContext
    ) -> NSString {
        // `taskStateScope` only namespaces interactive checkbox state; it does not
        // change parsed markdown, so identical content can share the cached document.
        [
            component(context.baseURL?.absoluteString ?? ""),
            component(context.inlineCodeStyle.cacheKey),
            component(context.composerChipMode.cacheKey),
            component(markdown)
        ].joined(separator: "|") as NSString
    }

    private static func component(_ value: String) -> String {
        "\(value.count):\(value)"
    }
}

struct AppMarkdownDocumentCacheContext: Sendable {
    let baseURL: URL?
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    let composerChipMode: AppMarkdownComposerChipMode
    let taskStateScope: String?
}

private final class AppMarkdownDocumentBox: NSObject {
    let document: AppMarkdownDocument

    init(_ document: AppMarkdownDocument) {
        self.document = document
    }
}

private extension AppMarkdownComposerChipMode {
    var cacheKey: String {
        switch self {
        case .none: return "plain"
        case .composer: return "chips"
        }
    }

    var composerChipProvider: ((String) -> [AppTextEditorChip])? {
        switch self {
        case .none:
            return nil
        case .composer:
            return ChatInputFieldTextSupport.composerTextChips(in:)
        }
    }
}

extension AppMarkdownInlineCodeStyle {
    var cacheKey: String {
        switch self {
        case .standard: return "standard"
        case .userBubble: return "userBubble"
        case .composer: return "composer"
        }
    }
}
