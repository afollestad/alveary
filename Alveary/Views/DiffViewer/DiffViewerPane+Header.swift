import SwiftUI

struct DiffViewerPaneHeader: View {
    let activeDirectory: String?
    let contextualAction: DiffViewerViewModel.ContextualAction
    let selectedFiles: [FileStatus]
    let areAgentActionsEnabled: Bool
    let isRefreshing: Bool
    let showsFileListDivider: Bool
    let onRefresh: () -> Void
    let onCommitRequested: () -> Void
    let onOpenPRRequested: () -> Void
    let onViewPRRequested: (String) -> Void
    let onStageSelectedFiles: () -> Void
    let onUnstageSelectedFiles: () -> Void
    let onDiscardSelectedFiles: () -> Void

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
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .iconActionButtonStyle()
                .help(isRefreshing ? "Refreshing" : "Refresh")
                .accessibilityLabel(isRefreshing ? "Refreshing" : "Refresh")
                .disabled(activeDirectory == nil || isRefreshing)
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

                if hasUnstagedSelection {
                    Button("Stage", action: onStageSelectedFiles)
                        .secondaryActionButtonStyle()
                }

                if hasStagedSelection {
                    Button("Unstage", action: onUnstageSelectedFiles)
                        .secondaryActionButtonStyle()
                }

                if !selectedFiles.isEmpty {
                    Button("Discard", role: .destructive, action: onDiscardSelectedFiles)
                        .destructiveActionButtonStyle()
                }
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(showsFileListDivider ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: showsFileListDivider)
                .allowsHitTesting(false)
        }
    }

    private var displayDirectory: String {
        guard let activeDirectory else {
            return "No project selected"
        }

        return CanonicalPath.abbreviateHomeDirectory(activeDirectory)
    }

    private var hasStagedSelection: Bool {
        selectedFiles.contains(where: \.isStaged)
    }

    private var hasUnstagedSelection: Bool {
        selectedFiles.contains { !$0.isStaged }
    }
}
