extension ContentView {
    static func diffViewerToolbarDisplayState(
        stats: DiffStats,
        isLoading: Bool,
        paneMode _: DiffViewerMode
    ) -> DiffViewerToolbarDisplayState {
        // The global toolbar always summarizes working-tree changes; pane mode only affects
        // the right-pane content so switching to commit inspection cannot change this source.
        if isLoading {
            return .loading
        }

        return .idle(stats)
    }
}
