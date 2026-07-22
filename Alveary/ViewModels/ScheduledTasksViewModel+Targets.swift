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

        let threadNotifications = notificationCenter.notifications(named: .threadPresentationChanged)
        threadObservationTask = Task { @MainActor [weak self] in
            for await _ in threadNotifications {
                guard !Task.isCancelled else { return }
                self?.reload()
            }
        }
    }

    func makeDefinitionEdit(
        from draft: ScheduledTaskEditorDraft,
        preservesTrustedGrantSnapshot: Bool
    ) throws -> ScheduledTaskDefinitionEdit {
        let text = try validatedText(in: draft)
        let destination = try resolvedDestination(in: draft)
        let options = modelOptions(for: draft.providerID)
        let storedModel = AgentModelOptionSelection.storedModelValue(
            in: options,
            matching: draft.modelSelection
        )
        let normalizedModel = storedModel == AppSettings.defaultModelValue ? nil : storedModel
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
            workspaceKind: draft.workspaceKind,
            workspaceStrategy: draft.workspaceStrategy,
            grantedRoots: preservesTrustedGrantSnapshot
                ? draft.grantedRoots
                : ScheduledTask.normalizedUniquePaths(draft.grantedRoots),
            project: destination.project,
            targetThread: destination.thread
        )
    }

    func resolveProject(path: String) -> Project? {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == path
        })
        return try? modelContext.fetch(descriptor).first
    }

    func makePinnedThreadOptions() throws -> [ScheduledTaskThreadOption] {
        let threads = SidebarPinnedItemOrdering.sorted(
            try modelContext.fetch(FetchDescriptor<AgentThread>())
                .filter(isEligibleExistingTarget)
                .map(SidebarPinnedItem.init(thread:))
        )
            .compactMap { item -> AgentThread? in
                guard case .thread(let thread) = item.kind else { return nil }
                return thread
            }
            .compactMap(pinnedThreadAndMainConversation)
        let nameCounts = Dictionary(grouping: threads, by: { $0.0.displayName() }).mapValues(\.count)
        let labeledThreads = threads.map { thread, conversation in
            (
                thread: thread,
                conversation: conversation,
                label: pinnedThreadLabel(
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
                let disambiguator = stablePinnedThreadDisambiguator(
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

    func isEligibleExistingTarget(_ thread: AgentThread) -> Bool {
        guard thread.isPinned,
              thread.archivedAt == nil,
              !thread.isDraft,
              !thread.isForkBootstrapPending,
              !thread.hasPendingScheduledTaskWorktreeCleanup else {
            return false
        }
        switch thread.effectiveMode {
        case .project:
            return thread.project != nil && thread.project?.isPinned != true
        case .task:
            return true
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
                  isEligibleExistingTarget(thread),
                  thread.conversations.filter(\.isMain).count == 1 else {
                throw ScheduledTasksViewModelError.existingThreadUnavailable
            }
            return (nil, thread)
        }
        guard draft.workspaceKind == .project else { return (nil, nil) }
        guard let projectPath = draft.projectPath else { throw ScheduledTasksViewModelError.projectRequired }
        guard let project = resolveProject(path: projectPath) else { throw ScheduledTasksViewModelError.projectNotFound }
        return (project, nil)
    }

    func pinnedThreadAndMainConversation(_ thread: AgentThread) -> (AgentThread, Conversation)? {
        let mainConversations = thread.conversations.filter(\.isMain)
        guard mainConversations.count == 1, let main = mainConversations.first else { return nil }
        return (thread, main)
    }

    func pinnedThreadLabel(_ thread: AgentThread, hasDuplicateName: Bool) -> String {
        guard hasDuplicateName else { return thread.displayName() }
        switch thread.effectiveMode {
        case .project:
            let location = thread.useWorktree ? "Worktree" : "Local"
            return "\(thread.displayName()) — \(thread.project?.name ?? "Project") · \(location)"
        case .task:
            return "\(thread.displayName()) — Tasks"
        }
    }

    func stablePinnedThreadDisambiguator(
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
