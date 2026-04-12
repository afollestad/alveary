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
        GeometryReader { proxy in
            let contentHeight = max(proxy.size.height - DiffViewerVerticalResizeHandle.thickness, 0)
            let topSectionHeight = contentHeight * clampedTopSectionFraction(topSectionFraction)
            let bottomSectionHeight = max(contentHeight - topSectionHeight, 0)

            VStack(spacing: 0) {
                fileListSection
                    .frame(maxWidth: .infinity)
                    .frame(height: topSectionHeight)

                DiffViewerVerticalResizeHandle(
                    splitFraction: $topSectionFraction,
                    totalHeight: contentHeight,
                    bounds: AppSettings.supportedDiffViewerSplitRange,
                    onCommit: onTopSectionFractionCommit
                )

                previewSection
                    .frame(maxWidth: .infinity)
                    .frame(height: bottomSectionHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var fileListSection: some View {
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
    }

    var previewSection: some View {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
