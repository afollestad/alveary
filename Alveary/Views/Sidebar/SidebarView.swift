import SwiftData
import SwiftUI

private enum SidebarProjectListMetrics {
    static let subsequentProjectTopSpacing: CGFloat = 4
}

struct SidebarView: View {
    let viewModel: SidebarViewModel
    @Bindable var appState: AppState

    @Environment(\.modelContext) var uiModelContext
    @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
    @Query private var queriedProjects: [Project]
    @State var expandedProjects: Set<String> = []
    @State var editingThreadID: PersistentIdentifier?
    @State var pendingArchiveThread: AgentThread?
    @State var pendingDeleteThread: AgentThread?
    @State var pendingDeleteProject: Project?
    @FocusState var isKeyboardFocused: Bool
    @FocusedValue(\.chatComposerFocus) var chatComposerFocus

    var projects: [Project] {
        queriedProjects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var threadOrderAnimation: Animation? {
        guard !accessibilityReduceMotion,
              editingThreadID == nil,
              expandedThreadCount <= 200 else {
            return nil
        }
        return .easeInOut(duration: 0.15)
    }

    private var expandedThreadCount: Int {
        pinnedThreads().count + projects.reduce(0) { count, project in
            guard expandedProjects.contains(project.path) else {
                return count
            }
            return count + activeThreads(for: project).count
        }
    }

    private var projectsHeader: some View {
        SidebarSectionHeaderRow(title: "Projects") {
            appState.openNewProjectFlow()
        }
    }

    private var pinnedHeader: some View {
        SidebarSectionHeaderRow(title: "Pinned")
    }

    @ViewBuilder
    private var projectsRows: some View {
        if projects.isEmpty {
            Text("No projects yet")
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }

        ForEach(projects.indices, id: \.self) { index in
            let project = projects[index]
            let isExpanded = expandedProjects.contains(project.path)
            let activeProjectThreads = activeThreads(for: project)
            let firstThreadID = activeProjectThreads.first?.persistentModelID
            let topSpacing: CGFloat = index == 0 ? 0 : SidebarProjectListMetrics.subsequentProjectTopSpacing

            SidebarProjectRow(
                project: project,
                isExpanded: isExpanded,
                isSelected: appState.selectedSidebarItem == .project(project),
                onToggleExpanded: {
                    toggleExpansion(for: project.path, in: &expandedProjects)
                    claimSidebarFocus()
                },
                onActivate: {
                    activateProject(project)
                },
                onCreateThread: {
                    Task { await createThread(in: project) }
                }
            )
            .padding(.top, topSpacing)
            .appSelectionRowBackground(
                isSelected: appState.selectedSidebarItem == .project(project),
                topInset: topSpacing
            )
            .contextMenu {
                Button("New Thread") {
                    Task { await createThread(in: project) }
                }

                Button("Remove Project...", role: .destructive) {
                    pendingDeleteProject = project
                }
            }

            if isExpanded {
                if shouldShowNoThreadsPlaceholder(
                    activeProjectThreads: activeProjectThreads,
                    hasAnyActiveThreads: hasAnyActiveThreads(for: project)
                ) {
                    Text("No threads")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6.75)
                        .padding(.leading, SidebarProjectRow.projectNameLeadingInset)
                        .allowsHitTesting(false)
                }

                ForEach(activeProjectThreads, id: \.persistentModelID) { thread in
                    let threadTopSpacing: CGFloat = thread.persistentModelID == firstThreadID
                        ? 0
                        : SidebarRowMetrics.interThreadRowSpacing
                    sidebarThreadRow(
                        thread,
                        layout: .project,
                        topSpacing: threadTopSpacing
                    )
                }
                .transaction { transaction in
                    if threadOrderAnimation == nil {
                        transaction.disablesAnimations = true
                        transaction.animation = nil
                    }
                }
            }
        }
    }

