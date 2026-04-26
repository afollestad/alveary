import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testInterruptedTrailingErrorTokensDoNotNotify() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }

        let notificationManager = RecordingNotificationManager()
        let manager = DefaultAgentsManager(
            sessionManager: InMemorySessionManager(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            environmentBuilder: DefaultAgentEnvironmentBuilder(),
            providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            settingsService: makeSettings(),
            notificationManager: notificationManager,
            adapterFactory: { _ in InterruptedTokenAdapter() }
        )
        let conversationId = "conversation-interrupted-notification"
        let config = AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: executable.workingDirectory.path,
            permissionMode: nil,
            model: nil,
            effort: nil,
            initialPrompt: nil
        )

        defer {
            Task {
                await manager.kill(conversationId: conversationId)
            }
        }

        try await manager.spawn(id: conversationId, config: config, forkSession: false)
        try await manager.sendMessage("stop this", conversationId: conversationId)

        try await waitUntil("expected interrupted stop notification without trailing error notification") {
            manager.status(for: conversationId) == .idle &&
                notificationManager.handleEventCalls.count == 1
        }

        let recordedEvent = try XCTUnwrap(notificationManager.handleEventCalls.first)
        XCTAssertEqual(recordedEvent.conversationId, conversationId)
        XCTAssertEqual(recordedEvent.event, .stop(message: ConversationInterruption.displayMessage))
    }
}

private final class InterruptedTokenAdapter: AgentAdapter, @unchecked Sendable {
    let supportsBidirectionalStreaming = true
    let supportsMidTurnSteering = false

    func buildArgs(config: AgentConfig) -> [String] {
        []
    }

    func envOverrides(config: AgentConfig) -> [String: String] {
        [:]
    }

    func decode(_ json: [String: Any]) -> [ConversationEvent] {
        guard json["type"] as? String == "interrupted" else {
            return []
        }

        return [
            .stop(message: ConversationInterruption.displayMessage),
            .tokens(
                input: 1,
                output: 0,
                cacheRead: 0,
                isError: true,
                stopReason: ConversationInterruption.requestInterruptedByUserReason,
                durationMs: 5,
                costUsd: 0,
                permissionDenials: []
            )
        ]
    }

    func finalize() -> [ConversationEvent] {
        []
    }

    func sendMessage(_ message: String, to process: Process) throws {
        guard let stdin = process.standardInput as? Pipe else {
            throw AgentError.stdinClosed
        }

        let payload: [String: Any] = ["type": "interrupted"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try stdin.fileHandleForWriting.write(contentsOf: data + Data("\n".utf8))
    }

    func sessionFilePath(sessionId: String, cwd: String) -> String? {
        nil
    }

    func canResumeSession(sessionId: String, cwd: String) -> Bool {
        false
    }

    func sessionLaunch(sessionId: String, cwd: String, isResuming: Bool, forkSession: Bool) -> SessionLaunchDecision {
        SessionLaunchDecision(args: [], continuity: .preserved)
    }
}
