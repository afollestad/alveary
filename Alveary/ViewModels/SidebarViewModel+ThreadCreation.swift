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
        pendingDraftProjectPath = requestedProjectPath

        if let draft = resolveCachedOrPersistedDraftThread() {
            return try moveDraftThread(draft, toProjectPath: requestedProjectPath)
        }

        let task = activeDraftCreationTask(requestedProjectPath: requestedProjectPath)

        let taskID = draftCreationTaskID
        defer {
            if draftCreationTaskID == taskID {
                draftCreationTask = nil
                draftCreationTaskID = nil
            }
        }

        let threadID = try await task.value
        guard let draft = modelContext.resolveThread(id: threadID),
              draft.isDraft else {
            throw SidebarViewModelError.threadMissing
        }
        let destinationPath = pendingDraftProjectPath ?? requestedProjectPath
        return try moveDraftThread(draft, toProjectPath: destinationPath)
    }

    func moveDraftThread(id: PersistentIdentifier, toProjectPath projectPath: String) throws -> AgentThread {
        guard let draft = modelContext.resolveThread(id: id),
              draft.isDraft else {
            throw SidebarViewModelError.threadMissing
        }
        return try moveDraftThread(draft, toProjectPath: projectPath)
    }

    func noteDraftMaterialized() {
        cachedDraftThreadID = nil
        pendingDraftProjectPath = nil
        threadOrderVersion += 1
    }

    func invalidateDraftThreadIfNeeded(threadID: PersistentIdentifier) {
        guard cachedDraftThreadID == threadID else {
            return
        }
        cachedDraftThreadID = nil
        pendingDraftProjectPath = nil
    }

    func invalidateDraftThreadIfNeeded(threadIDs: Set<PersistentIdentifier>) {
        guard let cachedDraftThreadID, threadIDs.contains(cachedDraftThreadID) else {
            return
        }
        self.cachedDraftThreadID = nil
        pendingDraftProjectPath = nil
    }
}

private extension SidebarViewModel {
    func activeDraftCreationTask(requestedProjectPath: String) -> Task<PersistentIdentifier, Error> {
        if let draftCreationTask {
            return draftCreationTask
        }

        draftCreationTaskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else {
                throw SidebarViewModelError.threadMissing
            }
            let resolution = await resolvedThreadDefaults()
            guard let providerID = resolution.providerID else {
                throw SidebarViewModelError.noReadyThreadDefaultProvider
            }
            let destinationPath = pendingDraftProjectPath ?? requestedProjectPath
            let draft = try createThread(
                projectPath: destinationPath,
                seed: ThreadCreationSeed(
                    provider: providerID,
                    permissionMode: resolution.permissionMode,
                    model: resolution.storedThreadModel,
                    effort: resolution.effort,
                    isDraft: true
                )
            )
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
        return try insertThread(
            project: dbProject,
            seed: ThreadCreationSeed(
                provider: provider,
                permissionMode: permissionMode,
                model: threadModel,
                effort: effort,
                isDraft: false
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

    func resolveCachedOrPersistedDraftThread() -> AgentThread? {
        if let cachedDraftThreadID,
           let draft = modelContext.resolveThread(id: cachedDraftThreadID),
           draft.isDraft {
            return draft
        }

        let descriptor = FetchDescriptor<AgentThread>(predicate: #Predicate { thread in
            thread.isDraft == true
        })
        guard let draft = try? modelContext.fetch(descriptor).first else {
            cachedDraftThreadID = nil
            return nil
        }
        cachedDraftThreadID = draft.persistentModelID
        return draft
    }

    func moveDraftThread(_ draft: AgentThread, toProjectPath projectPath: String) throws -> AgentThread {
        guard draft.isDraft else {
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
            pendingDraftProjectPath = previousProject?.path
            throw error
        }
        settingsService.updateLastActiveProjectPath(project.path)
        NotificationCenter.default.post(
            name: .threadDraftProjectChanged,
            object: nil,
            userInfo: [
                ThreadDraftNotificationKey.threadID: draft.persistentModelID,
                ThreadDraftNotificationKey.projectPath: project.path
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
}
