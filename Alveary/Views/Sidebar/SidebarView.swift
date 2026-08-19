import AppKit
import SwiftData
import SwiftUI

enum SidebarProjectListMetrics {
    static let subsequentProjectTopSpacing: CGFloat = 4

    /// A SwiftUI `List` section header insets 2pt less at the leading edge than a plain row does.
    /// Every section header is an ordinary row now, but the top-level rows' icon column and the
    /// section placeholders still line up with that same ink, so they all pull back together.
    static let plainRowLeadingCorrection: CGFloat = -2
}

private let archivedThreadProbeDescriptor: FetchDescriptor<AgentThread> = {
    var descriptor = FetchDescriptor<AgentThread>(
        predicate: #Predicate { $0.archivedAt != nil && $0.isDraft == false }
    )
    descriptor.fetchLimit = 1
    return descriptor
}()

/// Conversations feeding the sidebar's per-thread status fold: every conversation on an
/// unarchived thread, drafts included to match `queriedUnarchivedThreads`. Kept one relationship
/// hop deep per the `#Predicate` rules in `Alveary/Data/AGENTS.md`; internal (not `private`) so
/// `DeletedModelRenderSafetyTests` can execute it and catch a translation failure in a test
/// instead of on the render pass.
let sidebarStatusFoldConversationsPredicate = #Predicate<Conversation> {
    $0.thread?.archivedAt == nil
}

struct SidebarView: View, Equatable {
    let viewModel: SidebarViewModel
    // A plain `let`, not `@Bindable`: nothing here needs an `appState` binding, and `==` may
    // only read Sendable stored values — a wrapper's projected read is main-actor computed.
    let appState: AppState
    let voiceInputLifecycleController: VoiceInputLifecycleController?

