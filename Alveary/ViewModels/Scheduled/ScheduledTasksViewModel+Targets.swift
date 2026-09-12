import Foundation
import SwiftData

extension ScheduledTasksViewModel {
    func observeChanges() {
        let notifications = notificationCenter.notifications(named: .scheduledTasksChanged)
        changeObservationTask = Task { @MainActor [weak self] in
            for await notification in notifications {
                guard !Task.isCancelled else { return }
                if notification.userInfo?[ScheduledTasksChangeUserInfoKey.schedulerClaimResolved] as? Bool == true,
                   let definitionID = notification.userInfo?[ScheduledTasksChangeUserInfoKey.definitionID] as? String {
                    self?.pendingRunNowDefinitionIDs.remove(definitionID)
                    if let errorMessage = notification.userInfo?[ScheduledTasksChangeUserInfoKey.schedulerClaimErrorMessage] as? String {
                        self?.errorMessage = errorMessage
                    }
                }
                self?.reload()
            }
        }

        let proposalNotifications = notificationCenter.notifications(named: .scheduledTaskProposalsChanged)
        proposalObservationTask = Task { @MainActor [weak self] in
            for await _ in proposalNotifications {
                guard !Task.isCancelled else { return }
                self?.refreshActiveProposalPaneIfNeeded()
            }
        }

        threadObservationTask = reloadObservationTask(named: .threadPresentationChanged)

        // Deleting or archiving a reuse schedule's own thread converts no definition —
        // `ScheduledTaskTargetDetachment` filters to `.existingThread`, so `.scheduledTasksChanged`
        // never fires — yet the card summary names that thread and the editor's thread picker
        // offers it. The lifecycle notification is the only signal those reads have.
        threadLifecycleObservationTask = reloadObservationTask(named: .threadLifecycleChanged)

        // Sections have no other route into an open editor: the sidebar reads them through its
        // own `@Query`, so a section created mid-session — including by the windowless
        // `create_section` host tool — reaches the Section picker only through this.
        sectionObservationTask = reloadObservationTask(named: .sidebarSectionsChanged)
        // Refresh available defaults without replacing an editor's already captured workspace.
        workspaceObservationTask = reloadObservationTask(named: .workspaceConfigurationChanged)
    }

    /// One subscription that answers every posting of `name` with a full `reload()`.
    private func reloadObservationTask(named name: Notification.Name) -> Task<Void, Never> {
        let notifications = notificationCenter.notifications(named: name)
        return Task { @MainActor [weak self] in
            for await _ in notifications {
                guard !Task.isCancelled else { return }
                self?.reload()
            }
        }
    }

    func makeDefinitionEdit(
        from draft: ScheduledTaskEditorDraft,
        preservesTrustedGrantSnapshot: Bool
    ) throws -> ScheduledTaskDefinitionEdit {
        // The authoritative gate on repairing an unrecognized destination; the editor's disabled
        // submit button is only the affordance. Without it, saving any unrelated field would
        // silently commit the fallback `makeEditDraft` seeded.
        guard !draft.hasUnresolvedDestination else {
            throw ScheduledTasksViewModelError.destinationNotRecognized
        }
        guard !draft.isResolvingFolders else { throw ScheduledTasksViewModelError.foldersStillResolving }
        let text = try validatedText(in: draft)
        let destination = try resolvedDestination(in: draft)
        let threadSection = try resolvedThreadSection(in: draft)
        let options = modelOptions(for: draft.providerID)
        let storedModel = AgentModelOptionSelection.storedModelValue(
            in: options,
            matching: draft.modelSelection
        )
        let normalizedModel = storedModel == AppSettings.defaultModelValue ? nil : storedModel
        let roots = draft.destination == .existingThread ? []
            : draft.resolvedGrantPaths(preservingAllPaths: preservesTrustedGrantSnapshot)
        let source = draft.destination != .existingThread && draft.workspaceKind == .project
            ? draft.workspaceSnapshot?.primarySource ?? destination.project?.orderedFolders.first { $0.path == draft.projectPath }?.snapshot : nil
        let workspace = WorkspaceSnapshot(
            primarySource: source,
            grants: roots.map { path in
                draft.workspaceSnapshot?.grants.first { $0.path == path }
                    ?? destination.project?.orderedFolders.first { $0.path == path }?.snapshot
                    ?? SourceFolderSnapshot(path: path)
            },
            // Text-only edits retain legacy native roots and the existing reuse link.
            rootsExplicitlyManaged: !draft.isEditing || draft.workspaceSnapshot?.rootsExplicitlyManaged != false
                || source != draft.workspaceSnapshot?.primarySource || roots != draft.workspaceSnapshot?.grants.map(\.path)
        )
        return ScheduledTaskDefinitionEdit(
            title: text.title,
            prompt: text.prompt,
            destination: draft.destination,
            recurrence: draft.recurrence,
            timeZoneIdentifier: currentTimeZone().identifier,
            providerID: draft.providerID,
            model: normalizedModel,
            effort: AgentModelOptionSelection.normalizedEffort(
                draft.effort,
                options: options,
                selectedModel: normalizedModel
            ),
            permissionMode: draft.permissionMode,
            workspaceKind: draft.destination == .existingThread ? .privateWorkspace : draft.workspaceKind,
            workspaceStrategy: draft.workspaceStrategy,
            grantedRoots: roots,
            project: destination.project,
            targetThread: destination.thread,
            threadSection: threadSection,
            workspaceSnapshot: workspace
        )
    }

