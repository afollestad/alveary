import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitMarkPersistedUsesMappedRuntimeReplayCursor() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: RawThenMessageAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin",
            replayLimit: 1
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-runtime-cursor"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        try await waitUntil("expected first mapped AgentCLIKit event") {
            await manager.retainedEventCount(conversationId: conversationId) >= 1
        }
        try await Task.sleep(for: .milliseconds(100))
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)

        await manager.markPersisted(conversationId: conversationId, generation: generation, upTo: 1)
        try await Task.sleep(for: .milliseconds(100))
        try await manager.sendMessage("after", conversationId: conversationId)
        try await waitUntil("expected second mapped AgentCLIKit event") {
            await manager.retainedEventCount(conversationId: conversationId) >= 2
        }

        let replay = await fixture.runtime.subscribe(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
            afterIndex: nil
        )
        let replayedEvents = try await nextRuntimeEvents(
            from: replay.events,
            count: 2,
            description: "AgentCLIKit mapped replay events"
        )
        let messageTexts = replayedEvents.compactMap(Self.messageText)
        let hasRawOutput = replayedEvents.contains {
            if case .rawOutput = $0.event {
                return true
            }
            return false
        }

        XCTAssertFalse(hasRawOutput)
        XCTAssertEqual(messageTexts, ["first", "after"])
        await manager.kill(conversationId: conversationId)
    }

    private func nextRuntimeEvents(
        from stream: AsyncStream<AgentCLIKit.AgentEventEnvelope>,
        count: Int,
        description: String
    ) async throws -> [AgentCLIKit.AgentEventEnvelope] {
        try await withThrowingTaskGroup(of: [AgentCLIKit.AgentEventEnvelope].self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                var events: [AgentCLIKit.AgentEventEnvelope] = []
                while events.count < count {
                    if let event = await iterator.next() {
                        events.append(event)
                    } else {
                        break
                    }
                }
                return events
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw WaitTimeoutError(description: description)
            }
            defer { group.cancelAll() }
            let events = try await group.next() ?? []
            guard events.count == count else {
                throw WaitTimeoutError(description: description)
            }
            return events
        }
    }

    private static func messageText(from envelope: AgentCLIKit.AgentEventEnvelope) -> String? {
        guard case .message(let message) = envelope.event else {
            return nil
        }
        return message.text
    }
}
