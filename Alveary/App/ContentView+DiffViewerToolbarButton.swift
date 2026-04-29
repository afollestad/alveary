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
        // Keep the toolbar label stateless: toolbar width/content animations in
        // this area make the surrounding AppKit toolbar buttons move oddly.
        HStack(spacing: 6) {
            Label("Diff Viewer", systemImage: "sidebar.trailing")
                .labelStyle(.iconOnly)

            if displayState == .loading {
                DiffViewerToolbarProgressView()
            } else if case .idle(let diffStats) = displayState, !diffStats.isEmpty {
                DiffViewerToolbarDiffSummary(diffStats: diffStats)
            }
        }
        .font(.body.weight(.medium))
    }
}

private struct DiffViewerToolbarDiffSummary: View {
    let diffStats: DiffStats

    var body: some View {
        HStack(spacing: 6) {
            Text("+\(diffStats.additions)")
                .foregroundStyle(.green)

            Text("-\(diffStats.deletions)")
                .foregroundStyle(.red)
        }
        .padding(.trailing, 4)
    }
}

private struct DiffViewerToolbarProgressView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .tint(.blue)
            .scaleEffect(0.95)
            .frame(width: 16, height: 16)
            .padding(.trailing, 4)
    }
}