    /// Resolves the draft's section id against live rows, failing the save loudly — matching
    /// `projectNotFound` — instead of silently landing future threads in `Tasks`. `nil` when the
    /// destination or workspace cannot carry a section, so a hidden stale pick never round-trips.
    private func resolvedThreadSection(in draft: ScheduledTaskEditorDraft) throws -> SidebarSection? {
        guard draft.destination != .existingThread,
              draft.projectID == nil, draft.workspaceSnapshot != nil || draft.projectPath == nil,
              let sectionID = draft.sectionID else {
            return nil
        }
        guard let section = modelContext.resolveSidebarSection(id: sectionID),
              section.kind == .custom else {
            throw ScheduledTasksViewModelError.sectionNotFound
        }
        return section
    }

    func resolveProject(path: String) -> Project? {
        modelContext.resolveProject(path: path)
    }

    /// Custom sections in persisted sidebar order, for the editor's Section picker; `Tasks` is
    /// the picker's literal nil option, and `Pinned`/`Projects` are excluded because pinning and
    /// a Project placement are what put a thread in either. Deliberately the pure read path
    /// rather than `SidebarSectionService.orderedSections()`, whose builtin seeding *saves* —
    /// `reload()` also runs from `saveDefinition`'s failure path right after a `rollback()`, and
    /// a read that commits unrelated pending work there would resurrect what the rollback undid.
    func makeSectionOptions() throws -> [ScheduledTaskSectionOption] {
        SidebarSectionNormalization
            .orderedSections(try SidebarSectionNormalization.allSections(in: modelContext))
            .filter { $0.kind == .custom }
            .map { ScheduledTaskSectionOption(id: $0.id, name: $0.name) }
    }

    /// The thread a `.reusedThread` schedule already posts into, or `nil` while the next run
    /// still has to mint one. Gated on the same health `ScheduledTaskSchedulerEngine.reusedTarget`
    /// claims through, so the card and editor cannot name a thread the schedule has already
    /// decided to replace.
    func reusedThreadLink(for definition: ScheduledTask) -> ScheduledTaskReusedThreadLink? {
        guard definition.decodedDestination == .reusedThread,
              let thread = definition.reusedThread,
              thread.isHealthyReusedScheduledTaskTarget,
              let conversationID = thread.soleMainConversation?.id else {
            return nil
        }
        return ScheduledTaskReusedThreadLink(conversationID: conversationID, name: thread.displayName())
    }

    /// Selects the reuse thread the editor names. Sidebar selection is app-wide, so the request
    /// travels as a notification the root owns — see `ContentView+ThreadOpenRequests.swift`.
    func requestReusedThreadOpen(conversationID: String) {
        notificationCenter.post(
            name: .threadOpenRequested,
            object: nil,
            userInfo: [
                ThreadOpenRequestNotificationKey.request: ThreadOpenRequest(conversationID: conversationID)
            ]
        )
    }

