import AppKit
import SwiftUI

struct DiffViewerFileListSection: View {
    let files: [FileStatus]
    let selectedFiles: [FileStatus]
    let isGitRepository: Bool
    let isLoading: Bool
    let isSelected: (FileStatus) -> Bool
    let fileDisplayName: (FileStatus) -> String
    let onSelectFile: (FileStatus, DiffViewerFileSelectionBehavior) -> Void
    let onSelectAllFiles: @MainActor () -> Void
    let onNavigateFile: (Bool, DiffViewerFileSelectionBehavior) -> String?
    let onStageFiles: ([FileStatus]) -> Void
    let onUnstageFiles: ([FileStatus]) -> Void
    let onDiscardFiles: ([FileStatus]) -> Void

    @Binding var isTopDividerVisible: Bool

    @State private var verticalOffsetFromTop: CGFloat = 0
    @State private var scrollController = DiffViewerListScrollController()
    @State private var latestKeyboardNavigationScrollID = UUID()
    @State private var hasClaimedKeyboardFocus = false
    @FocusState private var isKeyboardFocused: Bool
    @FocusedValue(\.chatComposerFocus) private var chatComposerFocus

    var body: some View {
        ScrollViewReader { scrollProxy in
            List(files) { file in
                HStack(spacing: 10) {
                    Circle()
                        .fill(statusColor(for: file))
                        .frame(width: 8, height: 8)

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
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(file.path)
                .appSelectableRow(
                    isSelected: isSelected(file),
                    identity: file.id,
                    selectionBackgroundLeadingInset: DiffViewerPaneMetrics.selectionBackgroundLeadingInset,
                    selectionBackgroundTrailingInset: DiffViewerPaneMetrics.selectionBackgroundTrailingInset,
                    action: {
                        claimKeyboardFocus()
                        onSelectFile(file, currentSelectionBehavior)
                    }
                )
                .background {
                    DiffViewerSecondaryClickSelectionTarget {
                        claimKeyboardFocus()
                        if !isSelected(file) {
                            onSelectFile(file, .single)
                        }
                    }
                }
                .contextMenu {
                    let actionFiles = contextMenuFiles(for: file)
                    if actionFiles.contains(where: { !$0.isStaged }) {
                        Button("Stage") {
                            performContextMenuAction(for: file, action: onStageFiles)
                        }
                    }

                    if actionFiles.contains(where: \.isStaged) {
                        Button("Unstage") {
                            performContextMenuAction(for: file, action: onUnstageFiles)
                        }
                    }

                    Button("Discard", role: .destructive) {
                        performContextMenuAction(for: file, action: onDiscardFiles)
                    }
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .contentMargins(.bottom, 4, for: .scrollContent)
            .clipped()
            .focusable()
            .focused($isKeyboardFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, KeyEquivalent("a")]) { keyPress in
                handleKeyPress(keyPress, scrollProxy: scrollProxy)
            }
            .background {
                ZStack {
                    DiffViewerFileListScrollMonitor(
                        fileIDs: fileIDs,
                        verticalOffsetFromTop: $verticalOffsetFromTop,
                        scrollController: scrollController
                    )
                    DiffViewerTopListKeyboardMonitor(isEnabled: hasClaimedKeyboardFocus || isKeyboardFocused) { event in
                        handleKeyDown(event, scrollProxy: scrollProxy)
                    }
                }
            }
            .overlay {
                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Loading changes…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if files.isEmpty {
                    if isGitRepository {
                        EmptyStateView(
                            icon: "checkmark.circle",
                            heading: "Working tree is clean",
                            subtext: "There are no local changes to preview right now.",
                            actions: []
                        )
                    } else {
                        EmptyStateView(
                            icon: "tray",
                            heading: "Git features unavailable",
                            subtext: "This project is not a Git repository, so there are no Git diffs to show.",
                            actions: []
                        )
                    }
                }
            }
            .onAppear {
                isTopDividerVisible = shouldShowTopDivider
            }
            .onChange(of: shouldShowTopDivider) { _, isVisible in
                isTopDividerVisible = isVisible
            }
            .onDisappear {
                latestKeyboardNavigationScrollID = UUID()
                hasClaimedKeyboardFocus = false
                isTopDividerVisible = false
            }
            .onChange(of: isKeyboardFocused) { _, isFocused in
                if isFocused {
                    hasClaimedKeyboardFocus = true
                }
            }
            .onChange(of: fileIDs) { _, newFileIDs in
                preserveTopPositionIfNeeded(scrollProxy: scrollProxy, fileIDs: newFileIDs)
            }
        }
    }

    private var fileIDs: [String] {
        files.map(\.id)
    }

    private func statusColor(for file: FileStatus) -> Color {
        file.isStaged ? .green : .secondary
    }

    private var shouldShowTopDivider: Bool {
        !files.isEmpty && verticalOffsetFromTop > 0.5
    }

    private func handleKeyPress(_ keyPress: KeyPress, scrollProxy: ScrollViewProxy) -> KeyPress.Result {
        switch keyPress.key {
        case .upArrow:
            navigateFile(
                forward: false,
                behavior: keyboardNavigationSelectionBehavior(for: keyPress),
                scrollProxy: scrollProxy
            )
            return .handled
        case .downArrow:
            navigateFile(
                forward: true,
                behavior: keyboardNavigationSelectionBehavior(for: keyPress),
                scrollProxy: scrollProxy
            )
            return .handled
        case KeyEquivalent("a") where keyPress.modifiers.contains(.command):
            onSelectAllFiles()
            return .handled
        default:
            return .ignored
        }
    }

    private func handleKeyDown(_ event: NSEvent, scrollProxy: ScrollViewProxy) -> Bool {
        if isSelectAllKey(event) {
            onSelectAllFiles()
            return true
        }

        switch event.keyCode {
        case DiffViewerTopListKeyCode.upArrow:
            navigateFile(
                forward: false,
                behavior: keyboardNavigationSelectionBehavior(for: event),
                scrollProxy: scrollProxy
            )
            return true
        case DiffViewerTopListKeyCode.downArrow:
            navigateFile(
                forward: true,
                behavior: keyboardNavigationSelectionBehavior(for: event),
                scrollProxy: scrollProxy
            )
            return true
        default:
            return false
        }
    }

    private func claimKeyboardFocus() {
        latestKeyboardNavigationScrollID = UUID()
        hasClaimedKeyboardFocus = true
        chatComposerFocus?.release()
        isKeyboardFocused = false
        Task { @MainActor in
            isKeyboardFocused = true
        }
    }

    private func navigateFile(
        forward: Bool,
        behavior: DiffViewerFileSelectionBehavior,
        scrollProxy: ScrollViewProxy
    ) {
        guard let fileID = onNavigateFile(forward, behavior) else {
            return
        }
        scrollSelectionIntoView(scrollProxy: scrollProxy, id: fileID)
    }

    private var currentSelectionBehavior: DiffViewerFileSelectionBehavior {
        let flags = NSEvent.modifierFlags
        let isCommandPressed = flags.contains(.command)
        let isShiftPressed = flags.contains(.shift)

        switch (isCommandPressed, isShiftPressed) {
        case (true, true):
            return .rangeUnion
        case (true, false):
            return .toggle
        case (false, true):
            return .range
        case (false, false):
            return .single
        }
    }

    private func keyboardNavigationSelectionBehavior(for keyPress: KeyPress) -> DiffViewerFileSelectionBehavior {
        let isCommandPressed = keyPress.modifiers.contains(.command)
        let isShiftPressed = keyPress.modifiers.contains(.shift)

        return keyboardNavigationSelectionBehavior(isCommandPressed: isCommandPressed, isShiftPressed: isShiftPressed)
    }

    private func keyboardNavigationSelectionBehavior(for event: NSEvent) -> DiffViewerFileSelectionBehavior {
        let isCommandPressed = event.modifierFlags.contains(.command)
        let isShiftPressed = event.modifierFlags.contains(.shift)

        return keyboardNavigationSelectionBehavior(isCommandPressed: isCommandPressed, isShiftPressed: isShiftPressed)
    }

    private func keyboardNavigationSelectionBehavior(
        isCommandPressed: Bool,
        isShiftPressed: Bool
    ) -> DiffViewerFileSelectionBehavior {
        switch (isCommandPressed, isShiftPressed) {
        case (true, true):
            return .rangeUnion
        case (_, true):
            return .range
        default:
            return .single
        }
    }

    private func isSelectAllKey(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "a"
    }

    private func performContextMenuAction(
        for file: FileStatus,
        action: ([FileStatus]) -> Void
    ) {
        let actionFiles = contextMenuFiles(for: file)
        if !isSelected(file) {
            onSelectFile(file, .single)
        }
        action(actionFiles)
    }

    private func contextMenuFiles(for file: FileStatus) -> [FileStatus] {
        isSelected(file) ? selectedFiles : [file]
    }

    private func preserveTopPositionIfNeeded(
        scrollProxy: ScrollViewProxy,
        fileIDs: [String]
    ) {
        guard verticalOffsetFromTop <= 1,
              let firstFileID = fileIDs.first else {
            return
        }

        scrollToTop(scrollProxy: scrollProxy, firstFileID: firstFileID)
        DispatchQueue.main.async {
            scrollToTop(scrollProxy: scrollProxy, firstFileID: firstFileID)
        }
    }

    private func scrollToTop(scrollProxy: ScrollViewProxy, firstFileID: String) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollProxy.scrollTo(firstFileID, anchor: .top)
        }
        verticalOffsetFromTop = 0
    }

