import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitVisibleSendRecordsThreadActivity() async throws {
        let recorder = RecordingThreadActivityRecorder()
        let fixture = makeAgentCLIKitFixture(
            adapter: TurnStatusAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin",
            threadActivityRecorder: recorder
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-visible-send-activity"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }

        try await manager.sendMessage("start", conversationId: conversationId)

        XCTAssertEqual(recorder.visibleOutboundConversationIDs, [conversationId])
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitHiddenSendDoesNotRecordVisibleThreadActivity() async throws {
        let recorder = RecordingThreadActivityRecorder()
        let fixture = makeAgentCLIKitFixture(
            adapter: TurnStatusAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin",
            threadActivityRecorder: recorder
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-hidden-send-activity"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }

        try await manager.sendMessage("start", conversationId: conversationId, activityVisibility: .hidden)

        XCTAssertTrue(recorder.visibleOutboundConversationIDs.isEmpty)
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitTerminalTurnEndRecordsThreadActivityOnce() async throws {
        let recorder = RecordingThreadActivityRecorder()
        let fixture = makeAgentCLIKitFixture(
            adapter: TurnStatusAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin",
            threadActivityRecorder: recorder
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-terminal-turn-activity"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }

        try await manager.sendMessage("start", conversationId: conversationId)
        try await waitUntil("expected AgentCLIKit runtime to keep the turn active") {
            guard let status = await fixture.runtime.status(conversationId: runtimeConversationId) else {
                return false
            }
            return status.lastEventIndex >= 2 && status.isTurnActive
        }

        try await manager.sendMessage("finish", conversationId: conversationId)
        try await waitUntil("expected terminal activity record") {
            recorder.visibleTurnEndedConversationIDs == [conversationId]
        }

        XCTAssertEqual(recorder.visibleOutboundConversationIDs, [conversationId, conversationId])
        await manager.kill(conversationId: conversationId)
    }
}
