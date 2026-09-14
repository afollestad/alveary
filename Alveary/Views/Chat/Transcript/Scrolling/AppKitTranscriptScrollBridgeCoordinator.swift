import AppKit

/// Parsing has its own identity: resizing or scrolling while it runs updates the eventual
/// installation, without restarting work or replaying an obsolete width or scroll request.
@MainActor
final class AppKitTranscriptScrollBridgeCoordinator {
    private let rowFactory = AppKitTranscriptRowFactory()
    private let presentationCache = AppKitTranscriptPresentationCache()
    private var latestUpdate: AppKitTranscriptPreparedUpdate?
    private var latestSignature: AppKitTranscriptPreparedUpdate.ContentSignature?
    private var lastAppliedContentSignature: AppKitTranscriptPreparedUpdate.ContentSignature?
    private var lastScrollToBottomRequest: Int?
    private var lastScrollToRowTopRequest: AppKitTranscriptRowTopScrollRequest?
    private var preparationRequests: [AppKitTranscriptMarkdownPrepRequest] = []
    private var preparedDocuments: [AppKitTranscriptMarkdownPrepRequest: AppMarkdownDocument] = [:]
    private var markdownPreparationGeneration = 0
    private var markdownPreparationTask: Task<Void, Never>?
    private var isApplyingUpdate = false
    private var loadingStateVersion = 0
    private var onLoadingStateChanged: (Bool) -> Void = { _ in }
    private(set) var isPreparingInitialContent = false
#if DEBUG
    var documentLoaderForTesting: ((AppKitTranscriptMarkdownPrepRequest) async -> AppMarkdownDocument)?
#endif

    deinit { markdownPreparationTask?.cancel() }

    func update(
        container: AppKitTranscriptScrollContainerView,
        items: [ChatItem],
        presentation: AppKitTranscriptPresentation? = nil,
        transientRows: AppKitTranscriptTransientRows = .init(),
        rowConfiguration: AppKitTranscriptRowFactory.Configuration,
        isFollowing: Bool,
        scrollToBottomRequest: Int,
        scrollToRowTopRequest: AppKitTranscriptRowTopScrollRequest? = nil,
        onLoadingStateChanged: @escaping (Bool) -> Void = { _ in },
        onScrollMetricsChanged: @escaping (ChatTranscriptScrollMetrics) -> Void = { _ in }
    ) {
        self.onLoadingStateChanged = onLoadingStateChanged
        cancelPendingScrollIfUserMovedAway(
            container: container, isFollowing: isFollowing, bottomRequest: scrollToBottomRequest, rowTopRequest: scrollToRowTopRequest
        )
        container.preservesBottomOnResize = isFollowing
        container.onScrollMetricsChanged = { metrics in
            DispatchQueue.main.async { onScrollMetricsChanged(metrics) }
        }
        container.onStableLayout = { [weak self, weak container] in
            guard let container else { return }
            self?.applyLatestIfReady(container: container)
        }
        let update = AppKitTranscriptPreparedUpdate(
            presentation: presentation ?? presentationCache.presentation(for: items),
            transientRows: transientRows,
            rowConfiguration: rowConfiguration,
            isFollowing: isFollowing,
            scrollToBottomRequest: scrollToBottomRequest,
            scrollToRowTopRequest: scrollToRowTopRequest
        )
        latestUpdate = update
        latestSignature = update.contentSignature

        // Cancel a pending B even when reverting to the already installed A. The old early
        // return left B alive, allowing its eventual completion to overwrite the new selection.
        if lastAppliedContentSignature == latestSignature {
            cancelPreparation()
            setInitialLoading(false, container: container)
            applyLatestIfReady(container: container)
            return
        }

        let requests = rowFactory.markdownPreparationRequests(for: items, configuration: rowConfiguration)
        if markdownPreparationTask != nil, preparationRequests == requests { return }
        cancelPreparation()
        preparationRequests = requests
        let liveRequests = Set(requests)
        preparedDocuments = rowFactory.preparedMarkdownDocuments.merging(preparedDocuments) { _, new in new }
            .filter { liveRequests.contains($0.key) }
        for request in requests where preparedDocuments[request] == nil {
            preparedDocuments[request] = AppMarkdownDocumentCache.cachedDocument(
                markdown: request.markdown, context: request.documentCacheContext
            )
        }
        let missing = requests.filter { preparedDocuments[$0] == nil }
        if missing.isEmpty {
            applyLatestIfReady(container: container)
        } else {
            setInitialLoading(container.transcriptDocumentView.firstRow(atOrBelow: 0) == nil, container: container)
            startPreparation(missing, container: container)
        }
    }

    private func cancelPendingScrollIfUserMovedAway(
        container: AppKitTranscriptScrollContainerView,
        isFollowing: Bool,
        bottomRequest: Int,
        rowTopRequest: AppKitTranscriptRowTopScrollRequest?
    ) {
        guard latestUpdate?.isFollowing == true, !isFollowing else { return }
        // A collapse's clip animation must not restore its captured offset after the reader scrolls away.
        container.activeScrollAnimationToken = nil
        guard latestUpdate?.scrollToBottomRequest == bottomRequest else { return }
        // A user who moved away while new rows awaited preparation or layout cancelled the captured
        // follow request; only a subsequent explicit request can move them again.
        lastScrollToBottomRequest = bottomRequest
        if latestUpdate?.scrollToRowTopRequest == rowTopRequest {
            lastScrollToRowTopRequest = rowTopRequest
        }
    }

