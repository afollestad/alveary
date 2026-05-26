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
        assertSameInstance(component.agentRegistry, component.agentRegistry)
        assertSameInstance(component.providerRegistry, component.providerRegistry)
        assertSameInstance(component.providerDetectionService, component.providerDetectionService)
        assertSameInstance(component.keepAwakeService, component.keepAwakeService)
        assertSameInstance(component.claudeConfigStore, component.claudeConfigStore)
        assertSameInstance(component.claudeHookServer, component.claudeHookServer)
        assertSameInstance(component.gitService, component.gitService)
        assertSameInstance(component.gitHubCLIService, component.gitHubCLIService)
        assertSameInstance(component.skillsService, component.skillsService)
        assertSameInstance(component.mcpService, component.mcpService)

        let agentsManager = try XCTUnwrap(component.agentsManager as? DefaultAgentsManager)
        let runtimeStore = try XCTUnwrap(component.conversationRuntimeStore as? DefaultAgentsManager)
        XCTAssertTrue(component.defaultAgentsManager === agentsManager)
        XCTAssertTrue(component.defaultAgentsManager === runtimeStore)
    }

    func testRootPropertiesResolveAllServices() {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)

        _ = component.modelContainer
        _ = component.modelContext
        _ = component.settingsService
        _ = component.shellRunner
        _ = component.sessionManager
        _ = component.notificationRouter
        _ = component.notificationManager
        _ = component.agentRegistry
        _ = component.providerRegistry
        _ = component.providerDetectionService
        _ = component.keepAwakeService
        _ = component.agentEnvironmentBuilder
        _ = component.claudeConfigStore
        _ = component.providerSetupService
        _ = component.contextWindowCache
        _ = component.claudeHookServer
        _ = component.defaultAgentsManager
        _ = component.agentsManager
        _ = component.conversationRuntimeStore
        _ = component.gitService
        _ = component.worktreeManager
        _ = component.fileListManager
        _ = component.diffWorkspaceStore
        _ = component.gitHubCLIService
        _ = component.gitHubService
        _ = component.skillsService
        _ = component.mcpService
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
