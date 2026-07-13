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
        let requestedProjectID = project.persistentModelID
        guard let requestedProject = modelContext.resolveProject(id: requestedProjectID) else {
            throw SidebarViewModelError.projectMissing
        }
        let requestedProjectPath = requestedProject.path
        pendingDraftProjectPaths[.project] = requestedProjectPath

        if let draft = resolveCachedOrPersistedDraftThread(mode: .project) {
            return try moveDraftThread(draft, toProjectPath: requestedProjectPath)
        }

        let task = activeDraftCreationTask(mode: .project, requestedProjectPath: requestedProjectPath)

        let taskID = draftCreationTaskIDs[.project]
        defer {
            if draftCreationTaskIDs[.project] == taskID {
                draftCreationTasks[.project] = nil
                draftCreationTaskIDs[.project] = nil
            }
        }

        let threadID = try await task.value
        guard let draft = modelContext.resolveThread(id: threadID),
              draft.isDraft,
              draft.mode == .project else {
            throw SidebarViewModelError.threadMissing
        }
        let destinationPath = pendingDraftProjectPaths[.project] ?? requestedProjectPath
        return try moveDraftThread(draft, toProjectPath: destinationPath)
    }

    func openTaskDraft() async throws -> AgentThread {
        if let draft = resolveCachedOrPersistedDraftThread(mode: .task) {
            return draft
        }

        let task = activeDraftCreationTask(mode: .task, requestedProjectPath: nil)
        let taskID = draftCreationTaskIDs[.task]
        defer {
            if draftCreationTaskIDs[.task] == taskID {
                draftCreationTasks[.task] = nil
                draftCreationTaskIDs[.task] = nil
            }
        }

        let threadID = try await task.value
        guard let draft = modelContext.resolveThread(id: threadID),
              draft.isDraft,
              draft.mode == .task else {
            throw SidebarViewModelError.threadMissing
        }
        return draft
    }

    func moveDraftThread(id: PersistentIdentifier, toProjectPath projectPath: String) throws -> AgentThread {
        guard let draft = modelContext.resolveThread(id: id),
              draft.isDraft,
              draft.mode == .project else {
            throw SidebarViewModelError.threadMissing
        }
        return try moveDraftThread(draft, toProjectPath: projectPath)
    }

    func noteDraftMaterialized(mode: AgentThreadMode) {
        cachedDraftThreadIDs[mode] = nil
        pendingDraftProjectPaths[mode] = nil
        threadOrderVersion += 1
    }

    func invalidateDraftThreadIfNeeded(threadID: PersistentIdentifier) {
        for mode in AgentThreadMode.allCases where cachedDraftThreadIDs[mode] == threadID {
            cachedDraftThreadIDs[mode] = nil
            pendingDraftProjectPaths[mode] = nil
        }
    }

    func invalidateDraftThreadIfNeeded(threadIDs: Set<PersistentIdentifier>) {
        for mode in AgentThreadMode.allCases {
            guard let cachedID = cachedDraftThreadIDs[mode], threadIDs.contains(cachedID) else {
                continue
            }
            cachedDraftThreadIDs[mode] = nil
            pendingDraftProjectPaths[mode] = nil
        }
    }
}

