import AppKit
import SwiftData
import SwiftUI

enum SidebarProjectListMetrics {
    static let subsequentProjectTopSpacing: CGFloat = 4

    // SwiftUI `List` section headers omit the real project row's trailing action column inset.
    @MainActor static var listSectionHeaderTrailingCorrection: CGFloat {
        SidebarSectionHeaderRow.actionButtonCenterTrailingInset
    }
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
    @State var sidebarDragInteractionState = SidebarDragInteractionState.idle
    @State var sidebarDragPointerRelay = SidebarDragPointerRelay()
    @State var sidebarDropCandidate: SidebarDropCandidate?
    @State var sidebarDragGeometryFrames: [SidebarDragGeometryRole: [CGRect]] = [:]
    @State var sidebarDragGeometryRefreshRevision: UInt64 = 0
    @State var sidebarDragGeometryMissToken: UUID?
    @FocusState var isKeyboardFocused: Bool
    @FocusedValue(\.chatComposerFocus) var chatComposerFocus

    var projects: [Project] {
        viewModel.orderedProjects(from: queriedProjects)
    }

    var regularProjects: [Project] {
        viewModel.regularProjects(from: projects)
    }

    var threadOrderAnimation: Animation? {
        guard !accessibilityReduceMotion,
              editingThreadID == nil,
              !isSidebarDragInteractionInFlight,
              expandedThreadCount <= 200 else {
            return nil
        }
        return .easeInOut(duration: 0.15)
    }

    private var expandedThreadCount: Int {
        let pinnedThreadCount = pinnedItems().reduce(0) { count, item in
            switch item.kind {
            case .thread:
                return count + 1
            case .project(let project):
                guard expandedProjects.contains(project.path) else {
                    return count
                }
                return count + activeThreads(for: project).count
            }
        }

        return pinnedThreadCount + regularProjects.reduce(0) { count, project in
            guard expandedProjects.contains(project.path) else {
                return count
            }
            return count + activeThreads(for: project).count
        }
    }

    private func projectsHeader(isListSectionHeader: Bool) -> some View {
        SidebarSectionHeaderRow(title: "Projects") {
            appState.openNewProjectFlow()
        }
        .padding(
            .trailing,
            isListSectionHeader ? SidebarProjectListMetrics.listSectionHeaderTrailingCorrection : 0
        )
        .sidebarDragGeometry(.projectsHeader)
    }

    private var pinnedHeader: some View {
        SidebarSectionHeaderRow(title: "Pinned")
            .sidebarDragGeometry(.pinnedHeader)
    }

    var body: some View {
        let statusVersion = viewModel.statusVersion
        let threadOrderVersion = viewModel.threadOrderVersion
        let pinnedItems = self.pinnedItems()
        let regularProjects = self.regularProjects
        let visibleDragItems = Set(
            pinnedItems.map(\.dragItem) + regularProjects.map { .project($0.persistentModelID) }
        )
        let projectsHeaderIsListSectionHeader = pinnedItems.isEmpty

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

                    if !pinnedItems.isEmpty {
                        pinnedHeader

                        ForEach(pinnedItems) { item in
                            let topSpacing: CGFloat = item.id == pinnedItems.first?.id
                                ? 0
                                : SidebarRowMetrics.interThreadRowSpacing
                            switch item.kind {
                            case .project(let project):
                                projectRow(project, topSpacing: topSpacing, dropSection: .pinned)
                            case .thread(let thread):
                                sidebarThreadRow(
                                    thread,
                                    layout: .topLevel,
                                    topSpacing: topSpacing,
                                    dragConfiguration: pinnedThreadDragConfiguration(for: thread),
                                    opacity: activeSidebarDragItem == .pinnedThread(thread.persistentModelID) ? 0.48 : 1
                                )
                                .sidebarDragGeometry(.pinnedThread(thread.persistentModelID))
                            }
                        }
                        .transaction { transaction in
                            if threadOrderAnimation == nil {
                                transaction.disablesAnimations = true
                                transaction.animation = nil
                            }
                        }

                        projectsHeader(isListSectionHeader: projectsHeaderIsListSectionHeader)
                        projectRows(
                            regularProjects,
                            showsNoProjectsPlaceholder: projects.isEmpty,
                            dropSection: .projects
                        )
                    }
                }

                if pinnedItems.isEmpty {
                    Section {
                        projectRows(
                            projects,
                            showsNoProjectsPlaceholder: projects.isEmpty,
                            dropSection: .projects
                        )
                    } header: {
                        projectsHeader(isListSectionHeader: projectsHeaderIsListSectionHeader)
                    }
                }
            }
            .listStyle(.sidebar)
            .coordinateSpace(name: Self.sidebarDragCoordinateSpaceName)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SidebarDragGeometryPreferenceKey.self,
                        value: [.viewport: [proxy.frame(in: .named(Self.sidebarDragCoordinateSpaceName))]]
                    )
                }
            }
            .overlay { sidebarDragOverlay }
            .focusable()
            .focused($isKeyboardFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, Self.backspaceKey], action: handleSidebarKeyPress)
        }
        .onPreferenceChange(SidebarDragGeometryPreferenceKey.self) { frames in
            scheduleSidebarDragGeometryRefresh(with: frames)
        }
        .onAppear {
            do {
                try viewModel.ensureSidebarOrderingInitialized()
            } catch {
                viewModel.presentSidebarError(error)
            }
            syncExpansionWithSelection(appState.selectedSidebarItem)
        }
        .onDisappear {
            cancelSidebarDragForTeardown()
        }
        .onChange(of: visibleDragItems) { _, visibleItems in
            cancelSidebarDragIfSourceIsMissing(visibleItems: visibleItems)
        }
        .onChange(of: editingThreadID) { _, editingThreadID in
            if editingThreadID != nil {
                cancelSidebarDragForTeardown()
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .threadDraftProjectChanged), perform: handleDraftProjectChanged)
        .onReceive(NotificationCenter.default.publisher(for: .threadDraftMaterialized), perform: handleDraftMaterialized)
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
        topSpacing: CGFloat,
        dragConfiguration: SidebarRowDragConfiguration? = nil,
        opacity: Double = 1
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
            suppressHoverAffordances: isSidebarDragInteractionInFlight,
            dragConfiguration: dragConfiguration,
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
        .opacity(opacity)
        .animation(sidebarDragAnimation, value: opacity)
        .appSelectableRow(
            isSelected: isSelected,
            identity: thread.persistentModelID,
            selectionBackgroundTopInset: topSpacing,
            selectionBackgroundOpacity: opacity,
            showsHoverBackground: !isSidebarDragInteractionInFlight,
            suppressesPressFeedback: isSidebarDragInteractionInFlight,
            suppressesAction: isSidebarDragInteractionInFlight,
            action: { activateThread(thread) }
        )
        .contextMenu {
            sidebarThreadContextMenu(for: thread)
        }
    }

    @ViewBuilder
    func sidebarThreadContextMenu(for thread: AgentThread) -> some View {
        ForEach(
            sidebarThreadContextMenuItems(
                isPinned: thread.isPinned,
                canRename: editingThreadID == nil,
                allowsPinning: thread.project?.isPinned != true
            ),
            id: \.self
        ) { item in
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
