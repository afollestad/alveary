import AgentCLIKit
import Foundation
import NeedleFoundation
import SwiftData

final class AppComponent: BootstrapComponent {
    let storageProfile: AppStorageProfile
    let isStoredInMemoryOnly: Bool

    init(
        storageProfile: AppStorageProfile,
        isStoredInMemoryOnly: Bool = false
    ) {
        self.storageProfile = storageProfile
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        super.init()
    }

    var dataComponent: DataComponent {
        return shared { DataComponent(parent: self) }
    }

    var settingsComponent: SettingsComponent {
        return shared { SettingsComponent(parent: self) }
    }

    var shellComponent: ShellComponent {
        return shared { ShellComponent(parent: self) }
    }

    var sessionComponent: SessionComponent {
        return shared { SessionComponent(parent: self) }
    }

    var notificationComponent: NotificationComponent {
        return shared { NotificationComponent(parent: self) }
    }

    var detectionComponent: DetectionComponent {
        return shared { DetectionComponent(parent: self) }
    }

    var powerComponent: PowerComponent {
        return shared { PowerComponent(parent: self) }
    }

    var agentComponent: AgentComponent {
        return shared { AgentComponent(parent: self) }
    }

    var gitComponent: GitComponent {
        return shared { GitComponent(parent: self) }
    }

    var gitHubComponent: GitHubComponent {
        return shared { GitHubComponent(parent: self) }
    }

    var skillsComponent: SkillsComponent {
        return shared { SkillsComponent(parent: self) }
    }

    var mcpComponent: MCPComponent {
        return shared { MCPComponent(parent: self) }
    }
}

@MainActor
extension AppComponent {
    var shellRunner: ShellRunner {
        return shared { DefaultShellRunner() }
    }

    var executablePathResolver: any ExecutablePathResolving {
        return shared { DefaultExecutablePathResolver(shell: shellRunner) }
    }

    var notificationRouter: NotificationRouter {
        return shared { NotificationRouter() }
    }

    var notificationManager: NotificationManager {
        return shared {
            DefaultNotificationManager(
                settingsService: settingsService,
                modelContainer: modelContainer
            )
        }
    }

    var threadActivityRecorder: any ThreadActivityRecording {
        return shared { ThreadActivityRecorder(modelContext: modelContext) }
    }

    var agentRegistry: AgentRegistry {
        return shared { DefaultAgentRegistry() }
    }

    var harnessRegistry: HarnessRegistry {
        return shared { DefaultHarnessRegistry(agentRegistry: agentRegistry) }
    }

    var harnessDetectionService: HarnessDetectionService {
        return shared {
            DefaultHarnessDetectionService(
                shell: shellRunner,
                registry: harnessRegistry,
                executableResolver: executablePathResolver
            )
        }
    }

    var keepAwakeService: KeepAwakeService {
        return shared { DefaultKeepAwakeService(settingsService: settingsService) }
    }

    var agentEnvironmentBuilder: AgentEnvironmentBuilder {
        return shared { DefaultAgentEnvironmentBuilder() }
    }

    var harnessSetupService: HarnessSetupService {
        return shared {
            DefaultHarnessSetupService(
                projectTrustService: agentCLIKitProjectTrustService,
                projectTrustUpdates: harnessProjectTrustUpdates(stores: [
                    claudeProjectTrustUpdates(from: agentCLIKitClaudeConfigStore),
                    codexProjectTrustUpdates(from: agentCLIKitCodexConfigStore)
                ])
            )
        }
    }

    var agentCLIKitShellRunner: AgentCLIKitShellRunnerAdapter {
        return shared { AgentCLIKitShellRunnerAdapter(shellRunner: shellRunner) }
    }

    var agentCLIKitInteractionStore: AgentCLIKit.InMemoryAgentInteractionStore {
        return shared { AgentCLIKit.InMemoryAgentInteractionStore() }
    }

    var agentCLIKitApprovalPolicyStore: AgentCLIKit.InMemoryAgentApprovalPolicyStore {
        return shared { AgentCLIKit.InMemoryAgentApprovalPolicyStore() }
    }

    var agentCLIKitClaudeApprovalPolicyStore: AgentCLIKitClaudeApprovalStoreAdapter {
        return shared { AgentCLIKitClaudeApprovalStoreAdapter(approvalPersistenceStore: claudeApprovalPersistenceStore) }
    }

    var agentCLIKitLiveHookDecisionProvider: AgentCLIKitLiveHookDecisionProvider {
        return shared { AgentCLIKitLiveHookDecisionProvider() }
    }

    var agentCLIKitClaudeHarnessConfiguration: AgentCLIKit.ClaudeHarnessAdapter.Configuration {
        AgentCLIKit.ClaudeHarnessAdapter.Configuration(
            interactionStore: agentCLIKitInteractionStore,
            approvalPolicyStore: agentCLIKitClaudeApprovalPolicyStore,
            hookSupportDirectory: storageProfile.agentCLIKitHookSupportDirectory,
            hookDecisionProvider: agentCLIKitLiveHookDecisionProvider
        )
    }

