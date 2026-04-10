import AppKit
import SwiftUI

struct DiffViewerPane: View {
    let viewModel: DiffViewerViewModel
    let areAgentActionsEnabled: Bool
    let onCommitRequested: () -> Void
    let onOpenPRRequested: () -> Void

    @State private var pendingDiscardFiles: [FileStatus] = []

    var body: some View {
        VStack(spacing: 0) {
            header

            if let gitError = viewModel.gitError {
                InlineBanner(message: gitError, severity: .error, autoDismissAfter: nil) {
                    viewModel.clearGitError()
                }
                    .padding(12)
            }

            if viewModel.activeDirectory == nil {
                EmptyStateView(
                    icon: "rectangle.split.3x1",
                    heading: "No diff context",
                    subtext: "Select a thread to inspect repository changes and diff previews.",
                    actions: []
                )
            } else {
                content
            }
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: Binding(
                get: { !pendingDiscardFiles.isEmpty },
                set: { isPresented in
                    if !isPresented {
                        pendingDiscardFiles = []
                    }
                }
            )
        ) {
            Button("Discard", role: .destructive) {
                Task { await discardPendingFiles() }
            }

            Button("Cancel", role: .cancel) {
                pendingDiscardFiles = []
            }
        } message: {
            Text("This will permanently discard the selected uncommitted changes.")
        }
    }
}

private extension DiffViewerPane {
    var header: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diff Viewer")
                        .font(.headline)

                    Text(viewModel.activeDirectory ?? "No repository selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    guard let directory = viewModel.activeDirectory else {
                        return
                    }
                    Task {
                        await viewModel.refreshAndInvalidateFileList(in: directory, reason: .manual)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.activeDirectory == nil)
            }

            HStack(spacing: 8) {
                switch viewModel.contextualAction {
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
                        if let url = URL(string: url) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .primaryActionButtonStyle()
                case .none:
                    EmptyView()
                }

                Spacer()

                if let selectedFile = viewModel.selectedFile,
                   let directory = viewModel.activeDirectory {
                    if selectedFile.isStaged {
                        Button("Unstage") {
                            Task {
                                try? await viewModel.unstage(files: [selectedFile], in: directory)
                            }
                        }
                    } else {
                        Button("Stage") {
                            Task {
                                try? await viewModel.stage(files: [selectedFile], in: directory)
                            }
                        }
                    }

                    Button("Discard", role: .destructive) {
                        pendingDiscardFiles = [selectedFile]
                    }
                }
            }
        }
        .padding(14)
        .background(.bar)
    }

    var content: some View {
        VStack(spacing: 0) {
            List(viewModel.files) { file in
                Button {
                    guard let directory = viewModel.activeDirectory else {
                        return
                    }
                    Task {
                        await viewModel.selectFile(file, in: directory)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(statusSymbol(for: file))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(file.isStaged ? .green : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(fileDisplayName(file))
                                .lineLimit(1)
                                .foregroundStyle(.primary)

                            Text(file.isStaged ? "Staged" : "Unstaged")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected(file) ? Color.accentColor.opacity(0.14) : Color.clear)
                )
                .contextMenu {
                    if let directory = viewModel.activeDirectory {
                        if file.isStaged {
                            Button("Unstage") {
                                Task {
                                    try? await viewModel.unstage(files: [file], in: directory)
                                }
                            }
                        } else {
                            Button("Stage") {
                                Task {
                                    try? await viewModel.stage(files: [file], in: directory)
                                }
                            }
                        }

                        Button("Discard", role: .destructive) {
                            pendingDiscardFiles = [file]
                        }
                    }
                }
            }
            .overlay {
                if viewModel.files.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        heading: "Working tree is clean",
                        subtext: "There are no local changes to preview right now.",
                        actions: []
                    )
                }
            }

            Divider()

            Group {
                if let selectedFile = viewModel.selectedFile {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(fileDisplayName(selectedFile))
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)

                        ScrollView {
                            Text(viewModel.rawDiffContent.isEmpty ? "No diff preview available." : viewModel.rawDiffContent)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(14)
                        }
                    }
                } else {
                    EmptyStateView(
                        icon: "doc.plaintext",
                        heading: "Select a file",
                        subtext: "Choose a changed file to preview its diff.",
                        actions: []
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    func discardPendingFiles() async {
        guard let directory = viewModel.activeDirectory,
              !pendingDiscardFiles.isEmpty else {
            pendingDiscardFiles = []
            return
        }

        let files = pendingDiscardFiles
        pendingDiscardFiles = []
        try? await viewModel.discard(files: files, in: directory)
    }

    func isSelected(_ file: FileStatus) -> Bool {
        viewModel.selectedFile?.path == file.path && viewModel.selectedFile?.isStaged == file.isStaged
    }

    func fileDisplayName(_ file: FileStatus) -> String {
        if let originalPath = file.originalPath,
           originalPath != file.path {
            return "\(originalPath) → \(file.path)"
        }
        return file.path
    }

    func statusSymbol(for file: FileStatus) -> String {
        switch file.status {
        case .modified:
            return "●"
        case .added, .untracked:
            return "+"
        case .deleted:
            return "−"
        case .renamed:
            return "→"
        case .copied:
            return "⧉"
        case .unmerged:
            return "!"
        }
    }
}
