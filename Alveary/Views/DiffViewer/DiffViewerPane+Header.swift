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

                    Text(displayDirectory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .iconActionButtonStyle()
                .help("Refresh")
                .accessibilityLabel("Refresh")
                .disabled(activeDirectory == nil)
            }

            HStack(spacing: 8) {
                switch contextualAction {
                case .commit:
                    Button(action: onCommitRequested) {
                        Label("Commit", systemImage: "checkmark.circle")
                    }
                        .primaryActionButtonStyle()
                        .disabled(!areAgentActionsEnabled)
                case .openPR:
                    Button(action: onOpenPRRequested) {
                        Label("Open PR", systemImage: "arrow.triangle.branch")
                    }
                        .primaryActionButtonStyle()
                        .disabled(!areAgentActionsEnabled)
                case .viewPR(let url):
                    Button {
                        onViewPRRequested(url)
                    } label: {
                        Label("View PR", systemImage: "arrow.up.right.square")
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

    private var displayDirectory: String {
        guard let activeDirectory else {
            return "No project selected"
        }

        return CanonicalPath.abbreviateHomeDirectory(activeDirectory)
    }
}
