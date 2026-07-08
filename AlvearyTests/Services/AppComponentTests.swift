import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class AppComponentTests: XCTestCase {
    func testContainerScopedServicesReturnStableInstances() throws {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)

        XCTAssertTrue(component.modelContext === component.modelContext)
        XCTAssertTrue(component.modelContainer === component.modelContainer)
        assertSameInstance(component.settingsService, component.settingsService)
        assertSameInstance(component.shellRunner, component.shellRunner)
        assertSameInstance(component.sessionManager, component.sessionManager)
        XCTAssertTrue(component.notificationRouter === component.notificationRouter)
        assertSameInstance(component.notificationManager, component.notificationManager)
        assertSameInstance(component.appUpdateManager, component.appUpdateManager)
        assertSameInstance(component.agentRegistry, component.agentRegistry)
        assertSameInstance(component.providerRegistry, component.providerRegistry)
        assertSameInstance(component.providerDetectionService, component.providerDetectionService)
        assertSameInstance(component.keepAwakeService, component.keepAwakeService)
        assertSameInstance(component.agentCLIKitRuntime, component.agentCLIKitRuntime)
        assertSameInstance(component.agentCLIKitSessionStore, component.agentCLIKitSessionStore)
        assertSameInstance(component.agentCLIKitInteractionStore, component.agentCLIKitInteractionStore)
        assertSameInstance(component.agentCLIKitApprovalPolicyStore, component.agentCLIKitApprovalPolicyStore)
        assertSameInstance(component.agentCLIKitClaudeApprovalPolicyStore, component.agentCLIKitClaudeApprovalPolicyStore)
        XCTAssertEqual(component.agentCLIKitProviderAdapterSet.definitions.map(\.id.rawValue), ["claude", "codex"])
        _ = component.agentCLIKitOneShotPromptRunner
        assertSameInstance(component.agentCLIKitClaudeConfigStore, component.agentCLIKitClaudeConfigStore)
        assertSameInstance(component.agentCLIKitCodexConfigStore, component.agentCLIKitCodexConfigStore)
        assertSameInstance(component.agentCLIKitProviderRegistry, component.agentCLIKitProviderRegistry)
        _ = component.agentCLIKitProjectTrustService
        _ = component.agentCLIKitProviderDiscoveryService
        assertSameInstance(component.agentCLIKitContextWindowCache, component.agentCLIKitContextWindowCache)
        assertSameInstance(component.claudeApprovalPersistenceStore, component.claudeApprovalPersistenceStore)
        assertSameInstance(component.executablePathResolver, component.executablePathResolver)
        assertSameInstance(component.gitService, component.gitService)
        assertSameInstance(component.gitHubCLIService, component.gitHubCLIService)
        assertSameInstance(component.skillsService, component.skillsService)
        assertSameInstance(component.mcpService, component.mcpService)

        let agentsManager = try XCTUnwrap(component.agentsManager as? DefaultAgentsManager)
        let runtimeStore = try XCTUnwrap(component.conversationRuntimeStore as? DefaultAgentsManager)
        XCTAssertTrue(component.defaultAgentsManager === agentsManager)
        XCTAssertTrue(component.defaultAgentsManager === runtimeStore)
        assertSameInstance(component.agentOneShotPromptService, component.agentOneShotPromptService)
    }

    func testRootPropertiesResolveAllServices() {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)

        _ = component.modelContainer
        _ = component.modelContext
        _ = component.settingsService
        _ = component.shellRunner
        _ = component.executablePathResolver
        _ = component.sessionManager
        _ = component.notificationRouter
        _ = component.notificationManager
        _ = component.appUpdateReleaseClient
        _ = component.appVersionProvider
        _ = component.appUpdateManager
        _ = component.agentRegistry
        _ = component.providerRegistry
        _ = component.providerDetectionService
        _ = component.keepAwakeService
        _ = component.agentEnvironmentBuilder
        _ = component.providerSetupService
        _ = component.contextWindowCache
        _ = component.agentCLIKitShellRunner
        _ = component.agentCLIKitInteractionStore
        _ = component.agentCLIKitApprovalPolicyStore
        _ = component.agentCLIKitClaudeApprovalPolicyStore
        _ = component.agentCLIKitProviderAdapterSet
        _ = component.agentCLIKitOneShotPromptRunner
        _ = component.agentCLIKitClaudeConfigStore
        _ = component.agentCLIKitCodexConfigStore
        _ = component.agentCLIKitProviderRegistry
        _ = component.agentCLIKitProviderDetector
        _ = component.agentCLIKitProviderSetup
        _ = component.agentCLIKitCodexProviderSetup
        _ = component.agentCLIKitProjectTrustService
        _ = component.agentCLIKitProviderDiscoveryService
        _ = component.agentCLIKitContextWindowCache
        _ = component.agentCLIKitHostAdapter
        _ = component.agentCLIKitRuntime
        _ = component.agentCLIKitSessionStore
        _ = component.agentCLIKitHostServices
        _ = component.claudeApprovalPersistenceStore
        _ = component.defaultAgentsManager
        _ = component.agentsManager
        _ = component.agentOneShotPromptService
        _ = component.conversationRuntimeStore
        _ = component.gitService
        _ = component.worktreeManager
        _ = component.fileListManager
        _ = component.diffWorkspaceStore
        _ = component.gitHubCLIService
        _ = component.skillsService
        _ = component.mcpService
    }

    func testAgentCLIKitProviderRegistryUsesAdapterSetDefinitions() async {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)

        let adapterSetIDs = component.agentCLIKitProviderAdapterSet.definitions.map(\.id.rawValue)
        let registryIDs = await component.agentCLIKitProviderRegistry.allDefinitions().map(\.id.rawValue)

        XCTAssertEqual(registryIDs, adapterSetIDs)
    }

    func testAgentCLIKitCodexAdapterUsesSharedSessionApprovalStore() throws {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)
        let approvalStore = try XCTUnwrap(
            component.agentCLIKitCodexProviderConfiguration.sessionApprovalPolicyStore as? AgentCLIKitClaudeApprovalStoreAdapter
        )

        XCTAssertTrue(approvalStore === component.agentCLIKitClaudeApprovalPolicyStore)
    }

    func testAgentCLIKitHostAdapterMapsSpawnConfig() throws {
        let adapter = AgentCLIKitHostAdapter()
        let config = try adapter.spawnConfig(from: AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: "/tmp/project",
            permissionMode: "bypassPermissions",
            planModeEnabled: true,
            model: "sonnet",
            effort: "high",
            reasoningSummaryMode: .auto,
            speedMode: .fast,
            initialPrompt: "Start"
        ))

        XCTAssertEqual(config.providerId.rawValue, "claude")
        XCTAssertEqual(config.workingDirectory.path, "/tmp/project")
        XCTAssertEqual(config.permissionMode, "bypassPermissions")
        XCTAssertEqual(config.collaborationMode, .plan)
        XCTAssertEqual(config.model, "sonnet")
        XCTAssertEqual(config.effort, "high")
        XCTAssertEqual(config.reasoningSummaryMode, .auto)
        XCTAssertEqual(config.speedMode?.rawValue, "fast")
        XCTAssertEqual(config.initialPrompt, "Start")
    }

    func testAgentCLIKitHostAdapterAcceptsCodexProvider() throws {
        let adapter = AgentCLIKitHostAdapter()

        let config = try adapter.spawnConfig(from: AgentSpawnConfig(
            providerId: "codex",
            workingDirectory: "/tmp/project",
            permissionMode: "on-request",
            model: nil,
            effort: "high",
            initialPrompt: nil
        ))

        XCTAssertEqual(config.providerId.rawValue, "codex")
        XCTAssertEqual(config.permissionMode, "on-request")
        XCTAssertEqual(config.effort, "high")
    }

    func testAgentCLIKitHostAdapterRejectsUnsupportedProvider() {
        let adapter = AgentCLIKitHostAdapter()

        XCTAssertThrowsError(try adapter.spawnConfig(from: AgentSpawnConfig(
            providerId: "unknown",
            workingDirectory: "/tmp/project",
            permissionMode: nil,
            model: nil,
            effort: nil,
            initialPrompt: nil
        ))) { error in
            XCTAssertEqual(error as? AgentCLIKitHostAdapterError, .unsupportedProvider("unknown"))
        }
    }

    private func assertSameInstance<T>(
        _ first: T,
        _ second: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue((first as AnyObject) === (second as AnyObject), file: file, line: line)
    }

}