    func makeExistingThreadOptions() throws -> [ScheduledTaskThreadOption] {
        let threads = SidebarPinnedItemOrdering.sorted(
            try modelContext.fetch(FetchDescriptor<AgentThread>())
                .filter(\.isEligibleScheduledTaskTarget)
                .map(SidebarPinnedItem.init(thread:))
        )
            .compactMap { item -> AgentThread? in
                guard case .thread(let thread) = item.kind else { return nil }
                return thread
            }
            .compactMap(targetThreadAndMainConversation)
        let nameCounts = Dictionary(grouping: threads, by: { $0.0.displayName() }).mapValues(\.count)
        let labeledThreads = threads.map { thread, conversation in
            (
                thread: thread,
                conversation: conversation,
                label: targetThreadLabel(
                    thread,
                    hasDuplicateName: nameCounts[thread.displayName(), default: 0] > 1
                )
            )
        }
        let labelCounts = Dictionary(grouping: labeledThreads, by: { $0.label }).mapValues(\.count)
        return labeledThreads.map { item in
            let label: String
            if labelCounts[item.label, default: 0] > 1 {
                let duplicateConversationIDs = labeledThreads
                    .filter { $0.label == item.label }
                    .map { $0.conversation.id }
                let disambiguator = stableTargetThreadDisambiguator(
                    for: item.conversation.id,
                    among: duplicateConversationIDs
                )
                label = "\(item.label) · \(disambiguator)"
            } else {
                label = item.label
            }
            return ScheduledTaskThreadOption(
                conversationID: item.conversation.id,
                label: label
            )
        }
    }
}

private extension ScheduledTasksViewModel {
    typealias ValidatedText = (title: String, prompt: String)
    typealias ResolvedDestination = (project: Project?, thread: AgentThread?)

    func validatedText(in draft: ScheduledTaskEditorDraft) throws -> ValidatedText {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ScheduledTasksViewModelError.titleRequired }
        let prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw ScheduledTasksViewModelError.promptRequired }
        return (title, prompt)
    }

    func resolvedDestination(in draft: ScheduledTaskEditorDraft) throws -> ResolvedDestination {
        if draft.destination == .existingThread {
            guard let conversationID = draft.targetConversationID else {
                throw ScheduledTasksViewModelError.existingThreadRequired
            }
            guard let conversation = modelContext.resolveConversation(conversationID: conversationID),
                  conversation.isMain,
                  let thread = conversation.thread,
                  thread.isEligibleScheduledTaskTarget,
                  thread.soleMainConversation != nil else {
                throw ScheduledTasksViewModelError.existingThreadUnavailable
            }
            return (nil, thread)
        }
        if let id = draft.projectID {
            guard let project = modelContext.resolveProject(projectID: id) else { throw ScheduledTasksViewModelError.projectNotFound }
            return (project, nil)
        }
        // An edited detached definition retains its execution source independently of placement.
        if draft.workspaceSnapshot != nil { return (nil, nil) }
        guard draft.workspaceKind == .project else { return (nil, nil) }
        guard let projectPath = draft.projectPath else { throw ScheduledTasksViewModelError.projectRequired }
        guard let project = resolveProject(path: projectPath) else { throw ScheduledTasksViewModelError.projectNotFound }
        return (project, nil)
    }

    func targetThreadAndMainConversation(_ thread: AgentThread) -> (AgentThread, Conversation)? {
        guard let main = thread.soleMainConversation else { return nil }
        return (thread, main)
    }

    func targetThreadLabel(_ thread: AgentThread, hasDuplicateName: Bool) -> String {
        guard hasDuplicateName else { return thread.displayName() }
        switch thread.effectiveMode {
        case .project:
            let location = thread.useWorktree ? "Worktree" : "Local"
            return "\(thread.displayName()) — \(thread.project?.name ?? "Project") · \(location)"
        case .task:
            return "\(thread.displayName()) — Tasks"
        }
    }

    func stableTargetThreadDisambiguator(
        for conversationID: String,
        among conversationIDs: [String]
    ) -> String {
        var prefixLength = min(8, conversationID.count)
        while prefixLength < conversationID.count {
            let candidate = String(conversationID.prefix(prefixLength))
            guard conversationIDs.contains(where: {
                $0 != conversationID && $0.hasPrefix(candidate)
            }) else {
                break
            }
            prefixLength += 1
        }
        return String(conversationID.prefix(prefixLength))
    }
}
