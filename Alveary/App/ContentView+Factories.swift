import Foundation
import SwiftData

struct ContentViewBootstrapState {
    let sidebarViewModel: SidebarViewModel
    let appShotCaptureController: AppShotCaptureController
    let lastActiveProjectRecorder: LastActiveProjectRecorder
    let diffViewModel: DiffViewerViewModel
    let scheduledTaskProposalQueueCoordinator: ScheduledTaskProposalQueueCoordinator
    let reviewProposalCoordinator: PullRequestReviewProposalCoordinator
    /// Built here rather than in `ContentView.init` because it needs `reviewProposalCoordinator`,
    /// which this state already owns.
    let pullRequestsViewModel: PullRequestsViewModel
    let archivedThreadsViewModel: ArchivedThreadsViewModel
}

extension ContentView {
    static func makeBootstrapState(
        dependencies: ContentViewDependencies,
        appState: AppState
    ) -> ContentViewBootstrapState {
        let sidebarViewModel = makeSidebarViewModel(dependencies: dependencies, appState: appState)
        let reviewProposalCoordinator = makePullRequestReviewProposalCoordinator(dependencies: dependencies)
        return ContentViewBootstrapState(
            sidebarViewModel: sidebarViewModel,
            appShotCaptureController: makeAppShotCaptureController(
                dependencies: dependencies,
                appState: appState,
                appShotCoordinator: dependencies.appShotCoordinator,
                sidebarViewModel: sidebarViewModel
            ),
            lastActiveProjectRecorder: makeLastActiveProjectRecorder(dependencies: dependencies),
            diffViewModel: makeDiffViewModel(dependencies: dependencies),
            scheduledTaskProposalQueueCoordinator: makeScheduledTaskProposalQueueCoordinator(dependencies: dependencies),
            reviewProposalCoordinator: reviewProposalCoordinator,
            pullRequestsViewModel: makePullRequestsViewModel(
                dependencies: dependencies,
                appState: appState,
                reviewProposalCoordinator: reviewProposalCoordinator
            ),
            archivedThreadsViewModel: makeArchivedThreadsViewModel(
                dependencies: dependencies,
                sidebarViewModel: sidebarViewModel,
                appState: appState
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
            },
            activateAlveary: { [presenter = dependencies.mainWindowPresenter] in presenter.activate() }
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
            invalidateProviderDiscoveryCache: { [cache = dependencies.providerDiscoveryCache] in
                await cache.invalidate()
            },
            agentRegistry: dependencies.agentRegistry,
            globalAgentInstructionsService: dependencies.globalAgentInstructionsService,
            soundPreviewer: soundPreviewer.play,
            launchAtStartupService: DefaultLaunchAtStartupService()
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

    /// `reviewProposalCoordinator` comes from the already-built bootstrap state so the pane can
    /// resolve the review proposal a transcript jump attaches it to.
    static func makePullRequestsViewModel(
        dependencies: ContentViewDependencies,
        appState: AppState,
        reviewProposalCoordinator: PullRequestReviewProposalCoordinator
    ) -> PullRequestsViewModel {
        let attachmentImageURLResolver = dependencies.gitHubAttachmentImageURLResolver
        return PullRequestsViewModel(
            service: dependencies.pullRequestsService,
            avatarLoader: dependencies.gitHubAvatarLoader,
            listCache: dependencies.pullRequestsListCache,
            settingsService: dependencies.settingsService,
            attachmentUploadService: dependencies.gitHubAttachmentUploadService,
            attachmentImageSeeder: { upload in
                guard let source = upload.referenceURL?.absoluteString else {
                    return
                }
                await AppMarkdownImageStore.shared.seedRemoteImage(source: source, fileURL: upload.fileURL)
            },
            attachmentImageRepositoryRegistrar: { repository in
                attachmentImageURLResolver.registerRepository(repository)
            },
            presentToast: { message in
                appState.presentUnexpectedError(message: message)
            },
            agenticThreadStarter: { request in
                try await dependencies.pullRequestAgenticThreadService.start(
                    kind: request.kind,
                    identifier: request.identifier,
                    url: request.url,
                    knownDetail: request.knownDetail,
                    preferredProjectID: request.preferredProjectID
                )
            },
            reviewProposalCoordinator: reviewProposalCoordinator
        )
    }

    static func makePullRequestLinksViewModel(
        dependencies: ContentViewDependencies
    ) -> PullRequestLinksViewModel {
        PullRequestLinksViewModel(
            // Links are UI mutations, so they share the main context with the
            // sidebar's `@Query` reads.
            modelContext: dependencies.modelContainer.mainContext,
            service: dependencies.pullRequestsService
        )
    }

    /// Its own `ModelContext`, matching the scheduling coordinator below: proposal resolution
    /// saves outside any view's editing context.
    static func makePullRequestReviewProposalCoordinator(
        dependencies: ContentViewDependencies
    ) -> PullRequestReviewProposalCoordinator {
        PullRequestReviewProposalCoordinator(
            modelContext: ModelContext(dependencies.modelContainer),
            pullRequestsService: dependencies.pullRequestsService,
            avatarLoader: dependencies.gitHubAvatarLoader,
            previewCache: dependencies.pullRequestReviewProposalPreviewCache
        )
    }

    /// Shares the main context rather than taking its own like the proposal coordinators below.
    /// It only reads, and approval rows are written to the main context behind a debounced save —
    /// a private context would not see one until that save landed, leaving the dot late.
    static func makeUnresolvedApprovalRegistry(
        dependencies: ContentViewDependencies
    ) -> UnresolvedApprovalRegistry {
        UnresolvedApprovalRegistry(modelContext: dependencies.modelContainer.mainContext)
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

    static func makeArchivedThreadsViewModel(
        dependencies: ContentViewDependencies,
        sidebarViewModel: SidebarViewModel,
        appState: AppState
    ) -> ArchivedThreadsViewModel {
        ArchivedThreadsViewModel(
            modelContext: dependencies.modelContainer.mainContext,
            sidebarViewModel: sidebarViewModel,
            appState: appState,
            settingsService: dependencies.settingsService
        )
    }

    static func makeOnboardingViewModel(dependencies: ContentViewDependencies) -> OnboardingViewModel {
        OnboardingViewModel(
            settingsService: dependencies.settingsService,
            dependencyService: dependencies.onboardingDependencyService,
            gitHubCLI: dependencies.gitHubCLI
        )
    }

    static func makeLastActiveProjectRecorder(
        dependencies: ContentViewDependencies
    ) -> LastActiveProjectRecorder {
        let modelContext = dependencies.modelContainer.mainContext
        let settingsService = dependencies.settingsService
        return LastActiveProjectRecorder(
            resolve: { owner in
                resolveLastActiveProject(owner, modelContext: modelContext)
            },
            persist: { path in
                settingsService.updateLastActiveProjectPath(path)
            }
        )
    }

    static func resolveLastActiveProject(
        _ owner: LastActiveProjectOwner,
        modelContext: ModelContext
    ) -> LastActiveProjectResolution {
        switch owner {
        case .project(let projectID):
            return .path(modelContext.resolveProject(id: projectID)?.path)
        case .thread(let threadID):
            guard let thread = modelContext.resolveThread(id: threadID),
                  thread.effectiveMode == .project else {
                return .unowned
            }
            return .path(thread.project?.path)
        }
    }
}