    @Environment(\.modelContext) var uiModelContext
    @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
    // Waiting-dot sources the runtime cannot report. Optional because previews and snapshot
    // hosts mount the sidebar without the app root's environment.
    @Environment(UnresolvedApprovalRegistry.self) var unresolvedApprovalRegistry: UnresolvedApprovalRegistry?
    @Environment(ScheduledTaskProposalQueueCoordinator.self)
    var scheduledTaskProposalQueueCoordinator: ScheduledTaskProposalQueueCoordinator?
    @Environment(PullRequestReviewProposalCoordinator.self)
    var pullRequestReviewProposalCoordinator: PullRequestReviewProposalCoordinator?
    @Query var queriedProjects: [Project]
    // One observation-backed query feeds the whole render pass. Drafts are included so
    // draft-driven refreshes stay tracked; `SidebarRenderSnapshot` filters them out.
    @Query(filter: #Predicate<AgentThread> { $0.archivedAt == nil })
    var queriedUnarchivedThreads: [AgentThread]
    // Existence probe for the conditional Archived row. Bounded to one row because the
    // Archived screen owns the real fetch; this only decides whether to render the row.
    @Query(archivedThreadProbeDescriptor)
    var queriedArchivedThreadProbe: [AgentThread]
    // Section rows drive both order and membership, so the render pass has to observe them.
    // Sorting happens in `SidebarRenderSnapshot`, which applies the same tiebreaks normalization
    // does; an empty result renders the built-in fallback layout.
    @Query var queriedSidebarSections: [SidebarSection]
    // Feeds the status fold as `ConversationStatusSnapshot`s grouped per body pass in
    // `makeRenderContext()`, so no render path walks `thread.conversations` — that to-many can
    // hold stale entries that trap after a conversation delete. Observation-backed like the
    // thread query, so an `isUnread` flip repaints the row.
    @Query(filter: sidebarStatusFoldConversationsPredicate)
    var queriedStatusFoldConversations: [Conversation]
    @State var expandedProjects: Set<String> = []
    @State var collapsedSections: Set<SidebarCollapsibleSection> = []
    @State var editingThreadID: PersistentIdentifier?
    /// `SidebarSection.id` of the custom section header currently being renamed in place.
    @State var editingSectionID: String?
    /// Whether the pending new-section row is mounted at the bottom of the list.
    @State var isCreatingSection = false
    @State var pendingRemoveSection: SidebarPendingSectionRemoval?
    @State var pendingArchiveThread: SidebarPendingThreadCleanup?
    @State var pendingDeleteThread: SidebarPendingThreadCleanup?
    @State var pendingDeleteProject: SidebarPendingProjectRemoval?
    @State var pendingTaskProjectAccess: SidebarTaskProjectAccessRequest?
    @State var sidebarDragInteractionState = SidebarDragInteractionState.idle
    @State var sidebarDragPointerRelay = SidebarDragPointerRelay()
    @State var sidebarDropCandidate: SidebarDropCandidate?
    @State var sidebarDragGeometry = SidebarDragGeometryStore()
    /// The list's own bounds in the drag coordinate space, mirrored out of `sidebarDragGeometry`
    /// because `sidebarDragOverlay` reads it from `body` and the store deliberately publishes
    /// nothing. Unlike the row frames beside it in the store, this changes only when the list
    /// resizes, so observing it costs one rebuild per resize rather than one per layout pass.
    @State var sidebarDragViewportFrame: CGRect?
    @State var sidebarDragGeometryMissToken: UUID?
    /// The custom section whose secondary-click menu is open, with the frame its outline borders.
    ///
    /// The frame is captured when the menu opens rather than read from `sidebarDragGeometry` per
    /// body, which must never be observed from `body` at all. It cannot go stale in between:
    /// popping an `NSMenu` runs a nested event loop, so the list neither scrolls nor relayouts
    /// until the menu closes and this clears.
    @State var sidebarSectionSecondaryClickHighlight: SidebarSectionHighlight?
    @FocusState var isKeyboardFocused: Bool
    /// Handed in by `SidebarFocusBridge`, which owns the `@FocusedValue` declaration — declaring
    /// one here re-ran this whole body once per animation frame; the bridge's doc comment owns
    /// the mechanism. Do not add a `@FocusedValue` back to this view.
    let composerFocusRelay: SidebarComposerFocusRelay

    /// All four stored inputs are window-lifetime references, so identity is the whole
    /// comparison; every `@State`, `@FocusState`, and environment wrapper is SwiftUI-owned
    /// storage that survives a skipped body. `SidebarFocusBridge` relies on this through
    /// `.equatable()` — its parent re-runs once per animation frame of any presentation, and
    /// without the skip the sidebar rebuilt its whole snapshot on each of those frames.
    nonisolated static func == (lhs: SidebarView, rhs: SidebarView) -> Bool {
        lhs.viewModel === rhs.viewModel
            && lhs.appState === rhs.appState
            && lhs.voiceInputLifecycleController === rhs.voiceInputLifecycleController
            && lhs.composerFocusRelay === rhs.composerFocusRelay
    }

    /// `initialExpandedProjects` seeds expansion for previews and snapshots, which mount the
    /// sidebar without the interactions that expand a group. Selecting a project deliberately
    /// does not expand it (see `sidebarProjectPathToExpand`), so a fixture wanting an expanded
    /// group must say so. `initialCollapsedSections` is the same seed for section collapse, which
    /// no fixture can reach either.
    init(
        viewModel: SidebarViewModel,
        appState: AppState,
        voiceInputLifecycleController: VoiceInputLifecycleController? = nil,
        composerFocusRelay: SidebarComposerFocusRelay = SidebarComposerFocusRelay(),
        initialExpandedProjects: Set<String> = [],
        initialCollapsedSections: Set<SidebarCollapsibleSection> = [],
        initialEditingSectionID: String? = nil,
        initialIsCreatingSection: Bool = false
    ) {
        self.viewModel = viewModel
        self.appState = appState
        self.voiceInputLifecycleController = voiceInputLifecycleController
        self.composerFocusRelay = composerFocusRelay
        _expandedProjects = State(initialValue: initialExpandedProjects)
        _collapsedSections = State(initialValue: initialCollapsedSections)
        _editingSectionID = State(initialValue: initialEditingSectionID)
        _isCreatingSection = State(initialValue: initialIsCreatingSection)
    }

    /// True while any inline text field owns the sidebar: a thread rename, a section rename, or
    /// the pending new-section row. Every guard that used to read `editingThreadID == nil` reads
    /// this instead, so a section edit suppresses drags, key presses, and rename entry points
    /// exactly as a thread rename does.
    var isSidebarInlineEditingActive: Bool {
        editingThreadID != nil || editingSectionID != nil || isCreatingSection
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
        let threadOrderAnimation = context.threadOrderAnimation
        // Project-nested Tasks and Project-mode children are sources too, so their items must
        // survive unrelated set churn.
        let visibleDragItems = Set(
            context.dragLogicalOrder.pinnedItems
                + context.dragLogicalOrder.regularProjects
                + context.activeTaskThreads.map { SidebarDragItem.unpinnedTask($0.persistentModelID) }
                + context.dragLogicalOrder.projectIDByTaskID.keys.map(SidebarDragItem.unpinnedTask)
                + context.orderedProjects.flatMap { project in
                    context.activeThreads(for: project)
                        .filter { $0.effectiveMode == .project }
                        .map { SidebarDragItem.projectThread($0.persistentModelID) }
                }
                // A section removed mid-drag — by this window or another — cancels its own drag.
                + context.dragLogicalOrder.sections
        )
        let listContent = VStack(spacing: 0) {
            if let sidebarError = viewModel.sidebarError {
                InlineBanner(message: sidebarError, severity: .error, autoDismissAfter: nil, onDismiss: viewModel.dismissSidebarError)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            List {
                // One flat section: every visual section is an ordinary row group, so the
                // persisted section order alone decides what renders where.
                Section {
                    topLevelRows(context: context)

                    ForEach(context.sectionDescriptors) { descriptor in
                        sectionGroup(descriptor, context: context)
                    }

                    pendingNewSectionRow
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
            .overlay { sidebarSecondaryClickMenuTarget(context: context) }
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
        .onChange(of: isSidebarInlineEditingActive) { _, isEditing in
            if isEditing {
                cancelSidebarDragForTeardown()
            }
        }
        .onChange(of: context.showsPullRequests) { _, showsPullRequests in
            handlePullRequestsVisibilityChange(showsPullRequests: showsPullRequests)
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
        .onReceive(NotificationCenter.default.publisher(for: .threadLifecycleChanged), perform: handleThreadLifecycleChanged)
        .animation(threadOrderAnimation, value: threadOrderVersion)
        .animation(nil, value: statusVersion)

        return sidebarPresentationDialogs(listContent)
    }

    func sidebarThreadRow(
        _ thread: AgentThread,
        layout: SidebarThreadRowLayout,
        topSpacing: CGFloat,
        conversationStatuses: [ConversationStatusSnapshot],
        dragConfiguration: SidebarRowDragConfiguration? = nil,
        opacity: Double = 1
    ) -> some View {
        let isSelected = appState.selectedSidebarItem == .thread(thread)
        let cleanupAction = viewModel.defaultThreadCleanupAction
        let cleanupDisabledReason = viewModel.activeScheduledTaskRunReason(for: thread)
        let leadingPadding: CGFloat = layout == .topLevel ? SidebarSectionHeaderRow.contentLeadingPadding : 14
        // Snapshot here, where the render context's liveness filter guarantees a live row.
        // Neither the row nor the lazily-evaluated context menu may read the model itself;
        // `SidebarThreadRowPresentation` documents why.
        let presentation = SidebarThreadRowPresentation(thread: thread)

        return SidebarThreadRow(
            presentation: presentation,
            status: viewModel.threadStatus(
                threadID: thread.persistentModelID,
                isArchived: thread.archivedAt != nil,
                conversationStatuses: conversationStatuses
            ),
            isSelected: isSelected,
            layout: layout,
            editingThreadID: editingThreadID,
            onEditingThreadIDChange: { editingThreadID = $0 },
            cleanupAction: cleanupAction,
            cleanupDisabledReason: cleanupDisabledReason,
            suppressHoverAffordances: isSidebarDragInteractionInFlight,
            canBeginRename: !isSidebarInlineEditingActive,
            dragConfiguration: dragConfiguration,
            onCommitRename: { newName in
                renameThread(thread, to: newName)
            },
            onConfirmCleanup: { confirmThreadCleanup(thread, action: cleanupAction) }
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
            sidebarThreadContextMenu(
                for: thread,
                presentation: presentation,
                activeScheduledTaskRunReason: cleanupDisabledReason
            )
        }
    }

    private func confirmThreadCleanup(_ thread: AgentThread, action: ThreadCleanupAction) {
        Task {
            switch action {
            case .archive:
                await archive(thread)
            case .delete:
                await confirmDeleteThread(thread)
            }
        }
    }

    @ViewBuilder
    func sidebarThreadContextMenu(
        for thread: AgentThread,
        presentation: SidebarThreadRowPresentation,
        activeScheduledTaskRunReason: String?
    ) -> some View {
        ForEach(
            sidebarThreadContextMenuItems(
                isPinned: presentation.isPinned,
                canRename: !isSidebarInlineEditingActive,
                allowsPinning: presentation.allowsPinning,
                allowsForking: presentation.allowsForking
            ),
            id: \.self
        ) { item in
            let disabledReason = sidebarThreadContextMenuDisabledReason(
                for: item,
                activeScheduledTaskRunReason: activeScheduledTaskRunReason
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
        composerFocusRelay.handle?.release()
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
