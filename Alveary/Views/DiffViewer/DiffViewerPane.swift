import AppKit
import SwiftUI

struct DiffViewerPane: View {
    let viewModel: DiffViewerViewModel
    let areAgentActionsEnabled: Bool
    @Binding private var topSectionFraction: CGFloat
    let onTopSectionFractionCommit: (CGFloat) -> Void
    let onCommitRequested: () -> Void
    let onOpenPRRequested: () -> Void

    @State private var pendingDiscardFiles: [FileStatus] = []

    init(
        viewModel: DiffViewerViewModel,
        areAgentActionsEnabled: Bool,
        topSectionFraction: Binding<CGFloat> = .constant(CGFloat(AppSettings.defaultDiffViewerTopSectionFraction)),
        onTopSectionFractionCommit: @escaping (CGFloat) -> Void = { _ in },
        onCommitRequested: @escaping () -> Void,
        onOpenPRRequested: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.areAgentActionsEnabled = areAgentActionsEnabled
        _topSectionFraction = topSectionFraction
        self.onTopSectionFractionCommit = onTopSectionFractionCommit
        self.onCommitRequested = onCommitRequested
        self.onOpenPRRequested = onOpenPRRequested
    }

    var body: some View {
        VStack(spacing: 0) {
            DiffViewerPaneHeader(
                activeDirectory: viewModel.activeDirectory,
                contextualAction: viewModel.contextualAction,
                selectedFile: viewModel.selectedFile,
                areAgentActionsEnabled: areAgentActionsEnabled,
                onRefresh: {
                    guard let directory = viewModel.activeDirectory else {
                        return
                    }
                    Task {
                        await viewModel.refreshAndInvalidateFileList(in: directory, reason: .manual)
                    }
                },
                onCommitRequested: onCommitRequested,
                onOpenPRRequested: onOpenPRRequested,
                onViewPRRequested: { url in
                    guard let url = URL(string: url) else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                },
                onStageSelectedFile: {
                    guard let selectedFile = viewModel.selectedFile,
                          let directory = viewModel.activeDirectory else {
                        return
                    }

                    Task {
                        await performGitAction(errorPrefix: "Stage failed") {
                            try await viewModel.stage(files: [selectedFile], in: directory)
                        }
                    }
                },
                onUnstageSelectedFile: {
                    guard let selectedFile = viewModel.selectedFile,
                          let directory = viewModel.activeDirectory else {
                        return
                    }

                    Task {
                        await performGitAction(errorPrefix: "Unstage failed") {
                            try await viewModel.unstage(files: [selectedFile], in: directory)
                        }
                    }
                },
                onDiscardSelectedFile: {
                    guard let selectedFile = viewModel.selectedFile else {
                        return
                    }
                    pendingDiscardFiles = [selectedFile]
                }
            )

            if let gitError = viewModel.gitError {
                InlineBanner(message: gitError, severity: .error, autoDismissAfter: nil, onDismiss: viewModel.clearGitError)
                    .padding(12)
            }

            if viewModel.activeDirectory == nil {
                EmptyStateView(
                    icon: "rectangle.split.3x1",
                    heading: "No diff context",
                    subtext: "Select a thread to inspect project changes and diff previews.",
                    actions: []
                )
            } else {
                GeometryReader { proxy in
                    let contentHeight = max(proxy.size.height - DiffViewerVerticalResizeHandle.thickness, 0)
                    let topSectionHeight = contentHeight * clampedTopSectionFraction(topSectionFraction)
                    let bottomSectionHeight = max(contentHeight - topSectionHeight, 0)

                    VStack(spacing: 0) {
                        DiffViewerFileListSection(
                            files: viewModel.files,
                            isGitRepository: viewModel.isGitRepository,
                            isLoading: viewModel.isLoadingFiles,
                            isSelected: isSelected,
                            fileDisplayName: fileDisplayName,
                            statusSymbol: statusSymbol,
                            onSelectFile: { file in
                                guard let directory = viewModel.activeDirectory else {
                                    return
                                }

                                Task {
                                    await viewModel.selectFile(file, in: directory)
                                }
                            },
                            onStageFile: { file in
                                guard let directory = viewModel.activeDirectory else {
                                    return
                                }

                                Task {
                                    await performGitAction(errorPrefix: "Stage failed") {
                                        try await viewModel.stage(files: [file], in: directory)
                                    }
                                }
                            },
                            onUnstageFile: { file in
                                guard let directory = viewModel.activeDirectory else {
                                    return
                                }

                                Task {
                                    await performGitAction(errorPrefix: "Unstage failed") {
                                        try await viewModel.unstage(files: [file], in: directory)
                                    }
                                }
                            },
                            onDiscardFile: { file in
                                pendingDiscardFiles = [file]
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: topSectionHeight)

                        DiffViewerVerticalResizeHandle(
                            splitFraction: $topSectionFraction,
                            totalHeight: contentHeight,
                            bounds: AppSettings.supportedDiffViewerSplitRange,
                            onCommit: onTopSectionFractionCommit
                        )

                        DiffViewerPreviewSection(
                            selectedFile: viewModel.selectedFile,
                            parsedDiff: viewModel.parsedDiff,
                            rawDiffContent: viewModel.rawDiffContent,
                            isLoading: viewModel.isLoadingSelectedDiff,
                            fileDisplayName: fileDisplayName,
                            statusTitle: statusTitle,
                            diffPreviewIdentity: diffPreviewIdentity
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: bottomSectionHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    func clampedTopSectionFraction(_ candidate: CGFloat) -> CGFloat {
        let lowerBound = CGFloat(AppSettings.supportedDiffViewerSplitRange.lowerBound)
        let upperBound = CGFloat(AppSettings.supportedDiffViewerSplitRange.upperBound)
        return min(max(candidate, lowerBound), upperBound)
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

}

private struct DiffViewerVerticalResizeHandle: View {
    static let thickness: CGFloat = 8

    @Binding var splitFraction: CGFloat
    @Environment(\.displayScale) private var displayScale

    let totalHeight: CGFloat
    let bounds: ClosedRange<Double>
    let onCommit: (CGFloat) -> Void

    @State private var dragStartFraction: CGFloat?
    @State private var isHovering = false
    @State private var hasPushedCursor = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isHovering ? Color.accentColor : Color(nsColor: .separatorColor))
                .frame(height: 1)

            Rectangle()
                .fill(isHovering ? Color.accentColor.opacity(0.18) : Color.clear)
                .frame(height: 6)
        }
        .frame(height: Self.thickness)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering, !hasPushedCursor {
                NSCursor.resizeUpDown.push()
                hasPushedCursor = true
            } else if !hovering, hasPushedCursor {
                NSCursor.pop()
                hasPushedCursor = false
            }
        }
        .onDisappear {
            guard hasPushedCursor else {
                return
            }

            NSCursor.pop()
            hasPushedCursor = false
        }
        .gesture(
            // Keep drag deltas in global coordinates so they stay stable while the
            // resize handle itself shifts as the split moves.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    let startFraction = dragStartFraction ?? splitFraction
                    if dragStartFraction == nil {
                        dragStartFraction = startFraction
                    }
                    splitFraction = snappedFraction(startFraction + (value.translation.height / max(totalHeight, 1)))
                }
                .onEnded { value in
                    let startFraction = dragStartFraction ?? splitFraction
                    let committedFraction = snappedFraction(startFraction + (value.translation.height / max(totalHeight, 1)))
                    splitFraction = committedFraction
                    dragStartFraction = nil
                    onCommit(committedFraction)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Resize diff sections")
        .accessibilityHint("Drag up or down to resize the file list and diff preview.")
        .accessibilityValue("Top section \(Int((splitFraction * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let delta = CGFloat(0.05)
            let updatedFraction: CGFloat

            switch direction {
            case .increment:
                updatedFraction = snappedFraction(splitFraction + delta)
            case .decrement:
                updatedFraction = snappedFraction(splitFraction - delta)
            @unknown default:
                updatedFraction = splitFraction
            }

            splitFraction = updatedFraction
            onCommit(updatedFraction)
        }
    }

    private func snappedFraction(_ candidate: CGFloat) -> CGFloat {
        let lowerBound = CGFloat(bounds.lowerBound)
        let upperBound = CGFloat(bounds.upperBound)
        let clamped = min(max(candidate, lowerBound), upperBound)

        guard totalHeight > 0 else {
            return clamped
        }

        let pixelStep = max(1 / max(displayScale, 1), 0.5)
        let steppedHeight = ((clamped * totalHeight) / pixelStep).rounded() * pixelStep
        let steppedFraction = steppedHeight / totalHeight
        return min(max(steppedFraction, lowerBound), upperBound)
    }
}
