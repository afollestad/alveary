import SwiftUI

struct DiffPreviewFileHeader: View {
    let file: DiffFile
    let collapseState: DiffPreviewFileHeaderCollapseState?

    var body: some View {
        if let collapseState {
            AppHeaderToggle(action: collapseState.onToggle) {
                headerContent(collapseState: collapseState)
            }
            .help(helpText(for: collapseState))
            .accessibilityLabel(file.path)
            .accessibilityValue(collapseState.isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityAction(.default, collapseState.onToggle)
        } else {
            headerContent(collapseState: nil)
                .accessibilityElement(children: .combine)
        }
    }

    private func headerContent(collapseState: DiffPreviewFileHeaderCollapseState?) -> some View {
        HStack(spacing: 8) {
            headerTitle

            if file.isBinary {
                DiffPreviewBadge(title: "Binary", tone: .neutral)
            }

            if file.linesAdded > 0 {
                DiffPreviewBadge(title: "+\(file.linesAdded)", tone: .added)
            }

            if file.linesDeleted > 0 {
                DiffPreviewBadge(title: "-\(file.linesDeleted)", tone: .deleted)
            }

            if let collapseState {
                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapseState.isCollapsed ? 0 : 90))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                    .animation(appExpansionAnimation, value: collapseState.isCollapsed)
            }
        }
        .diffPreviewMinimumContentWidthFrame()
    }

    private var headerTitle: some View {
        Text(verbatim: file.path)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func helpText(for collapseState: DiffPreviewFileHeaderCollapseState) -> String {
        collapseState.isCollapsed ? "Expand \(file.path)" : "Collapse \(file.path)"
    }
}

struct DiffPreviewFileHeaderCollapseState {
    let isCollapsed: Bool
    let onToggle: () -> Void
}