private extension SidebarViewModel {
    func activeDraftCreationTask(
        mode: AgentThreadMode,
        requestedProjectPath: String?
    ) -> Task<PersistentIdentifier, Error> {
        if let draftCreationTask = draftCreationTasks[mode] {
            return draftCreationTask
        }

        draftCreationTaskIDs[mode] = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else {
                throw SidebarViewModelError.threadMissing
            }
            let resolution = await resolvedThreadDefaults()
            guard let providerID = resolution.providerID else {
                throw SidebarViewModelError.noReadyThreadDefaultProvider
            }
            let seed = ThreadCreationSeed(
                provider: providerID,
                permissionMode: resolution.permissionMode,
                model: resolution.storedThreadModel,
                effort: resolution.effort,
                isDraft: true,
                mode: mode
            )
            let draft: AgentThread
            switch mode {
            case .project:
                guard let destinationPath = pendingDraftProjectPaths[.project] ?? requestedProjectPath else {
                    throw SidebarViewModelError.projectMissing
                }
                draft = try createThread(projectPath: destinationPath, seed: seed)
            case .task:
                draft = try createTaskThread(seed: seed)
            }
            cachedDraftThreadIDs[mode] = draft.persistentModelID
            return draft.persistentModelID
        }
        draftCreationTasks[mode] = task
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
        return try insertThread(
            project: dbProject,
            seed: ThreadCreationSeed(
                provider: provider,
                permissionMode: permissionMode,
                model: threadModel,
                effort: effort,
                isDraft: false,
                mode: .project
            )
        )
    }

    func createThread(
        projectPath: String,
        seed: ThreadCreationSeed
    ) throws -> AgentThread {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == projectPath
        })
        guard let project = try modelContext.fetch(descriptor).first else {
            throw SidebarViewModelError.projectMissing
        }
        return try insertThread(
            project: project,
            seed: seed
        )
    }

    func insertThread(project: Project, seed: ThreadCreationSeed) throws -> AgentThread {
        precondition(seed.mode == .project)
        if modelContext.hasChanges {
            try modelContext.save()
        }
        let thread = AgentThread(
            name: "New thread",
            permissionMode: seed.permissionMode,
            effort: seed.effort,
            model: seed.model,
            useWorktree: settingsService.current.createWorktreeByDefault && project.isGitRepository,
            isDraft: seed.isDraft,
            project: project
        )
        thread.mode = .project
        let conversation = Conversation(
            provider: seed.provider,
            isMain: true,
            displayOrder: 0,
            thread: thread
        )

        modelContext.insert(thread)
        modelContext.insert(conversation)
        do {
            try persistThreadCreation()
        } catch {
            modelContext.rollback()
            throw error
        }
        return thread
    }

    func createTaskThread(seed: ThreadCreationSeed) throws -> AgentThread {
        precondition(seed.mode == .task)
        if modelContext.hasChanges {
            try modelContext.save()
        }
        let workspace = try taskWorkspaceOwnershipService.createPrivateWorkspace()
        let thread = AgentThread(
            name: "New task",
            permissionMode: seed.permissionMode,
            effort: seed.effort,
            model: seed.model,
            useWorktree: false,
            isDraft: seed.isDraft,
            project: nil
        )
        thread.mode = .task
        thread.taskWorkspaceDescriptor = workspace
        let conversation = Conversation(
            provider: seed.provider,
            isMain: true,
            displayOrder: 0,
            thread: thread
        )

        modelContext.insert(thread)
        modelContext.insert(conversation)
        do {
            try persistThreadCreation()
        } catch {
            modelContext.rollback()
            try? taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace)
            throw error
        }
        return thread
    }

    func resolveCachedOrPersistedDraftThread(mode: AgentThreadMode) -> AgentThread? {
        if let cachedDraftThreadID = cachedDraftThreadIDs[mode],
           let draft = modelContext.resolveThread(id: cachedDraftThreadID),
           draft.isDraft,
           draft.mode == mode {
            return draft
        }

        let descriptor = FetchDescriptor<AgentThread>(predicate: #Predicate { thread in
            thread.isDraft == true
        })
        guard let draft = try? modelContext.fetch(descriptor).first(where: { $0.mode == mode }) else {
            cachedDraftThreadIDs[mode] = nil
            return nil
        }
        cachedDraftThreadIDs[mode] = draft.persistentModelID
        return draft
    }

    func moveDraftThread(_ draft: AgentThread, toProjectPath projectPath: String) throws -> AgentThread {
        guard draft.isDraft, draft.mode == .project else {
            throw SidebarViewModelError.threadMissing
        }
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == projectPath
        })
        guard let project = try modelContext.fetch(descriptor).first else {
            throw SidebarViewModelError.projectMissing
        }

        if draft.project?.persistentModelID == project.persistentModelID {
            settingsService.updateLastActiveProjectPath(project.path)
            return draft
        }

        let previousProject = draft.project
        draft.project = project
        do {
            try persistDraftProjectMove()
        } catch {
            draft.project = previousProject
            pendingDraftProjectPaths[.project] = previousProject?.path
            throw error
        }
        settingsService.updateLastActiveProjectPath(project.path)
        NotificationCenter.default.post(
            name: .threadDraftProjectChanged,
            object: nil,
            userInfo: [
                ThreadDraftNotificationKey.threadID: draft.persistentModelID,
                ThreadDraftNotificationKey.projectPath: project.path,
                ThreadDraftNotificationKey.mode: AgentThreadMode.project.rawValue
            ]
        )
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

private struct ThreadCreationSeed {
    let provider: String
    let permissionMode: String
    let model: String?
    let effort: String
    let isDraft: Bool
    let mode: AgentThreadMode
}