    var agentCLIKitCodexHarnessConfiguration: AgentCLIKit.CodexHarnessAdapter.Configuration {
        AgentCLIKit.CodexHarnessAdapter.Configuration(
            sessionApprovalPolicyStore: agentCLIKitClaudeApprovalPolicyStore
        )
    }

    var agentCLIKitHarnessAdapterSet: AgentCLIKit.AgentHarnessAdapterSet {
        return shared {
            AgentCLIKit.AgentHarnessAdapterSet.default(
                claude: agentCLIKitClaudeHarnessConfiguration,
                codex: agentCLIKitCodexHarnessConfiguration,
                opencode: agentCLIKitOpenCodeHarnessConfiguration
            )
        }
    }

    /// Cleanup must reach the server holding the Codex thread's writer lock, which outlives its runtime sentinel.
    var agentCLIKitSessionActionRouter: AgentCLIKit.AgentHarnessSessionActionRouter {
        AgentCLIKit.AgentHarnessSessionActionRouter(borrowing: agentCLIKitHarnessAdapterSet)
    }

    var harnessSessionActionService: any HarnessSessionActionService {
        return shared {
            AgentCLIKitHarnessSessionActionService(
                sessionStore: agentCLIKitSessionStore,
                router: agentCLIKitSessionActionRouter,
                harnessLookup: agentCLIKitHarnessRegistry
            )
        }
    }

    var harnessSessionBindingStore: any HarnessSessionBindingStore {
        return shared {
            SwiftDataHarnessSessionBindingStore(modelContainer: modelContainer)
        }
    }

    var agentCLIKitClaudeConfigStore: AgentCLIKit.ClaudeConfigStore {
        return shared {
            AgentCLIKit.ClaudeConfigStore(
                fileURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
            )
        }
    }

    var agentCLIKitCodexConfigStore: AgentCLIKit.CodexConfigStore {
        return shared {
            AgentCLIKit.CodexConfigStore(
                codexHomeDirectoryURL: AgentCLIKit.CodexConfigStore.defaultCodexHomeDirectoryURL
            )
        }
    }

    var agentCLIKitHarnessRegistry: AgentCLIKit.AgentHarnessRegistry {
        return shared {
            AgentCLIKit.AgentHarnessRegistry(
                definitions: agentCLIKitHarnessAdapterSet.definitions
            )
        }
    }

    var agentCLIKitHarnessDetector: AgentCLIKit.AgentHarnessDetector {
        return shared { AgentCLIKit.AgentHarnessDetector(shellRunner: agentCLIKitShellRunner) }
    }

    var agentCLIKitCodexHarnessSetup: AgentCLIKit.CodexHarnessSetup {
        return shared { AgentCLIKit.CodexHarnessSetup(configStore: agentCLIKitCodexConfigStore) }
    }

    var agentCLIKitProjectTrustService: AgentCLIKit.DefaultAgentProjectTrustService {
        return shared {
            AgentCLIKit.DefaultAgentProjectTrustService(setups: [
                agentCLIKitHarnessSetup,
                agentCLIKitCodexHarnessSetup,
                agentCLIKitOpenCodeHarnessSetup
            ])
        }
    }

    var agentCLIKitContextWindowCache: AgentCLIKit.JSONAgentModelContextWindowCache {
        return shared {
            AgentCLIKit.JSONAgentModelContextWindowCache(
                fileURL: storageProfile.agentCLIKitContextWindowCacheFileURL
            )
        }
    }

    var agentCLIKitHostAdapter: AgentCLIKitHostAdapter {
        return shared { AgentCLIKitHostAdapter() }
    }

    var agentCLIKitRuntime: AgentCLIKit.DefaultAgentRuntime {
        return shared {
            AgentCLIKit.DefaultAgentRuntime(
                adapterSet: agentCLIKitHarnessAdapterSet,
                sessionStore: agentCLIKitSessionStore,
                hostToolHandling: hostToolHandling
            )
        }
    }

    var agentCLIKitSessionStore: AgentCLIKit.JSONFileAgentSessionStore {
        return shared {
            AgentCLIKit.JSONFileAgentSessionStore(
                fileURL: storageProfile.agentCLIKitSessionStoreFileURL
            )
        }
    }

    var agentCLIKitHostServices: AgentCLIKitHostServices {
        return shared {
            AgentCLIKitHostServices(
                runtime: agentCLIKitRuntime,
                sessionStore: agentCLIKitSessionStore,
                harnessDetector: agentCLIKitHarnessDetector,
                harnessRegistry: agentCLIKitHarnessRegistry,
                claudeConfigStore: agentCLIKitClaudeConfigStore,
                claudeHarnessSetup: agentCLIKitHarnessSetup,
                interactionStore: agentCLIKitInteractionStore,
                approvalPolicyStore: agentCLIKitApprovalPolicyStore,
                claudeApprovalPolicyStore: agentCLIKitClaudeApprovalPolicyStore,
                liveHookDecisionProvider: agentCLIKitLiveHookDecisionProvider,
                contextWindowCache: agentCLIKitContextWindowCache,
                sessionActionRouter: agentCLIKitSessionActionRouter,
                hostAdapter: agentCLIKitHostAdapter
            )
        }
    }

