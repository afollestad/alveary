import AppKit
import SwiftData
import SwiftUI

enum SidebarProjectListMetrics {
    static let subsequentProjectTopSpacing: CGFloat = 4

    // Native list-section headers add more pre-header space than inline section rows.
    static let listHeaderDividerYOffset: CGFloat = -6
    static let listHeaderTopPaddingCorrection: CGFloat = 3.5
    // The Projects header's top edge is the empty-Pinned drop boundary, so keep its divider inset measurable.
    static let listHeaderDragTopInsetExclusion: CGFloat = 0

    // SwiftUI `List` section headers omit the real project row's trailing action column inset.
    @MainActor static var listSectionHeaderTrailingCorrection: CGFloat {
        SidebarSectionHeaderRow.actionButtonCenterTrailingInset
    }
}

private let archivedThreadProbeDescriptor: FetchDescriptor<AgentThread> = {
    var descriptor = FetchDescriptor<AgentThread>(
        predicate: #Predicate { $0.archivedAt != nil && $0.isDraft == false }
    )
    descriptor.fetchLimit = 1
    return descriptor
}()

struct SidebarView: View {
    let viewModel: SidebarViewModel
    @Bindable var appState: AppState
    let voiceInputLifecycleController: VoiceInputLifecycleController?

    @Environment(\.modelContext) var uiModelContext
    @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
    @Query var queriedProjects: [Project]
    // One observation-backed query feeds the whole render pass. Drafts are included so
    // draft-driven refreshes stay tracked; `SidebarRenderSnapshot` filters them out.
    @Query(filter: #Predicate<AgentThread> { $0.archivedAt == nil })
    var queriedUnarchivedThreads: [AgentThread]
    // Existence probe for the conditional Archived row. Bounded to one row because the
    // Archived screen owns the real fetch; this only decides whether to render the row.
    @Query(archivedThreadProbeDescriptor)
    var queriedArchivedThreadProbe: [AgentThread]
    @State var expandedProjects: Set<String> = []
    @State var editingThreadID: PersistentIdentifier?
    @State var pendingArchiveThread: AgentThread?
    @State var pendingDeleteThread: AgentThread?
    @State var pendingDeleteProject: Project?
    @State var pendingTaskProjectAccess: SidebarTaskProjectAccessRequest?
    @State var sidebarDragInteractionState = SidebarDragInteractionState.idle
    @State var sidebarDragPointerRelay = SidebarDragPointerRelay()
    @State var sidebarDropCandidate: SidebarDropCandidate?
    @State var sidebarDragGeometryFrames: [SidebarDragGeometryRole: [CGRect]] = [:]
    @State var sidebarDragGeometryRefreshRevision: UInt64 = 0
    @State var sidebarDragGeometryMissToken: UUID?
    @FocusState var isKeyboardFocused: Bool
    @FocusedValue(\.chatComposerFocus) var chatComposerFocus

    init(
        viewModel: SidebarViewModel,
        appState: AppState,
        voiceInputLifecycleController: VoiceInputLifecycleController? = nil
    ) {
        self.viewModel = viewModel
        self.appState = appState
        self.voiceInputLifecycleController = voiceInputLifecycleController
    }

    /// Ordered projects for action paths that run outside a render pass.
    /// Render code must use `SidebarRenderContext` instead.
    var projects: [Project] {
        viewModel.orderedProjects(from: queriedProjects)
    }

    var body: some View {
        let statusVersion = viewModel.statusVersion
        let threadOrderVersion = viewModel.threadOrderVersion
        let context = makeRenderContext()
        let pinnedItems = context.pinnedItems
        let regularProjects = context.regularProjects
        let activeTaskThreads = context.activeTaskThreads
        let threadOrderAnimation = context.threadOrderAnimation
        // Project-nested Tasks are sources too, so their items must survive unrelated set churn.
        let visibleDragItems = Set(
            context.dragLogicalOrder.pinnedItems
                + context.dragLogicalOrder.regularProjects
                + context.activeTaskThreads.map { SidebarDragItem.unpinnedTask($0.persistentModelID) }
                + context.dragLogicalOrder.projectIDByTaskID.keys.map(SidebarDragItem.unpinnedTask)
        )
        let projectsHeaderIsListSectionHeader = pinnedItems.isEmpty

        let listContent = VStack(spacing: 0) {
            if let sidebarError = viewModel.sidebarError {
                InlineBanner(message: sidebarError, severity: .error, autoDismissAfter: nil, onDismiss: viewModel.dismissSidebarError)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            List {
                Section {
                    topLevelRows(context: context)

                    if !pinnedItems.isEmpty {
                        pinnedHeader

                        ForEach(pinnedItems) { item in
                            let topSpacing: CGFloat = item.id == pinnedItems.first?.id
                                ? 0
                                : SidebarRowMetrics.interThreadRowSpacing
                            switch item.kind {
                            case .project(let project):
                                projectRow(project, topSpacing: topSpacing, dropSection: .pinned, context: context)
                            case .thread(let thread):
                                sidebarThreadRow(
                                    thread,
                                    layout: .topLevel,
                                    topSpacing: topSpacing,
                                    dragConfiguration: pinnedItemDragConfiguration(
                                        for: thread,
                                        logicalOrder: context.dragLogicalOrder
                                    ),
                                    opacity: activeSidebarDragItem == item.dragItem ? 0.48 : 1
                                )
                                .sidebarDragGeometry(pinnedItemDragGeometryRole(for: thread))
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
                            showsNoProjectsPlaceholder: context.orderedProjects.isEmpty,
                            dropSection: .projects,
                            context: context
                        )

                        tasksHeader
                        taskRows(
                            activeTaskThreads,
                            showsNoTasksPlaceholder: shouldShowNoTasksPlaceholder(
                                activeTaskThreads: activeTaskThreads,
                                hasAnyActiveTaskThreads: context.snapshot.hasAnyActiveTaskThreads
                            ),
                            context: context
                        )
                    }
                }

                if pinnedItems.isEmpty {
                    Section {
                        projectRows(
                            context.orderedProjects,
                            showsNoProjectsPlaceholder: context.orderedProjects.isEmpty,
                            dropSection: .projects,
                            context: context
                        )

                        tasksHeader
                        taskRows(
                            activeTaskThreads,
                            showsNoTasksPlaceholder: shouldShowNoTasksPlaceholder(
                                activeTaskThreads: activeTaskThreads,
                                hasAnyActiveTaskThreads: context.snapshot.hasAnyActiveTaskThreads
                            ),
                            context: context
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
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, Self.backspaceKey]) { keyPress in
                handleSidebarKeyPress(keyPress, context: context)
            }
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

        return sidebarPresentationDialogs(listContent)
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
        let cleanupDisabledReason = viewModel.scheduledTaskAttachmentReason(for: thread)
        let leadingPadding: CGFloat = layout == .topLevel ? SidebarSectionHeaderRow.contentLeadingPadding : 14

        return SidebarThreadRow(
            thread: thread,
            status: viewModel.threadStatus(for: thread),
            isSelected: isSelected,
            layout: layout,
            editingThreadID: $editingThreadID,
            cleanupAction: cleanupAction,
            cleanupDisabledReason: cleanupDisabledReason,
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
        let scheduledTaskAttachmentReason = viewModel.scheduledTaskAttachmentReason(for: thread)

        ForEach(
            sidebarThreadContextMenuItems(
                isPinned: thread.isPinned,
                canRename: editingThreadID == nil,
                allowsPinning: thread.effectiveMode == .task || thread.project?.isPinned != true,
                allowsForking: thread.effectiveMode == .project
            ),
            id: \.self
        ) { item in
            let disabledReason = sidebarThreadContextMenuDisabledReason(
                for: item,
                scheduledTaskAttachmentReason: scheduledTaskAttachmentReason
            )
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
                SidebarThreadContextMenuActionButton("Unpin", disabledReason: disabledReason) {
                    setThreadPinned(thread, isPinned: false)
                }
            case .rename:
                Button("Rename...") {
                    editingThreadID = thread.persistentModelID
                }
            case .archive:
                SidebarThreadContextMenuActionButton("Archive...", disabledReason: disabledReason) {
                    requestArchive(thread)
                }
            case .delete:
                SidebarThreadContextMenuActionButton("Delete...", role: .destructive, disabledReason: disabledReason) {
                    requestDelete(thread)
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

@MainActor
func startNewTaskFlowFromSidebar(appState: AppState) {
    appState.startNewThreadFlow(mode: .task)
}

func shouldShowNoThreadsPlaceholder(
    activeProjectThreads: [AgentThread],
    hasAnyActiveThreads: Bool
) -> Bool {
    activeProjectThreads.isEmpty && !hasAnyActiveThreads
}
