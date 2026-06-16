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
                cached.document,
                cacheKey: key,
                taskStateScope: context.taskStateScope
            )
        }

        let parsedDocument = parse()
        cache.setObject(AppMarkdownDocumentBox(parsedDocument), forKey: key, cost: markdown.count)
        return document(
            parsedDocument,
            cacheKey: key,
            taskStateScope: context.taskStateScope
        )
    }

    static func cachedDocument(
        markdown: String,
        context: AppMarkdownDocumentCacheContext
    ) -> AppMarkdownDocument? {
        let key = cacheKey(markdown: markdown, context: context)
        guard let cached = cache.object(forKey: key) else {
            return nil
        }
        return document(
            cached.document,
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
                cached.document,
                cacheKey: key,
                taskStateScope: context.taskStateScope
            )
        }

        let parsedDocument = await Task.detached(priority: .userInitiated) {
            let parser = AppMarkdownParser(
                baseURL: context.baseURL,
                composerChipProvider: context.composerChipMode.composerChipProvider
            )
            return parser.documentPreservingSource(for: markdown)
        }.value

        cache.setObject(AppMarkdownDocumentBox(parsedDocument), forKey: key, cost: markdown.count)
        return document(
            parsedDocument,
            cacheKey: key,
            taskStateScope: context.taskStateScope
        )
    }

    private static func document(
        _ document: AppMarkdownDocument,
        cacheKey: NSString,
        taskStateScope: String?
    ) -> AppMarkdownDocument {
        AppMarkdownDocument(
            content: document.content,
            taskStateNamespace: taskStateNamespace(cacheKey: cacheKey as String, taskStateScope: taskStateScope),
            blocks: document.blocks
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
            return ChatComposerTextSupport.composerTextChips(in:)
        }
    }
}

extension AppMarkdownInlineCodeStyle {
    var cacheKey: String {
        switch self {
        case .standard: return "standard"
        case .assistantBubble: return "assistantBubble"
        case .userBubble: return "userBubble"
        case .composer: return "composer"
        }
    }
}
