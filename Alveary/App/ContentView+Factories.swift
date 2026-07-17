import Foundation
import SwiftData

struct ContentViewBootstrapState {
    let sidebarViewModel: SidebarViewModel
    let appShotCoordinator: AppShotCoordinator
    let appShotCaptureController: AppShotCaptureController
}

extension ContentView {
    static func makeBootstrapState(
        dependencies: ContentViewDependencies,
        appState: AppState
    ) -> ContentViewBootstrapState {
        let sidebarViewModel = makeSidebarViewModel(dependencies: dependencies, appState: appState)
        let appShotCoordinator = AppShotCoordinator()
        return ContentViewBootstrapState(
            sidebarViewModel: sidebarViewModel,
            appShotCoordinator: appShotCoordinator,
            appShotCaptureController: makeAppShotCaptureController(
                dependencies: dependencies,
                appState: appState,
                appShotCoordinator: appShotCoordinator,
                sidebarViewModel: sidebarViewModel
            )
        )
    }

    static func makeAppShotCaptureController(
        dependencies: ContentViewDependencies,
        appState: AppState,
        appShotCoordinator: AppShotCoordinator,
        sidebarViewModel: SidebarViewModel
    ) -> AppShotCaptureController {
        let modelContext = dependencies.modelContainer.mainContext
        return AppShotCaptureController(
            appState: appState,
            modelContext: modelContext,
            settingsService: dependencies.settingsService,
            runtimeStore: dependencies.runtimeStore,
            attachmentStore: dependencies.attachmentStore,
            isVoiceInputLocked: {
                dependencies.voiceInputLifecycleController.isComposerInteractionLocked
            },
            prepareCapture: { try await appShotCoordinator.prepareCapture() },
            openDraft: { projectID in
                guard let project = modelContext.resolveProject(id: projectID) else {
                    throw SidebarViewModelError.projectMissing
                }
                return try await sidebarViewModel.openDraftThread(project: project).persistentModelID
            }
        )
    }

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
            taskWorkspaceOwnershipService: dependencies.taskWorkspaceOwnershipService,
            invalidateConversationController: { conversationID in
                dependencies.conversationControllerRegistry.invalidate(
                    for: ConversationControllerKey(conversationID: conversationID)
                )
            },
            stopAndWaitForScheduledTaskRun: { runID in
                try await dependencies.scheduledTaskSchedulerCoordinator.stopAndWait(runID: runID)
            },
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

    static func makeScheduledTasksViewModel(dependencies: ContentViewDependencies) -> ScheduledTasksViewModel {
        ScheduledTasksViewModel(
            modelContext: dependencies.modelContainer.mainContext,
            mutationService: dependencies.scheduledTaskMutationService,
            providerDiscovery: dependencies.providerDiscovery,
            settingsService: dependencies.settingsService,
            agentRegistry: dependencies.agentRegistry,
            runNow: { request in
                guard dependencies.scheduledTaskLifecycleCoordinator.canStartManualRuns else {
                    return false
                }
                return dependencies.scheduledTaskSchedulerCoordinator.startRunNow(request)
            }
        )
    }

    static func makeScheduledTaskProposalQueueCoordinator(
        dependencies: ContentViewDependencies
    ) -> ScheduledTaskProposalQueueCoordinator {
        ScheduledTaskProposalQueueCoordinator(
            modelContext: ModelContext(dependencies.modelContainer),
            mutationService: dependencies.scheduledTaskMutationService,
            runNow: { request in
                guard dependencies.scheduledTaskLifecycleCoordinator.canStartManualRuns else {
                    return false
                }
                return dependencies.scheduledTaskSchedulerCoordinator.startRunNow(request)
            }
        )
    }

    static func makeArchivedTasksSettingsViewModel(
        dependencies: ContentViewDependencies,
        sidebarViewModel: SidebarViewModel,
        appState: AppState
    ) -> ArchivedTasksSettingsViewModel {
        ArchivedTasksSettingsViewModel(
            modelContext: dependencies.modelContainer.mainContext,
            sidebarViewModel: sidebarViewModel,
            appState: appState,
            settingsService: dependencies.settingsService
        )
    }
}
