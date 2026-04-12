import SwiftUI

struct DiffViewerPaneHeader: View {
    let activeDirectory: String?
    let contextualAction: DiffViewerViewModel.ContextualAction
    let selectedFile: FileStatus?
    let areAgentActionsEnabled: Bool
    let onRefresh: () -> Void
    let onCommitRequested: () -> Void
    let onOpenPRRequested: () -> Void
    let onViewPRRequested: (String) -> Void
    let onStageSelectedFile: () -> Void
    let onUnstageSelectedFile: () -> Void
    let onDiscardSelectedFile: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diff Viewer")
                        .font(.headline)

                    Text(activeDirectory ?? "No project selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(activeDirectory == nil)
            }

            HStack(spacing: 8) {
                switch contextualAction {
                case .commit:
                    Button("Commit", action: onCommitRequested)
                        .primaryActionButtonStyle()
                        .disabled(!areAgentActionsEnabled)
                case .openPR:
                    Button("Open PR", action: onOpenPRRequested)
                        .primaryActionButtonStyle()
                        .disabled(!areAgentActionsEnabled)
                case .viewPR(let url):
                    Button("View PR") {
                        onViewPRRequested(url)
                    }
                    .primaryActionButtonStyle()
                case .none:
                    EmptyView()
                }

                Spacer()

                if let selectedFile {
                    if selectedFile.isStaged {
                        Button("Unstage", action: onUnstageSelectedFile)
                            .secondaryActionButtonStyle()
                    } else {
                        Button("Stage", action: onStageSelectedFile)
                            .secondaryActionButtonStyle()
                    }

                    Button("Discard", role: .destructive, action: onDiscardSelectedFile)
                        .destructiveActionButtonStyle()
                }
            }
        }
        .padding(14)
        .background(.bar)
    }
}
