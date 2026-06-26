import CoreGraphics

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

    var diffViewerToggleHelpText: String {
        let action = appState.isRightPaneVisible ? "Hide Diff Viewer" : "Show Diff Viewer"
        guard !diffViewModel.isDiffToolbarLoading else {
            return "\(action), loading diffs"
        }
        let stats = diffViewModel.diffStats

        guard !stats.isEmpty else {
            return action
        }

        return "\(action), +\(stats.additions) -\(stats.deletions)"
    }

    var diffViewerToggleAccessibilityValue: String {
        guard !diffViewModel.isDiffToolbarLoading else {
            return "Loading diffs"
        }
        let stats = diffViewModel.diffStats
        guard !stats.isEmpty else {
            return ""
        }

        return "\(stats.additions) additions, \(stats.deletions) deletions"
    }

    var diffViewerToolbarDisplayState: DiffViewerToolbarDisplayState {
        Self.diffViewerToolbarDisplayState(
            stats: diffViewModel.diffStats,
            isLoading: diffViewModel.isDiffToolbarLoading,
            paneMode: diffViewerMode
        )
    }

    func effectiveDiffViewerWidth(availableWidth: CGFloat) -> CGFloat {
        ContentDiffViewerWidthPolicy.effectiveWidth(storedWidth: diffViewerWidth, availableWidth: availableWidth)
    }

    func effectiveDiffViewerBounds(availableWidth: CGFloat) -> ClosedRange<Double> {
        ContentDiffViewerWidthPolicy.bounds(availableWidth: availableWidth)
    }
}
