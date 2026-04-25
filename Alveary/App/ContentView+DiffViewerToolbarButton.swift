import SwiftUI

struct DiffViewerToolbarButton: View {
    let diffStats: DiffStats
    let action: () -> Void

    var body: some View {
        Button(
            action: action,
            label: {
                DiffViewerToolbarButtonLabel(diffStats: diffStats)
            }
        )
    }
}

private struct DiffViewerToolbarButtonLabel: View {
    let diffStats: DiffStats

    var body: some View {
        // Keep the toolbar label stateless: toolbar width/content animations in
        // this area make the surrounding AppKit toolbar buttons move oddly.
        HStack(spacing: 0) {
            Label("Diff Viewer", systemImage: "sidebar.trailing")
                .labelStyle(.iconOnly)

            if !diffStats.isEmpty {
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
        .padding(.leading, 6)
        .padding(.trailing, 4)
    }
}