    func cancel(container: AppKitTranscriptScrollContainerView) {
        cancelPreparation()
        latestUpdate = nil
        latestSignature = nil
        isPreparingInitialContent = false
        container.onStableLayout = nil
        container.onScrollMetricsChanged = nil
        container.cancelViewportPrewarming()
        loadingStateVersion += 1
        container.setIsLoading(false)
    }

    private func cancelPreparation() {
        markdownPreparationGeneration += 1
        markdownPreparationTask?.cancel()
        markdownPreparationTask = nil
    }

    private func startPreparation(
        _ requests: [AppKitTranscriptMarkdownPrepRequest],
        container: AppKitTranscriptScrollContainerView
    ) {
        let generation = markdownPreparationGeneration
#if DEBUG
        let loader = documentLoaderForTesting
#endif
        markdownPreparationTask = Task { @MainActor [weak self, weak container] in
            var documents: [AppKitTranscriptMarkdownPrepRequest: AppMarkdownDocument] = [:]
            for request in requests {
                guard !Task.isCancelled else { return }
                let document: AppMarkdownDocument
#if DEBUG
                if let loader {
                    document = await loader(request)
                } else {
                    document = await AppMarkdownDocumentCache.document(markdown: request.markdown, context: request.documentCacheContext)
                }
#else
                document = await AppMarkdownDocumentCache.document(markdown: request.markdown, context: request.documentCacheContext)
#endif
                documents[request] = document
            }
            guard !Task.isCancelled, let self, let container,
                  self.markdownPreparationGeneration == generation else { return }
            self.preparedDocuments.merge(documents) { _, new in new }
            self.markdownPreparationTask = nil
            self.applyLatestIfReady(container: container)
        }
    }

    private func applyLatestIfReady(container: AppKitTranscriptScrollContainerView) {
        guard !isApplyingUpdate, markdownPreparationTask == nil,
              let update = latestUpdate, let signature = latestSignature else { return }
        guard container.bounds.width > transcriptScrollLeadingInset + transcriptScrollTrailingInset,
              !container.transcriptDocumentView.hasActiveFrameAnimation,
              container.activeScrollAnimationToken == nil else {
            setInitialLoading(!update.items.isEmpty && container.transcriptDocumentView.firstRow(atOrBelow: 0) == nil, container: container)
            return
        }
        isApplyingUpdate = true
        defer { isApplyingUpdate = false }
        guard signature != lastAppliedContentSignature else {
            honorScrollRequestsIfNeeded(container: container, update: update)
            return
        }
        var configuration = update.rowConfiguration
        var dirtyRowIDs: Set<String> = []
        var isBuildingRows = true
        configuration.onRowHeightInvalidated = { [weak self, weak container] rowID, animates in
            if isBuildingRows {
                dirtyRowIDs.insert(rowID)
                return
            }
            let forcesBottom = self?.latestUpdate?.isFollowing == true &&
                (rowID == AppKitTranscriptTransientRows.streamingRowID || AppKitTranscriptTransientRows.isThoughtRowID(rowID))
            container?.rowHeightInvalidated(
                rowID: rowID, preserveBottomIfFollowing: true,
                forceBottomIfPreserving: forcesBottom, animatesLayoutChanges: animates
            )
        }
        rowFactory.preparedMarkdownDocuments = preparedDocuments
        let rows = rowFactory.makeRows(for: update.presentation, transientRows: update.transientRows, configuration: configuration)
        isBuildingRows = false
        container.configure(
            rows: rows, dirtyRowIDs: dirtyRowIDs, rowIDAliases: update.presentation.rowIDAliases,
            preserveBottomIfFollowing: update.isFollowing && !shouldHonorRowTopRequest(update.scrollToRowTopRequest)
        )
        container.preservesBottomOnResize = update.isFollowing
        lastAppliedContentSignature = signature
        honorScrollRequestsIfNeeded(container: container, update: update)
        setInitialLoading(false, container: container)
        container.publishScrollMetrics()
    }

    private func honorScrollRequestsIfNeeded(
        container: AppKitTranscriptScrollContainerView,
        update: AppKitTranscriptPreparedUpdate
    ) {
        // Empty geometry cannot satisfy a request for asynchronously arriving history.
        guard !container.transcriptDocumentView.hasActiveFrameAnimation,
              container.activeScrollAnimationToken == nil,
              container.transcriptDocumentView.firstRow(atOrBelow: 0) != nil else { return }
        if shouldHonorRowTopRequest(update.scrollToRowTopRequest), let request = update.scrollToRowTopRequest,
           container.scrollToRowTop(rowID: request.rowID, topInset: request.topInset) {
            lastScrollToRowTopRequest = request
            lastScrollToBottomRequest = update.scrollToBottomRequest
            return
        }
        let shouldScroll = lastScrollToBottomRequest.map { $0 != update.scrollToBottomRequest } ?? (update.scrollToBottomRequest != 0)
        if shouldScroll { container.scrollToBottom() }
        lastScrollToBottomRequest = update.scrollToBottomRequest
    }

    private func shouldHonorRowTopRequest(_ request: AppKitTranscriptRowTopScrollRequest?) -> Bool {
        request != nil && lastScrollToRowTopRequest != request
    }

    private func setInitialLoading(_ isLoading: Bool, container: AppKitTranscriptScrollContainerView) {
        container.setIsLoading(isLoading)
        guard isPreparingInitialContent != isLoading else { return }
        isPreparingInitialContent = isLoading
        loadingStateVersion += 1
        let version = loadingStateVersion
        // NSViewRepresentable update may be in SwiftUI's render pass.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.loadingStateVersion == version else { return }
            self.onLoadingStateChanged(isLoading)
        }
    }
}