    var body: some View {
        let statusVersion = viewModel.statusVersion
        let threadOrderVersion = viewModel.threadOrderVersion
        let pinnedThreads = self.pinnedThreads()

        return VStack(spacing: 0) {
            if let sidebarError = viewModel.sidebarError {
                InlineBanner(message: sidebarError, severity: .error, autoDismissAfter: nil, onDismiss: viewModel.dismissSidebarError)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            List {
                Section {
                    topLevelRow(
                        title: "Skills",
                        systemImage: "puzzlepiece.extension",
                        item: .skills,
                        bottomSpacing: SidebarRowMetrics.topLevelRowSpacing
                    )

                    topLevelRow(
                        title: "MCP",
                        systemImage: "server.rack",
                        item: .mcp
                    )

                    if !pinnedThreads.isEmpty {
                        pinnedHeader

                        ForEach(pinnedThreads, id: \.persistentModelID) { thread in
                            sidebarThreadRow(
                                thread,
                                layout: .topLevel,
                                topSpacing: thread.persistentModelID == pinnedThreads.first?.persistentModelID
                                    ? 0
                                    : SidebarRowMetrics.interThreadRowSpacing
                            )
                        }
                        .transaction { transaction in
                            if threadOrderAnimation == nil {
                                transaction.disablesAnimations = true
                                transaction.animation = nil
                            }
                        }

                        projectsHeader
                        projectsRows
                    }
                }

                if pinnedThreads.isEmpty {
                    Section {
                        projectsRows
                    } header: {
                        projectsHeader
                    }
                }
            }
            .listStyle(.sidebar)
            .focusable()
            .focused($isKeyboardFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, Self.backspaceKey], action: handleSidebarKeyPress)
        }
        .onAppear {
            syncExpansionWithSelection(appState.selectedSidebarItem)
        }
        .onChange(of: appState.selectedSidebarItem) { _, item in
            syncExpansionWithSelection(item)
            // Skip the focus claim when a command has requested the composer grab focus
            // (e.g. ⌘N). The BlockInput composer consumes and clears the token.
            if appState.pendingComposerFocusToken == nil {
                claimSidebarFocus()
            }
        }
        .onChange(of: appState.pendingComposerFocusToken) { _, token in
            // Release the sidebar's `@FocusState` claim so the composer can take AppKit
            // first responder without a fight. Without this, a sidebar that already holds
            // `isKeyboardFocused = true` (from prior keyboard navigation) keeps reclaiming
            // AppKit focus via `.focused($isKeyboardFocused)` while the composer tries to
            // take over.
            if token != nil {
                isKeyboardFocused = false
            }
        }
        .animation(threadOrderAnimation, value: threadOrderVersion)
        .animation(nil, value: statusVersion)
        .confirmationDialog(
            "Archive thread?",
            isPresented: Binding(
                get: { pendingArchiveThread != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingArchiveThread = nil
                    }
                }
            ),
            presenting: pendingArchiveThread
        ) { thread in
            Button("Archive") {
                pendingArchiveThread = nil
                Task { await archive(thread) }
            }

            Button("Cancel", role: .cancel) {
                pendingArchiveThread = nil
            }
        } message: { thread in
            Text(archiveConfirmationMessage(for: thread))
        }
        .confirmationDialog(
            "Delete thread?",
            isPresented: Binding(
                get: { pendingDeleteThread != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteThread = nil
                    }
                }
            ),
            presenting: pendingDeleteThread
        ) { thread in
            Button("Delete", role: .destructive) {
                Task { await confirmDeleteThread(thread) }
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteThread = nil
            }
        } message: { thread in
            Text(deleteConfirmationMessage(for: thread))
        }
        .confirmationDialog(
            "Remove project?",
            isPresented: Binding(
                get: { pendingDeleteProject != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteProject = nil
                    }
                }
            ),
            presenting: pendingDeleteProject
        ) { project in
            Button("Remove Project", role: .destructive) {
                Task { await confirmDeleteProject(project) }
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteProject = nil
            }
        } message: { project in
            Text(
                "Remove \(project.name) from Alveary, and delete its threads and worktrees? " +
                    "The main project folder will not be touched."
            )
        }
    }

    func archiveConfirmationMessage(for thread: AgentThread) -> String {
        "This archives \"\(thread.displayName())\". "
            + "You can find archived threads in the selected project's settings, at the bottom under Archived Threads."
    }

    func deleteConfirmationMessage(for thread: AgentThread) -> String {
        threadDeleteConfirmationMessage(for: thread)
    }

    func sidebarThreadRow(
        _ thread: AgentThread,
        layout: SidebarThreadRowLayout,
        topSpacing: CGFloat
    ) -> some View {
        let isSelected = appState.selectedSidebarItem == .thread(thread)
        let cleanupAction = viewModel.defaultThreadCleanupAction
        let leadingPadding: CGFloat = layout == .topLevel ? SidebarSectionHeaderRow.contentLeadingPadding : 14

        return SidebarThreadRow(
            thread: thread,
            status: viewModel.threadStatus(for: thread),
            isSelected: isSelected,
            layout: layout,
            editingThreadID: $editingThreadID,
            cleanupAction: cleanupAction,
            onCommitRename: { newName in
                renameThread(thread, to: newName)
            },
            onConfirmCleanup: {
                Task {
                    switch cleanupAction {
                    case .archive:
                        await archive(thread)
                    case .delete:
                        await confirmDeleteThread(thread)
                    }
                }
            }
        )
        .padding(.leading, leadingPadding)
        .padding(.top, topSpacing)
        .appSelectableRow(
            isSelected: isSelected,
            selectionBackgroundTopInset: topSpacing,
            action: { activateThread(thread) }
        )
        .contextMenu {
            sidebarThreadContextMenu(for: thread)
        }
    }

    @ViewBuilder
    func sidebarThreadContextMenu(for thread: AgentThread) -> some View {
        ForEach(sidebarThreadContextMenuItems(isPinned: thread.isPinned, canRename: editingThreadID == nil), id: \.self) { item in
            switch item {
            case .forkLocal:
                Button("Fork into local") {
                    Task { await forkThread(thread, mode: .local) }
                }
            case .forkWorktree:
                Button("Fork into worktree") {
                    Task { await forkThread(thread, mode: .worktree) }
                }
            case .divider:
                Divider()
            case .pin:
                Button("Pin") {
                    setThreadPinned(thread, isPinned: true)
                }
            case .unpin:
                Button("Unpin") {
                    setThreadPinned(thread, isPinned: false)
                }
            case .rename:
                Button("Rename...") {
                    editingThreadID = thread.persistentModelID
                }
            case .archive:
                Button("Archive...") {
                    pendingArchiveThread = thread
                }
            case .delete:
                Button("Delete...", role: .destructive) {
                    pendingDeleteThread = thread
                }
            }
        }
    }

    // Driven by explicit user actions (row tap, selection change, expansion toggle),
    // not by `.onChange(of: isKeyboardFocused)`. The reactive change handler also fires
    // when SwiftUI's `.focused($isKeyboardFocused)` re-claims the List after another
    // view briefly takes focus, which would yank focus back from the composer the
    // moment the user clicks into it.
    //
    // Always call this from row taps too — clicking the *already-selected* row does
    // not mutate `selectedSidebarItem`, so the `.onChange` hook never fires and the
    // composer would otherwise keep AppKit first-responder while the user expects
    // arrow keys to drive the sidebar.
    //
    // Clears `pendingComposerFocusToken` up front so a racing sidebar takeover
    // cancels an unconsumed composer-focus request. Without this, a user who presses
    // ⌘N and immediately clicks a different sidebar row before the new composer
    // mounts would see that composer steal first responder back once it mounts and
    // consumes the stale token.
    func claimSidebarFocus() {
        appState.pendingComposerFocusToken = nil
        chatComposerFocus?.release()
        isKeyboardFocused = true
    }
}

func shouldShowNoThreadsPlaceholder(
    activeProjectThreads: [AgentThread],
    hasAnyActiveThreads: Bool
) -> Bool {
    activeProjectThreads.isEmpty && !hasAnyActiveThreads
}