    var claudeApprovalPersistenceStore: ClaudeApprovalPersistenceStore {
        return shared { DefaultClaudeApprovalPersistenceStore(supportDirectory: storageProfile.approvalSupportDirectory) }
    }

    var defaultAgentsManager: DefaultAgentsManager {
        return shared {
            DefaultAgentsManager(
                agentCLIKitServices: agentCLIKitHostServices,
                sessionManager: sessionManager,
                harnessDetection: harnessDetectionService,
                environmentBuilder: agentEnvironmentBuilder,
                harnessRegistry: harnessRegistry,
                settingsService: settingsService,
                keepAwakeService: keepAwakeService,
                notificationManager: notificationManager,
                fileListManager: fileListManager,
                threadActivityRecorder: threadActivityRecorder,
                claudeApprovalPersistenceStore: claudeApprovalPersistenceStore,
                harnessSessionBindingStore: harnessSessionBindingStore
            )
        }
    }

    var agentsManager: AgentsManager {
        return defaultAgentsManager
    }

    var agentOneShotPromptService: any AgentOneShotPromptService {
        return shared {
            DefaultAgentOneShotPromptService(
                promptRunner: agentCLIKitOneShotPromptRunner,
                settingsService: settingsService,
                harnessSetup: harnessSetupService,
                harnessDetection: harnessDetectionService,
                environmentBuilder: agentEnvironmentBuilder
            )
        }
    }

    var conversationRuntimeStore: ConversationRuntimeStore {
        return defaultAgentsManager
    }

    var gitService: GitService {
        return shared { demoGitService ?? CLIGitService(shell: shellRunner) }
    }

    var worktreeManager: WorktreeManager {
        return shared {
            DefaultWorktreeManager(
                settingsService: settingsService,
                shell: shellRunner
            )
        }
    }

    var taskWorkspaceOwnershipService: TaskWorkspaceOwnershipService {
        return shared {
            DefaultTaskWorkspaceOwnershipService(
                privateWorkspacesRoot: storageProfile.privateTaskWorkspacesDirectory,
                worktreeOwnershipRecordsRoot: storageProfile.worktreeOwnershipRecordsDirectory
            )
        }
    }

    var fileListManager: FileListManager {
        return shared { GitFileListManager(gitService: gitService) }
    }

    var diffWorkspaceStore: DiffWorkspaceStore {
        return shared { DiffWorkspaceStore(gitService: gitService) }
    }

    var gitHubCLIService: GitHubCLIService {
        return shared {
            DefaultGitHubCLIService(
                shell: shellRunner,
                executableResolver: executablePathResolver
            )
        }
    }

    var skillsService: SkillsService {
        return shared { demoSkillsService ?? DefaultSkillsService(agentRegistry: agentRegistry) }
    }

    var globalAgentInstructionsService: GlobalAgentInstructionsService {
        return shared { DefaultGlobalAgentInstructionsService(agentRegistry: agentRegistry) }
    }

    var mcpService: MCPService {
        return shared {
            demoMCPService ?? DefaultMCPService(
                claudeConfigStore: agentCLIKitClaudeConfigStore,
                codexConfigStore: agentCLIKitCodexConfigStore,
                openCodeConfigStore: agentCLIKitOpenCodeConfigStore,
                harnessDetection: harnessDetectionService,
                agentRegistry: agentRegistry
            )
        }
    }

}

private func claudeProjectTrustUpdates(
    from configStore: AgentCLIKit.ClaudeConfigStore
) -> @Sendable () async -> AsyncStream<Void> {
    {
        let snapshots = await configStore.snapshots()
        return AsyncStream { continuation in
            let task = Task {
                for await _ in snapshots {
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private func codexProjectTrustUpdates(
    from configStore: AgentCLIKit.CodexConfigStore
) -> @Sendable () async -> AsyncStream<Void> {
    {
        let snapshots = await configStore.snapshots()
        return AsyncStream { continuation in
            let task = Task {
                for await _ in snapshots {
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private func harnessProjectTrustUpdates(
    stores: [@Sendable () async -> AsyncStream<Void>]
) -> @Sendable () async -> AsyncStream<Void> {
    {
        let streams = await withTaskGroup(of: AsyncStream<Void>.self) { group in
            for store in stores {
                group.addTask {
                    await store()
                }
            }
            var streams: [AsyncStream<Void>] = []
            for await stream in group {
                streams.append(stream)
            }
            return streams
        }

        return AsyncStream { continuation in
            let tasks = streams.map { stream in
                Task {
                    for await _ in stream {
                        continuation.yield(())
                    }
                }
            }
            continuation.onTermination = { _ in
                tasks.forEach { $0.cancel() }
            }
        }
    }
}
