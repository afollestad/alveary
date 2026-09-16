import NeedleFoundation

@MainActor
extension AppComponent {
    var conversationControllerRegistry: ConversationControllerRegistry {
        return shared {
            let modelContext = self.modelContainer.mainContext
            let agentsManager = self.agentsManager
            let runtimeStore = self.conversationRuntimeStore
            let keepAwakeService = self.keepAwakeService
            let settingsService = self.settingsService
            let worktreeManager = self.worktreeManager
            let taskWorkspaceOwnershipService = self.taskWorkspaceOwnershipService
            let harnessSetup = self.harnessSetupService
            let contextWindowCache = self.contextWindowCache
            let harnessDiscovery = self.cachedAgentHarnessDiscoveryService
            let attachmentStore = self.conversationAttachmentStore
            let threadActivityRecorder = self.threadActivityRecorder
            return DefaultConversationControllerRegistry { conversation in
                ConversationViewModel(
                    conversation: conversation,
                    agentsManager: agentsManager,
                    runtimeStore: runtimeStore,
                    keepAwakeService: keepAwakeService,
                    modelContext: modelContext,
                    settingsService: settingsService,
                    worktreeManager: worktreeManager,
                    taskWorkspaceOwnershipService: taskWorkspaceOwnershipService,
                    harnessSetup: harnessSetup,
                    contextWindowCache: contextWindowCache,
                    harnessDiscovery: harnessDiscovery,
                    attachmentStore: attachmentStore,
                    threadActivityRecorder: threadActivityRecorder
                )
            }
        }
    }
}
