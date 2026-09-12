import Foundation
import SwiftData

extension SidebarViewModel {
    func createThread(project: Project, provider: String, permissionMode: String) async throws -> AgentThread {
        let defaultModel = settingsService.current.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let threadModel = defaultModel != AppSettings.defaultModelValue && !defaultModel.isEmpty ? defaultModel : nil
        return try await createThread(
            project: project,
            provider: provider,
            permissionMode: permissionMode,
            threadModel: threadModel,
            effort: seedEffortLevel()
        )
    }

    func createThread(project: Project) async throws -> AgentThread {
        let resolution = await resolvedThreadDefaults()
        guard let providerID = resolution.providerID else {
            throw SidebarViewModelError.noReadyThreadDefaultProvider
        }
        return try await createThread(
            project: project,
            provider: providerID,
            permissionMode: resolution.permissionMode,
            threadModel: resolution.storedThreadModel,
            effort: resolution.effort
        )
    }

    func openDraftThread(project: Project) async throws -> AgentThread {
        guard let project = modelContext.resolveProject(id: project.persistentModelID) else {
            throw SidebarViewModelError.projectMissing
        }
        return try await openDraft(destination: .project(id: project.id))
    }

    func openTaskDraft() async throws -> AgentThread {
        try await openDraft(destination: .tasks)
    }

    func openDraft(destination: ThreadDraftDestination) async throws -> AgentThread {
        pendingDraftDestination = destination
        if let draft = resolveCachedOrPersistedDraftThread() {
            return try moveDraftThread(draft, to: destination)
        }
        let task = activeDraftCreationTask()
        let taskID = draftCreationTaskID
        defer {
            if draftCreationTaskID == taskID {
                draftCreationTask = nil
                draftCreationTaskID = nil
            }
        }
        let threadID = try await task.value
        guard let draft = modelContext.resolveThread(id: threadID), draft.isDraft else {
            throw SidebarViewModelError.threadMissing
        }
        // Concurrent open requests share one insert; the latest destination wins after discovery returns.
        return try moveDraftThread(draft, to: pendingDraftDestination ?? destination)
    }

    func moveDraftThread(id: PersistentIdentifier, to destination: ThreadDraftDestination) throws -> AgentThread {
        guard let draft = modelContext.resolveThread(id: id), draft.isDraft else {
            throw SidebarViewModelError.threadMissing
        }
        return try moveDraftThread(draft, to: destination)
    }

    func noteDraftMaterialized(mode _: AgentThreadMode) {
        cachedDraftThreadID = nil
        pendingDraftDestination = nil
        threadOrderVersion += 1
    }

    func invalidateDraftThreadIfNeeded(threadID: PersistentIdentifier) {
        invalidateDraftThreadIfNeeded(threadIDs: [threadID])
    }

    func invalidateDraftThreadIfNeeded(threadIDs: Set<PersistentIdentifier>) {
        guard let cachedDraftThreadID, threadIDs.contains(cachedDraftThreadID) else { return }
        self.cachedDraftThreadID = nil
        pendingDraftDestination = nil
    }
}

private extension SidebarViewModel {
    func activeDraftCreationTask() -> Task<PersistentIdentifier, Error> {
        if let draftCreationTask { return draftCreationTask }
        draftCreationTaskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { throw SidebarViewModelError.threadMissing }
            let resolution = await resolvedThreadDefaults()
            guard let providerID = resolution.providerID else {
                throw SidebarViewModelError.noReadyThreadDefaultProvider
            }
            let draft: AgentThread
            switch pendingDraftDestination ?? .tasks {
            case .project(let projectID):
                guard let project = modelContext.resolveProject(projectID: projectID) else {
                    throw SidebarViewModelError.projectMissing
                }
                draft = try threadLifecycle.insertProjectThread(
                    project: project,
                    seed: ProjectThreadSeed(
                        provider: providerID, permissionMode: resolution.permissionMode,
                        model: resolution.storedThreadModel, effort: resolution.effort, isDraft: true,
                        workspaceSnapshot: project.workspaceSnapshot()
                    )
                )
            case .tasks, .section:
                let placement: TaskThreadSidebarPlacement
                if case .section(let id) = pendingDraftDestination { placement = .section(id: id) } else { placement = .tasks }
                draft = try threadLifecycle.insertTaskThread(seed: TaskThreadSeed(
                    provider: providerID, permissionMode: resolution.permissionMode,
                    model: resolution.storedThreadModel, effort: resolution.effort, isDraft: true, placement: placement
                ))
            }
            cachedDraftThreadID = draft.persistentModelID
            return draft.persistentModelID
        }
        draftCreationTask = task
        return task
    }

    func createThread(
        project: Project,
        provider: String,
        permissionMode: String,
        threadModel: String?,
        effort: String
    ) async throws -> AgentThread {
        let dbProject = try requireProject(project)
        return try threadLifecycle.insertProjectThread(
            project: dbProject,
            seed: ProjectThreadSeed(
                provider: provider,
                permissionMode: permissionMode,
                model: threadModel,
                effort: effort,
                isDraft: false
            )
        )
    }

    func resolveCachedOrPersistedDraftThread() -> AgentThread? {
        if let cachedDraftThreadID, let draft = modelContext.resolveThread(id: cachedDraftThreadID), draft.isDraft {
            return draft
        }
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { $0.isDraft == true }, sortBy: [SortDescriptor(\AgentThread.modifiedAt, order: .reverse)]
        )
        let draft = try? modelContext.fetch(descriptor).first
        cachedDraftThreadID = draft?.persistentModelID
        return draft
    }

    func resolvedThreadDefaults() async -> ThreadDefaultResolution {
        if let providerDiscovery {
            return await ThreadDefaultResolver.resolve(
                settings: settingsService.current,
                providerDiscovery: providerDiscovery
            )
        }
        return ThreadDefaultResolver.resolve(
            settings: settingsService.current,
            providerOrdering: AppSettings.supportedProviderIDs,
            providerStatuses: [:],
            allowStaticFallback: true
        )
    }

    func seedEffortLevel() -> String {
        AppSettings.normalizedEffortLevel(settingsService.current.effort)
    }
}
