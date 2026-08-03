import NeedleFoundation

@MainActor
extension AppComponent {
    /// App-scoped thread creation and archiving. Callers with no window — the `alveary_host`
    /// thread tools — use this instance; `SidebarViewModel` builds its own over the same
    /// `mainContext`, and the service holds no state of its own.
    var threadLifecycleService: ThreadLifecycleService {
        return shared {
            ThreadLifecycleService(
                modelContext: modelContainer.mainContext,
                settingsService: settingsService,
                agentsManager: agentsManager,
                providerSessionActionService: providerSessionActionService,
                notificationManager: notificationManager,
                invalidateConversationController: { conversationID in
                    self.conversationControllerRegistry.invalidate(
                        for: ConversationControllerKey(conversationID: conversationID)
                    )
                },
                stopAndWaitForScheduledTaskRun: { runID in
                    try await self.scheduledTaskSchedulerCoordinator.stopAndWait(runID: runID)
                }
            )
        }
    }
}
