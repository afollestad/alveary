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
                let files = pendingDiscardFiles
                let directory = viewModel.activeDirectory
                pendingDiscardFiles = []

                Task {
                    await discardPendingFiles(files: files, in: directory)
                }
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
                                await performGitAction(errorPrefix: "Unstage failed") {
                                    try await viewModel.unstage(files: [selectedFile], in: directory)
                                }
                            }
                        }
                        .secondaryActionButtonStyle()
                    } else {
                        Button("Stage") {
                            Task {
                                await performGitAction(errorPrefix: "Stage failed") {
                                    try await viewModel.stage(files: [selectedFile], in: directory)
                                }
                            }
                        }
                        .secondaryActionButtonStyle()
                    }

                    Button("Discard", role: .destructive) {
                        pendingDiscardFiles = [selectedFile]
                    }
                    .destructiveActionButtonStyle()
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
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(isSelected(file) ? .isSelected : [])
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBackground(for: file))
                .contextMenu {
                    if let directory = viewModel.activeDirectory {
                        if file.isStaged {
                            Button("Unstage") {
                                Task {
                                    await performGitAction(errorPrefix: "Unstage failed") {
                                        try await viewModel.unstage(files: [file], in: directory)
                                    }
                                }
                            }
                        } else {
                            Button("Stage") {
                                Task {
                                    await performGitAction(errorPrefix: "Stage failed") {
                                        try await viewModel.stage(files: [file], in: directory)
                                    }
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
                    VStack(alignment: .leading, spacing: 4) {
                        DiffPreviewHeader(
                            title: fileDisplayName(selectedFile),
                            fileStatus: selectedFile,
                            parsedDiff: viewModel.parsedDiff,
                            statusTitle: statusTitle(for: selectedFile.status)
                        )

                        DiffPreviewContent(
                            parsedDiff: viewModel.parsedDiff,
                            rawDiffContent: viewModel.rawDiffContent,
                            isLoading: viewModel.isLoadingSelectedDiff
                        )
                        .id(diffPreviewIdentity(for: selectedFile))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    func discardPendingFiles(files: [FileStatus], in directory: String?) async {
        guard let directory,
              !files.isEmpty else {
            return
        }

        await performGitAction(errorPrefix: "Discard failed") {
            try await viewModel.discard(files: files, in: directory)
        }
    }

    func performGitAction(errorPrefix: String, action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            viewModel.presentGitError("\(errorPrefix): \(error.localizedDescription)")
        }
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

    func statusTitle(for status: FileStatus.Status) -> String {
        switch status {
        case .modified:
            return "Modified"
        case .added:
            return "Added"
        case .deleted:
            return "Deleted"
        case .renamed:
            return "Renamed"
        case .copied:
            return "Copied"
        case .untracked:
            return "Untracked"
        case .unmerged:
            return "Unmerged"
        }
    }

    func diffPreviewIdentity(for file: FileStatus) -> String {
        [
            file.id,
            file.originalPath ?? "",
            file.status.rawValue,
            String(viewModel.rawDiffContent.count)
        ].joined(separator: "|")
    }

    func rowBackground(for file: FileStatus) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected(file) ? selectedRowFillColor : Color.clear)
            .padding(.horizontal, 10)
    }

    var selectedRowFillColor: Color {
        let backgroundColor = NSColor.textBackgroundColor.usingColorSpace(.deviceRGB) ?? .textBackgroundColor
        let accentColor = NSColor.controlAccentColor.usingColorSpace(.deviceRGB) ?? .systemBlue
        return Color(nsColor: backgroundColor.blended(withFraction: 0.18, of: accentColor) ?? accentColor)
    }
}
