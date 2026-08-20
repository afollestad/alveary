import AgentCLIKit
import SwiftData

struct ContentViewDependencies {
    let settingsService: SettingsService
    let shellRunner: ShellRunner
    let gitHubCLI: GitHubCLIService
    let providerDetection: any ProviderDetectionService
    /// The cached decorator, so thread creation and the composer do not each re-probe.
    let providerDiscovery: any AgentCLIKit.AgentProviderDiscoveryService
    /// The same object, concrete, for the Agents settings screen's invalidation.
    let providerDiscoveryCache: CachingAgentProviderDiscoveryService
    let agentRegistry: AgentRegistry
    let providerRegistry: ProviderRegistry
    let skillsService: SkillsService
    let globalAgentInstructionsService: GlobalAgentInstructionsService
    let mcpService: MCPService
    let agentsManager: any AgentsManager
    let agentOneShotPromptService: any AgentOneShotPromptService
    let runtimeStore: any ConversationRuntimeStore
    let conversationControllerRegistry: any ConversationControllerRegistry
    let attachmentStore: any ConversationAttachmentStore
    let keepAwakeService: KeepAwakeService
    let worktreeManager: WorktreeManager
    let taskWorkspaceOwnershipService: any TaskWorkspaceOwnershipService
    let scheduledTaskMutationService: ScheduledTaskMutationService
    let scheduledTaskSchedulerCoordinator: ScheduledTaskSchedulerCoordinator
    let scheduledTaskLifecycleCoordinator: ScheduledTaskLifecycleCoordinator
    let providerSessionActions: any ProviderSessionActionService
    let providerSetup: ProviderSetupService
    let contextWindowCache: any ContextWindowCache
    let fileListManager: FileListManager
    let notificationManager: any NotificationManager
    let notificationRouter: NotificationRouter
    let menuBarCommandRouter: MenuBarCommandRouter
    let mainWindowPresenter: MainWindowPresenter
    /// App-scoped: its global shortcut has to outlive the window.
    let appShotCoordinator: AppShotCoordinator
    let appUpdateManager: AppUpdateManager
    let onboardingDependencyService: any OnboardingDependencyService
    let threadActivityRecorder: any ThreadActivityRecording
    let gitService: GitService
    let diffWorkspaceStore: DiffWorkspaceStore
    let pullRequestsService: any PullRequestsService
    let pullRequestAgenticThreadService: PullRequestAgenticThreadService
    let pullRequestAgenticThreadActivity: PullRequestAgenticThreadActivity
    let gitHubAttachmentUploadService: any GitHubAttachmentUploadService
    let gitHubAttachmentImageURLResolver: GitHubAttachmentImageURLResolver
    let gitHubDiffImageBlobFetcher: GitHubDiffImageBlobFetcher
    let gitHubAvatarLoader: GitHubAvatarLoader
    let pullRequestsListCache: PullRequestsListCache
    let pullRequestReviewProposalPreviewCache: PullRequestReviewProposalPreviewCache
    let voiceInputService: any VoiceInputService
    let voiceInputLifecycleController: VoiceInputLifecycleController
    let modelContainer: ModelContainer

    @MainActor
    static func resolve(_ component: AppComponent) -> ContentViewDependencies {
        ContentViewDependencies(
            settingsService: component.settingsService,
            shellRunner: component.shellRunner,
            gitHubCLI: component.gitHubCLIService,
            providerDetection: component.providerDetectionService,
            providerDiscovery: component.cachedAgentProviderDiscoveryService,
            providerDiscoveryCache: component.cachedAgentProviderDiscoveryService,
            agentRegistry: component.agentRegistry,
            providerRegistry: component.providerRegistry,
            skillsService: component.skillsService,
            globalAgentInstructionsService: component.globalAgentInstructionsService,
            mcpService: component.mcpService,
            agentsManager: component.agentsManager,
            agentOneShotPromptService: component.agentOneShotPromptService,
            runtimeStore: component.conversationRuntimeStore,
            conversationControllerRegistry: component.conversationControllerRegistry,
            attachmentStore: component.conversationAttachmentStore,
            keepAwakeService: component.keepAwakeService,
            worktreeManager: component.worktreeManager,
            taskWorkspaceOwnershipService: component.taskWorkspaceOwnershipService,
            scheduledTaskMutationService: component.scheduledTaskMutationService,
            scheduledTaskSchedulerCoordinator: component.scheduledTaskSchedulerCoordinator,
            scheduledTaskLifecycleCoordinator: component.scheduledTaskLifecycleCoordinator,
            providerSessionActions: component.providerSessionActionService,
            providerSetup: component.providerSetupService,
            contextWindowCache: component.contextWindowCache,
            fileListManager: component.fileListManager,
            notificationManager: component.notificationManager,
            notificationRouter: component.notificationRouter,
            menuBarCommandRouter: component.menuBarCommandRouter,
            mainWindowPresenter: component.mainWindowPresenter,
            appShotCoordinator: component.appShotCoordinator,
            appUpdateManager: component.appUpdateManager,
            onboardingDependencyService: component.onboardingDependencyService,
            threadActivityRecorder: component.threadActivityRecorder,
            gitService: component.gitService,
            diffWorkspaceStore: component.diffWorkspaceStore,
            pullRequestsService: component.pullRequestsService,
            pullRequestAgenticThreadService: component.pullRequestAgenticThreadService,
            pullRequestAgenticThreadActivity: component.pullRequestAgenticThreadActivity,
            gitHubAttachmentUploadService: component.gitHubAttachmentUploadService,
            gitHubAttachmentImageURLResolver: component.gitHubAttachmentImageURLResolver,
            gitHubDiffImageBlobFetcher: component.gitHubDiffImageBlobFetcher,
            gitHubAvatarLoader: component.gitHubAvatarLoader,
            pullRequestsListCache: component.pullRequestsListCache,
            pullRequestReviewProposalPreviewCache: component.pullRequestReviewProposalPreviewCache,
            voiceInputService: component.voiceInputService,
            voiceInputLifecycleController: component.voiceInputLifecycleController,
            modelContainer: component.modelContainer
        )
    }
}
