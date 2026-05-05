import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testDestroyRuntimeWaitsForExistingKillWithoutStartingSecondSessionRemoval() async throws {
        let conversationId = "conversation-destroy-after-kill"
        let manager = DefaultAgentsManager(
            sessionManager: InMemorySessionManager(),
            providerDetection: StubProviderDetectionService(resolvedPath: "/usr/bin/false"),
            environmentBuilder: DefaultAgentEnvironmentBuilder(),
            providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            settingsService: InMemorySettingsService(current: AppSettings()),
            keepAwakeService: RecordingKeepAwakeService(),
            notificationManager: StubNotificationManager(),
            adapterFactory: { _ in EchoAgentAdapter() }
        )

        await manager.seedPendingTeardownForTesting(conversationId: conversationId)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            await manager.clearPendingTeardownForTesting(conversationId: conversationId)
        }

        try await manager.destroyRuntime(conversationId: conversationId)

        // kill clears denied-tool bookkeeping. Preserving this value proves
        // destroyRuntime waited for the existing teardown instead of re-running kill.
        let deniedToolIDs = await manager.deniedToolUseIDsForTesting(conversationId: conversationId)
        XCTAssertEqual(deniedToolIDs, ["tool-use"])
    }
}

private extension DefaultAgentsManager {
    func seedPendingTeardownForTesting(conversationId: String) {
        pendingSessionRemovalIds.insert(conversationId)
        deniedToolUseIdsByConversation[conversationId] = ["tool-use"]
    }

    func clearPendingTeardownForTesting(conversationId: String) {
        pendingSessionRemovalIds.remove(conversationId)
    }

    func deniedToolUseIDsForTesting(conversationId: String) -> Set<String> {
        deniedToolUseIdsByConversation[conversationId] ?? []
    }
}
