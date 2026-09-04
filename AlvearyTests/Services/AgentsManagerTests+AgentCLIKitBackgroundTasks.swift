import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitSuspendRuntimeKeepsProcessWhileBackgroundTasksAreLive() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: BackgroundTaskAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-suspend-background-tasks"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)

        try await manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path)
        )
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }

        try await manager.sendMessage("tasks:2", conversationId: conversationId)
        try await waitUntil("expected the turn to end with two live background tasks") {
            guard let status = await fixture.runtime.status(conversationId: runtimeConversationId) else {
                return false
            }
            return !status.isTurnActive && status.liveBackgroundTaskCount == 2
        }
        try await waitUntil("expected live background tasks to keep the conversation busy") {
            manager.status(for: conversationId) == .busy &&
                manager.conversationState(for: conversationId).liveBackgroundTaskCount == 2
        }
        await manager.suspendRuntime(conversationId: conversationId)

        let isRunning = await manager.isRunning(conversationId: conversationId)
        XCTAssertTrue(isRunning)

        // Dropped tasks stay counted until their notification arrives, so drain both.
        for line in ["tasks:0", "done:task-0", "done:task-1"] {
            try await manager.sendMessage(line, conversationId: conversationId)
        }
        try await waitUntil("expected the runtime to settle idle with no live tasks") {
            manager.status(for: conversationId) == .idle &&
                manager.conversationState(for: conversationId).liveBackgroundTaskCount == 0
        }
        await manager.suspendRuntime(conversationId: conversationId)

        let isRunningAfterTasksEnded = await manager.isRunning(conversationId: conversationId)
        XCTAssertFalse(isRunningAfterTasksEnded)
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitClaudeActiveActivityMakesHiddenTurnVisible() async throws {
        let recorder = RecordingThreadActivityRecorder()
        let fixture = makeAgentCLIKitFixture(
            adapter: BackgroundTaskAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin",
            threadActivityRecorder: recorder
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-provider-initiated-turn-activity"

        try await manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path)
        )
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }

        try await manager.sendMessage("active:background-task:1", conversationId: conversationId, activityVisibility: .hidden)
        try await waitUntil("expected the provider-initiated turn to record a visible turn end") {
            recorder.visibleTurnEndedConversationIDs == [conversationId]
        }

        XCTAssertTrue(recorder.visibleOutboundConversationIDs.isEmpty)
        await manager.kill(conversationId: conversationId)
    }
}
