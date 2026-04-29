import AppKit
import SwiftUI

enum DiffViewerToolbarDisplayState: Equatable {
    case idle(DiffStats)
    case loading
}

struct DiffViewerToolbarButton: View {
    let displayState: DiffViewerToolbarDisplayState
    let action: () -> Void

    var body: some View {
        Button(
            action: action,
            label: {
                DiffViewerToolbarButtonLabel(displayState: displayState)
            }
        )
    }
}

private struct DiffViewerToolbarButtonLabel: View {
    let displayState: DiffViewerToolbarDisplayState

    var body: some View {
        HStack(spacing: 0) {
            Label("Diff Viewer", systemImage: "sidebar.trailing")
                .labelStyle(.iconOnly)
                .font(PrimaryToolbarMetrics.iconFont)
                .frame(
                    width: PrimaryToolbarMetrics.iconButtonSize,
                    height: PrimaryToolbarMetrics.iconButtonSize
                )

            DiffViewerToolbarStatusSlot(displayState: displayState)
                .font(PrimaryToolbarMetrics.statusFont)
        }
    }
}

private struct DiffViewerToolbarDiffSummary: View {
    let diffStats: DiffStats

    var body: some View {
        HStack(spacing: PrimaryToolbarMetrics.diffSummarySpacing) {
            DiffViewerToolbarStatText(
                text: "+\(diffStats.additions)",
                color: .green
            )

            DiffViewerToolbarStatText(
                text: "-\(diffStats.deletions)",
                color: .red
            )
        }
        .padding(.trailing, PrimaryToolbarMetrics.diffSummaryTrailingPadding)
    }
}

private struct DiffViewerToolbarStatText: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .foregroundStyle(color)
            .contentTransition(.numericText())
            // Cache hits can switch directly from one stats value to another;
            // animate each label width so the text and outer slot stay in sync.
            .frame(width: DiffViewerToolbarTextMeasurer.textWidth(text), alignment: .leading)
            .animation(PrimaryToolbarMetrics.statusAnimation, value: text)
    }
}

private struct DiffViewerToolbarStatusSlot: View {
    let displayState: DiffViewerToolbarDisplayState

    @State private var animatedSlotWidth: CGFloat
    @State private var areStatsVisible: Bool
    @State private var statsVisibilityTask: Task<Void, Never>?

    init(displayState: DiffViewerToolbarDisplayState) {
        self.displayState = displayState
        _animatedSlotWidth = State(initialValue: displayState.statusSlotWidth)
        _areStatsVisible = State(initialValue: displayState.statusContent.isStats)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            switch displayState.statusContent {
            case .empty:
                EmptyView()
            case .loading:
                PrimaryToolbarProgressSlot()
                    .padding(.leading, PrimaryToolbarMetrics.statusSpacing)
                    .transition(.opacity)
            case .stats(let diffStats):
                DiffViewerToolbarDiffSummary(diffStats: diffStats)
                    .padding(.leading, PrimaryToolbarMetrics.statusSpacing)
                    .opacity(areStatsVisible ? 1 : 0)
            }
        }
        .frame(
            width: animatedSlotWidth,
            height: PrimaryToolbarMetrics.iconButtonSize,
            alignment: .leading
        )
        .clipShape(Rectangle())
        .animation(Self.statusAnimation, value: areStatsVisible)
        .onChange(of: displayState) { oldValue, newValue in
            withAnimation(Self.statusAnimation) {
                animatedSlotWidth = newValue.statusSlotWidth
            }
            updateStatsVisibility(
                wasShowingStats: oldValue.statusContent.isStats,
                isShowingStats: newValue.statusContent.isStats
            )
        }
        .onDisappear {
            statsVisibilityTask?.cancel()
        }
    }

    private func updateStatsVisibility(wasShowingStats: Bool, isShowingStats: Bool) {
        statsVisibilityTask?.cancel()

        guard isShowingStats else {
            areStatsVisible = false
            return
        }

        guard !wasShowingStats else {
            areStatsVisible = true
            return
        }

        // Let the slot and following toolbar buttons move before the stats fade in;
        // otherwise the text can briefly render under the settings button.
        areStatsVisible = false
        statsVisibilityTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.statsRevealDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            areStatsVisible = true
        }
    }

    private static let statusAnimation = PrimaryToolbarMetrics.statusAnimation
    private static let statsRevealDelayNanoseconds: UInt64 = 90_000_000
}

private enum DiffViewerToolbarStatusContent {
    case empty
    case loading
    case stats(DiffStats)

    var isStats: Bool {
        if case .stats = self {
            return true
        }

        return false
    }
}

private extension DiffViewerToolbarDisplayState {
    var statusContent: DiffViewerToolbarStatusContent {
        switch self {
        case .loading:
            return .loading
        case .idle(let diffStats) where diffStats.isEmpty:
            return .empty
        case .idle(let diffStats):
            return .stats(diffStats)
        }
    }
}

extension DiffViewerToolbarDisplayState {
    var statusSlotWidth: CGFloat {
        switch statusContent {
        case .empty:
            return 0
        case .loading:
            return PrimaryToolbarMetrics.statusSpacing + PrimaryToolbarMetrics.iconButtonSize
        case .stats(let diffStats):
            return PrimaryToolbarMetrics.statusSpacing
                + DiffViewerToolbarTextMeasurer.diffSummaryWidth(for: diffStats)
        }
    }
}

private enum DiffViewerToolbarTextMeasurer {
    static func diffSummaryWidth(for diffStats: DiffStats) -> CGFloat {
        ceil(textWidth("+\(diffStats.additions)"))
            + PrimaryToolbarMetrics.diffSummarySpacing
            + ceil(textWidth("-\(diffStats.deletions)"))
            + PrimaryToolbarMetrics.diffSummaryTrailingPadding
    }

    static func textWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(
            ofSize: NSFont.systemFontSize,
            weight: .medium
        )
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}