    private func scrollSelectionIntoView(scrollProxy: ScrollViewProxy, id: String) {
        let scrollID = UUID()
        latestKeyboardNavigationScrollID = scrollID
        if id == fileIDs.first {
            scrollToListBoundary(scrollProxy: scrollProxy, rowID: id, edge: .top, scrollID: scrollID)
        } else if id == fileIDs.last {
            scrollToListBoundary(scrollProxy: scrollProxy, rowID: id, edge: .bottom, scrollID: scrollID)
        } else {
            scrollToRow(scrollProxy: scrollProxy, rowID: id, scrollID: scrollID)
        }
    }

    private func scrollToListBoundary(
        scrollProxy: ScrollViewProxy,
        rowID: String,
        edge: DiffViewerListScrollEdge,
        scrollID: UUID
    ) {
        let didScroll = scrollController.scroll(to: edge, animated: true)
        if !didScroll {
            withAnimation(.easeInOut(duration: 0.18)) {
                scrollProxy.scrollTo(rowID, anchor: edge.fallbackAnchor)
            }
        }

        // `List` can settle its AppKit document geometry after SwiftUI publishes selection.
        // Reissue on later ticks so the final position reaches the actual content bound.
        DispatchQueue.main.async {
            guard latestKeyboardNavigationScrollID == scrollID else {
                return
            }
            if !scrollController.scroll(to: edge, animated: true) {
                scrollProxy.scrollTo(rowID, anchor: edge.fallbackAnchor)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard latestKeyboardNavigationScrollID == scrollID else {
                return
            }
            _ = scrollController.scroll(to: edge, animated: false)
        }
    }

    private func scrollToRow(scrollProxy: ScrollViewProxy, rowID: String, scrollID: UUID) {
        withAnimation(.easeInOut(duration: 0.18)) {
            scrollProxy.scrollTo(rowID)
        }
        DispatchQueue.main.async {
            guard latestKeyboardNavigationScrollID == scrollID else {
                return
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                scrollProxy.scrollTo(rowID)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard latestKeyboardNavigationScrollID == scrollID else {
                return
            }
            scrollProxy.scrollTo(rowID)
        }
    }
}
