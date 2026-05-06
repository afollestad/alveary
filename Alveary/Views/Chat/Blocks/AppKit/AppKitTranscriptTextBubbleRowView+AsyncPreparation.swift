@preconcurrency import AppKit

extension AppKitTranscriptTextBubbleRowView {
    func preparedMeasurementContext(
        for markdownWidth: CGFloat,
        configuration: Configuration
    ) -> TextBubblePreparedMeasurement.Context {
        TextBubblePreparedMeasurement.Context(
            configuration: configuration,
            isExpanded: isExpanded,
            markdownWidth: markdownWidth,
            inlineCodeStyle: inlineCodeStyle(for: configuration.role),
            appearance: effectiveAppearance
        )
    }

    func scheduleAsyncMarkdownPreparation(for context: TextBubblePreparedMeasurement.Context) {
        let key = context.key
        guard pendingAsyncPreparationKey != key,
              asyncPreparedMarkdown?.key != key,
              AppMarkdownDocumentCache.cachedDocument(markdown: context.configuration.markdown, context: context.documentCacheContext) == nil else {
            return
        }

        asyncPreparationTask?.cancel()
        pendingAsyncPreparationKey = key
        asyncPreparationGeneration += 1
        let generation = asyncPreparationGeneration
        let markdown = context.configuration.markdown
        let cacheContext = context.documentCacheContext

        // Only parser/cache work runs asynchronously here; AppKit text measurement
        // and view creation stay on the main actor where their primitives belong.
        asyncPreparationTask = Task { [weak self] in
            let document: AppMarkdownDocument
#if DEBUG
            if let loader = self?.asyncDocumentLoaderForTesting {
                document = await loader(markdown, cacheContext)
            } else {
                document = await AppMarkdownDocumentCache.document(markdown: markdown, context: cacheContext)
            }
#else
            document = await AppMarkdownDocumentCache.document(markdown: markdown, context: cacheContext)
#endif
            guard !Task.isCancelled else {
                return
            }
            self?.acceptAsyncPreparedMarkdown(document, key: key, generation: generation)
        }
    }

    func resetAsyncMarkdownPreparation() {
        asyncPreparationTask?.cancel()
        asyncPreparationTask = nil
        pendingAsyncPreparationKey = nil
        asyncPreparedMarkdown = nil
        asyncPreparationGeneration += 1
    }

    func acceptAsyncPreparedMarkdown(
        _ document: AppMarkdownDocument,
        key: AppKitMarkdownPreparedLayoutKey,
        generation: Int
    ) {
        guard generation == asyncPreparationGeneration,
              pendingAsyncPreparationKey == key,
              let configuration,
              preparedMeasurementContext(for: key.availableWidth, configuration: configuration).key == key
        else {
            return
        }

        pendingAsyncPreparationKey = nil
        asyncPreparedMarkdown = AsyncPreparedMarkdown(key: key, document: document)
        if superview != nil {
            invalidateTranscriptHeight(force: true)
        }
    }
}

#if DEBUG
extension AppKitTranscriptTextBubbleRowView {
    var acceptedAsyncKeyForTesting: AppKitMarkdownPreparedLayoutKey? {
        asyncPreparedMarkdown?.key
    }

    var pendingAsyncKeyForTesting: AppKitMarkdownPreparedLayoutKey? {
        pendingAsyncPreparationKey
    }
}
#endif
