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
            let providerSetup = self.providerSetupService
            let contextWindowCache = self.contextWindowCache
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
                    providerSetup: providerSetup,
                    contextWindowCache: contextWindowCache,
                    attachmentStore: attachmentStore,
                    threadActivityRecorder: threadActivityRecorder
                )
            }
        }
    }
}
