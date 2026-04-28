import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testStartFreshSessionReplacesSessionIdentityWithoutForking() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }

        let adapter = RecordingLaunchAdapter()
        let sessionManager = InMemorySessionManager()
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            sessionManager: sessionManager,
            adapterFactory: { _ in adapter }
        )
        let conversationId = "conversation-fresh-session"
        let config = AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: executable.workingDirectory.path,
            permissionMode: "acceptEdits",
            model: "sonnet",
            effort: "high",
            initialPrompt: nil
        )

        defer {
            Task {
                await manager.kill(conversationId: conversationId)
            }
        }

        try await manager.spawn(id: conversationId, config: config, forkSession: false)
        let initialSessionId = await sessionManager.sessionId(for: conversationId)

        try await manager.startFreshSession(conversationId: conversationId, config: config)
        let freshSessionId = await sessionManager.sessionId(for: conversationId)

        let launchCalls = adapter.recordedSessionLaunchCalls
        XCTAssertEqual(launchCalls.count, 2)
        XCTAssertEqual(launchCalls.map(\.isResuming), [false, false])
        XCTAssertEqual(launchCalls.map(\.forkSession), [false, false])
        XCTAssertNotEqual(initialSessionId, freshSessionId)
        XCTAssertEqual(launchCalls.map(\.sessionId), [initialSessionId, freshSessionId])

        await manager.kill(conversationId: conversationId)
        try await waitUntil("expected fresh-session process teardown after kill") {
            let hasTrackedProcess = await manager.hasTrackedProcess(conversationId: conversationId)
            let isRunning = await manager.isRunning(conversationId: conversationId)
            return !hasTrackedProcess && !isRunning
        }
    }
}
