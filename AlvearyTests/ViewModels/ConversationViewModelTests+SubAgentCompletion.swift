import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testCodexSubAgentStartPersistsDeterministicAgentToolCallOnce() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let startEvent = codexSubAgentStartEvent(toolUseId: "spawn-1", description: "Review the diff")

        fixture.viewModel.handleEvent(startEvent)
        fixture.viewModel.handleEvent(startEvent)

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.type == "tool_call"
        }
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(
            record.id,
            ConversationViewModel.codexSubAgentStartRecordId(conversationId: fixture.conversation.id, toolUseId: "spawn-1")
        )
        XCTAssertEqual(record.toolId, "spawn-1")
        XCTAssertEqual(record.toolName, "Agent")
        XCTAssertEqual(record.toolInput, codexSubAgentInput(description: "Review the diff"))

        let agents = subAgents(in: fixture.viewModel.state.grouper)
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents.first?.id, "spawn-1")
        XCTAssertEqual(agents.first?.agentType, "codex")
        XCTAssertEqual(agents.first?.description, "Review the diff")
    }

    func testDuplicateCodexSubAgentStartAndCompletionStillAdvanceRuntimeCursor() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let generation = UUID()
        let startEvent = codexSubAgentStartEvent(toolUseId: "spawn-1", description: "Review the diff")
        let completionEvent = ConversationEvent.subAgentCompleted(
            toolUseId: "spawn-1",
            status: "completed",
            toolUses: 1,
            totalTokens: 200,
            durationMs: 300
        )
        fixture.viewModel.state.activeBufferGeneration = generation

        fixture.viewModel.state.lastObservedEventIndex = 1
        fixture.viewModel.handleEvent(startEvent)
        await fixture.viewModel.flushPendingSaveIfNeeded()

        fixture.viewModel.state.lastObservedEventIndex = 2
        fixture.viewModel.handleEvent(startEvent)
        await fixture.viewModel.flushPendingSaveIfNeeded()

        fixture.viewModel.state.lastObservedEventIndex = 3
        fixture.viewModel.handleEvent(completionEvent)
        await fixture.viewModel.flushPendingSaveIfNeeded()

        fixture.viewModel.state.lastObservedEventIndex = 4
        fixture.viewModel.handleEvent(completionEvent)
        await fixture.viewModel.flushPendingSaveIfNeeded()

        let calls = await fixture.agentsManager.markPersistedCalls()
        XCTAssertEqual(calls.last?.conversationId, fixture.conversation.id)
        XCTAssertEqual(calls.last?.generation, generation)
        XCTAssertEqual(calls.last?.index, 4)
        XCTAssertEqual(fixture.viewModel.state.lastPersistedEventIndex, 4)
        XCTAssertEqual(try fixture.records(type: "tool_call").count, 1)
        XCTAssertEqual(try fixture.records(type: ConversationEventRecord.subAgentCompletedType).count, 1)
    }

    func testCodexSubAgentStartAndCompletionRebuildVisibleSubAgentBlock() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")

        fixture.viewModel.handleEvent(codexSubAgentStartEvent(toolUseId: "spawn-1", description: "Review the diff"))
        fixture.viewModel.handleEvent(.subAgentCompleted(
            toolUseId: "spawn-1",
            status: "completed",
            toolUses: 1,
            totalTokens: 200,
            durationMs: 300
        ))

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).sorted { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }
        let grouper = ChatItemGrouper()
        grouper.update(events: records, forceFullRebuild: true)

        let agents = subAgents(in: grouper)
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents.first?.id, "spawn-1")
        XCTAssertTrue(agents.first?.isComplete == true)
        XCTAssertEqual(agents.first?.toolUseCount, 1)
        XCTAssertEqual(agents.first?.totalTokens, 200)
        XCTAssertEqual(agents.first?.durationMs, 300)
    }

    func testSubAgentCompletionPersistsHiddenMarkerOnce() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.subAgentCompleted(
            toolUseId: "agent-1",
            status: "completed",
            toolUses: 2,
            totalTokens: 300,
            durationMs: 400
        ))
        fixture.viewModel.handleEvent(.subAgentCompleted(
            toolUseId: "agent-1",
            status: "completed",
            toolUses: 2,
            totalTokens: 300,
            durationMs: 400
        ))

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.type == ConversationEventRecord.subAgentCompletedType
        }
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.id, "sub-agent-completed:\(fixture.conversation.id):agent-1")
        XCTAssertEqual(record.toolId, "agent-1")
        XCTAssertEqual(record.durationMs, 400)
        let content = try XCTUnwrap(record.content?.data(using: .utf8))
        let payload = try JSONDecoder().decode(SubAgentCompletionMarkerPayload.self, from: content)
        XCTAssertEqual(payload.status, "completed")
        XCTAssertEqual(payload.toolUses, 2)
        XCTAssertEqual(payload.totalTokens, 300)
    }

    private func codexSubAgentStartEvent(toolUseId: String, description: String) -> ConversationEvent {
        .toolCall(
            id: toolUseId,
            name: "Agent",
            input: codexSubAgentInput(description: description),
            parentToolUseId: nil,
            callerAgent: nil
        )
    }

    private func codexSubAgentInput(description: String) -> String {
        """
        {"codex_collab_tool":"spawnAgent","description":"\(description)","subagent_type":"codex"}
        """
    }

    private func subAgents(in grouper: ChatItemGrouper) -> [SubAgentEntry] {
        grouper.items.compactMap { item -> [SubAgentEntry]? in
            guard case .subAgentBlock(_, let agents) = item else {
                return nil
            }
            return agents
        }.flatMap { $0 }
    }
}
