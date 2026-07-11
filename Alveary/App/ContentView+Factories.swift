import Foundation

extension ContentView {
    static func makeSidebarViewModel(dependencies: ContentViewDependencies, appState: AppState) -> SidebarViewModel {
        SidebarViewModel(
            agentsManager: dependencies.agentsManager,
            modelContext: dependencies.modelContainer.mainContext,
            shell: dependencies.shellRunner,
            gitHubCLI: dependencies.gitHubCLI,
            worktreeManager: dependencies.worktreeManager,
            settingsService: dependencies.settingsService,
            providerDiscovery: dependencies.providerDiscovery,
            providerSessionActions: dependencies.providerSessionActions,
            attachmentStore: dependencies.attachmentStore,
            presentUnexpectedError: { message in
                appState.presentUnexpectedError(message: message)
            },
            notificationManager: dependencies.notificationManager,
            threadActivityRecorder: dependencies.threadActivityRecorder
        )
    }

    static func makeDiffViewModel(dependencies: ContentViewDependencies) -> DiffViewerViewModel {
        DiffViewerViewModel(
            gitService: dependencies.gitService,
            diffStore: dependencies.diffWorkspaceStore,
            fileListManager: dependencies.fileListManager,
            agentsManager: dependencies.agentsManager
        )
    }

    static func makeSettingsViewModel(dependencies: ContentViewDependencies) -> SettingsViewModel {
        let soundPreviewer = SettingsSoundPreviewer()
        return SettingsViewModel(
            settingsService: dependencies.settingsService,
            providerDiscovery: dependencies.providerDiscovery,
            agentRegistry: dependencies.agentRegistry,
            soundPreviewer: soundPreviewer.play
        )
    }
}
