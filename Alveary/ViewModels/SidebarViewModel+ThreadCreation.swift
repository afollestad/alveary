import Foundation

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
}

private extension SidebarViewModel {
    func createThread(
        project: Project,
        provider: String,
        permissionMode: String,
        threadModel: String?,
        effort: String
    ) async throws -> AgentThread {
        let dbProject = try requireProject(project)
        let thread = AgentThread(
            name: "New thread",
            permissionMode: permissionMode,
            effort: effort,
            model: threadModel,
            useWorktree: settingsService.current.createWorktreeByDefault && dbProject.isGitRepository,
            project: dbProject
        )
        let conversation = Conversation(
            provider: provider,
            isMain: true,
            displayOrder: 0,
            thread: thread
        )

        modelContext.insert(thread)
        modelContext.insert(conversation)
        try modelContext.save()
        return thread
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
