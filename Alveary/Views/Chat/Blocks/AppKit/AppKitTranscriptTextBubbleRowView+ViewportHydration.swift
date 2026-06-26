@preconcurrency import AppKit

@MainActor
/// Row contract for content that can be installed after measurement without changing transcript height.
protocol AppKitTranscriptViewportHydratable: AnyObject {
    var isTranscriptViewportHydrated: Bool { get }

    func hydrateForTranscriptViewport()
}

extension AppKitTranscriptTextBubbleRowView {
    func resetMarkdownView() {
        markdownView?.removeFromSuperview()
        markdownView = nil
        hasMarkdownHeightHandler = false
        lastLayoutMetrics = nil
        resetAsyncMarkdownPreparation()
    }

    func hydrateMarkdownIfNeeded() {
        guard markdownView == nil else {
            return
        }
        guard let configuration else {
            return
        }
        guard configuration.hasBubbleContent else {
            return
        }

        let markdownView = AppKitMarkdownView(
            document: document(for: configuration),
            inlineCodeStyle: inlineCodeStyle(for: configuration.role),
            typography: configuration.typography,
            imageBaseURL: configuration.markdownBaseURL,
            onOpenLink: onOpenMarkdownLink
        )
        markdownView.translatesAutoresizingMaskIntoConstraints = true
        markdownClipView.addSubview(markdownView)
        self.markdownView = markdownView
    }

    func installMarkdownHeightInvalidationHandlerIfNeeded() {
        guard !hasMarkdownHeightHandler,
              let markdownView else {
            return
        }
        markdownView.onHeightInvalidated = { [weak self] in
            guard self?.isHydratingMarkdownForViewport == false else {
                return
            }
            self?.invalidateTranscriptHeight(force: true)
        }
        hasMarkdownHeightHandler = true
    }

    func document(for configuration: Configuration) -> AppMarkdownDocument {
        let composerChipProvider: ((String) -> [AppTextEditorChip])?
        if configuration.role == .user {
            composerChipProvider = ChatComposerTextSupport.composerTextChips(in:)
        } else {
            composerChipProvider = nil
        }

        return AppMarkdownDocumentCache.document(
            markdown: configuration.markdown,
            context: AppMarkdownDocumentCacheContext(
                baseURL: nil,
                inlineCodeStyle: inlineCodeStyle(for: configuration.role),
                composerChipMode: configuration.role == .user ? .composer : .none,
                taskStateScope: configuration.id
            )
        ) {
            AppMarkdownParser(
                composerChipProvider: composerChipProvider
            )
            .documentPreservingSource(for: configuration.markdown)
        }
    }
}

extension AppKitTranscriptTextBubbleRowView: AppKitTranscriptViewportHydratable {
    var isTranscriptViewportHydrated: Bool {
        if configuration?.hasBubbleContent == false {
            return true
        }
        return markdownView != nil
    }

    func hydrateForTranscriptViewport() {
        guard !isTranscriptViewportHydrated else {
            return
        }
        isHydratingMarkdownForViewport = true
        hydrateMarkdownIfNeeded()
        if let lastLayoutMetrics, let markdownView {
            markdownView.maximumImageDisplayWidth = lastLayoutMetrics.markdownFrame.width
            markdownView.frame = lastLayoutMetrics.markdownFrame
            markdownView.layoutSubtreeIfNeeded()
        }
        // Initial markdown layout can emit height invalidations; install the handler
        // after this hydration turn so fixed shells remain layout-neutral.
        DispatchQueue.main.async { [weak self] in
            self?.isHydratingMarkdownForViewport = false
            self?.installMarkdownHeightInvalidationHandlerIfNeeded()
        }
    }
}
