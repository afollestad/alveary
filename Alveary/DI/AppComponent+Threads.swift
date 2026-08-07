import AgentCLIKit
import NeedleFoundation

@MainActor
extension AppComponent {
    var threadHostToolService: ThreadHostToolService {
        return shared {
            ThreadHostToolService(
                modelContext: modelContainer.mainContext,
                lifecycleService: threadLifecycleService,
                linkService: pullRequestLinkService,
                settingsService: settingsService,
                providerDiscovery: agentCLIKitProviderDiscoveryService,
                startInitialPrompt: { conversation, prompt in
                    self.startHeadlessInitialPrompt(conversation: conversation, prompt: prompt)
                }
            )
        }
    }

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
                taskWorkspaceOwnershipService: taskWorkspaceOwnershipService,
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

    /// Runs a newly created thread's first turn with no window mounted.
    ///
    /// Deliberately reuses the ordinary UI first-send path (`setupAndStart`) rather than the
    /// scheduled-run executor: this is a user-started thread in every respect except that nobody
    /// is looking at it, so it should create its worktree, spawn, auto-name, and get ordinary
    /// host-tool exposure exactly like one the user typed into.
    ///
    /// Detached on purpose — `create_thread` reports dispatch, not the turn's outcome. A spawn
    /// failure leaves a retryable failed first message on the new thread, which is the same thing
    /// the user would see had they started it themselves.
    /// Shared by `create_thread` and the pull request pane's agentic review, which differ only
    /// in the prompt they dispatch.
    func startHeadlessInitialPrompt(conversation: Conversation, prompt: String) {
        let registry = conversationControllerRegistry
        Task { @MainActor in
            let lease = registry.makeBackgroundLease(for: conversation)
            defer { lease.release() }
            lease.activate()
            do {
                try await lease.viewModel.setupAndStart(prompt)
            } catch {
                // The failure is already durable on the thread's own transcript.
                return
            }
            // Hold the lease until the turn finishes so the controller is not torn down mid-turn.
            for await outcome in lease.outcomes() where outcome.state.isTerminal {
                break
            }
        }
    }
}
