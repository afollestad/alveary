import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testParallelSubAgentApprovalRebuildUpdatesExistingBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let events = parallelSubAgentApprovalEvents(conversationId: conversationId)
        let eventsThroughApproval = events.prefix(5)

        grouper.update(events: Array(eventsThroughApproval), forceFullRebuild: true)
        for event in events.dropFirst(eventsThroughApproval.count) {
            grouper.append(event: event)
        }

        assertSingleCompletedParallelSubAgentBlock(in: grouper)
    }

    func testParallelSubAgentApprovalStreamingAppendUpdatesExistingBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        for event in parallelSubAgentApprovalEvents(conversationId: conversationId) {
            grouper.append(event: event)
        }

        assertSingleCompletedParallelSubAgentBlock(in: grouper)
    }

    func testAsyncSubAgentCompletionResultsPatchExpandedResultContentAfterApprovalInterleaves() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.append(event: agentCall(
            id: "agent-call-1",
            conversationId: conversationId,
            toolId: "agent-1",
            description: "Count images"
        ))
        grouper.append(event: agentCall(
            id: "agent-call-2",
            conversationId: conversationId,
            toolId: "agent-2",
            description: "Audit scripts"
        ))
        grouper.append(event: secondAgentApproval(conversationId: conversationId))
        grouper.handleSubAgentControl(.subAgentCompleted(
            toolUseId: "agent-1",
            status: "completed",
            toolUses: 1,
            totalTokens: 100,
            durationMs: 200
        ))
        grouper.append(event: agentResult(id: "agent-result-1", conversationId: conversationId, toolId: "agent-1", output: "Image result"))
        grouper.handleSubAgentControl(.subAgentCompleted(
            toolUseId: "agent-2",
            status: "completed",
            toolUses: 2,
            totalTokens: 300,
            durationMs: 400
        ))
        grouper.append(event: agentResult(id: "agent-result-2", conversationId: conversationId, toolId: "agent-2", output: "Audit result"))

        let subAgentBlocks = grouper.items.compactMap { item -> [SubAgentEntry]? in
            guard case .subAgentBlock(_, let agents) = item else {
                return nil
            }
            return agents
        }
        XCTAssertEqual(subAgentBlocks.count, 1)
        let agents = subAgentBlocks.first ?? []
        XCTAssertEqual(agents.map(\.id), ["agent-1", "agent-2"])
        XCTAssertTrue(agents.allSatisfy(\.isComplete))
        XCTAssertEqual(agents.first(where: { $0.id == "agent-1" })?.result, "Image result")
        XCTAssertEqual(agents.first(where: { $0.id == "agent-2" })?.result, "Audit result")
        XCTAssertEqual(agents.first(where: { $0.id == "agent-1" })?.toolUseCount, 1)
        XCTAssertEqual(agents.first(where: { $0.id == "agent-2" })?.toolUseCount, 2)
    }

    func testSubAgentResultBeforeAgentCallCompletesLaterAgentRow() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.append(event: agentResult(
            id: "agent-result-1",
            conversationId: conversationId,
            toolId: "agent-1",
            output: "Early result"
        ))
        grouper.append(event: agentCall(
            id: "agent-call-1",
            conversationId: conversationId,
            toolId: "agent-1",
            description: "Count HTML"
        ))

        let agent = onlySubAgent(in: grouper)
        XCTAssertEqual(agent?.id, "agent-1")
        XCTAssertTrue(agent?.isComplete == true)
        XCTAssertEqual(agent?.result, "Early result")
    }

    func testSubAgentCompletionBeforeAgentCallAppliesMetricsToLaterAgentRow() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.handleSubAgentControl(.subAgentCompleted(
            toolUseId: "agent-1",
            status: "completed",
            toolUses: 3,
            totalTokens: 400,
            durationMs: 500
        ))
        grouper.append(event: agentCall(
            id: "agent-call-1",
            conversationId: conversationId,
            toolId: "agent-1",
            description: "Count HTML"
        ))

        let agent = onlySubAgent(in: grouper)
        XCTAssertEqual(agent?.id, "agent-1")
        XCTAssertTrue(agent?.isComplete == true)
        XCTAssertEqual(agent?.toolUseCount, 3)
        XCTAssertEqual(agent?.totalTokens, 400)
        XCTAssertEqual(agent?.durationMs, 500)
    }

    func testDuplicateEarlySubAgentResultsDoNotDuplicateRowsOrRegressStatus() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.append(event: agentResult(
            id: "agent-result-1a",
            conversationId: conversationId,
            toolId: "agent-1",
            output: "First result"
        ))
        grouper.append(event: agentResult(
            id: "agent-result-1b",
            conversationId: conversationId,
            toolId: "agent-1",
            output: "Second result"
        ))
        grouper.append(event: agentCall(
            id: "agent-call-1",
            conversationId: conversationId,
            toolId: "agent-1",
            description: "Count HTML"
        ))
        grouper.append(event: agentResult(
            id: "agent-result-1c",
            conversationId: conversationId,
            toolId: "agent-1",
            output: "Final result"
        ))

        let agents = subAgents(in: grouper)
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents.first?.id, "agent-1")
        XCTAssertTrue(agents.first?.isComplete == true)
        XCTAssertEqual(agents.first?.result, "Final result")
    }

    func testInterleavedApprovalDoesNotDropEarlyCompletedSubAgent() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.append(event: agentResult(
            id: "agent-result-1",
            conversationId: conversationId,
            toolId: "agent-1",
            output: "Early result"
        ))
        grouper.append(event: secondAgentApproval(conversationId: conversationId))
        grouper.append(event: agentCall(
            id: "agent-call-1",
            conversationId: conversationId,
            toolId: "agent-1",
            description: "Count HTML"
        ))
        grouper.append(event: agentCall(
            id: "agent-call-2",
            conversationId: conversationId,
            toolId: "agent-2",
            description: "Audit CSS"
        ))

        let agents = subAgents(in: grouper)
        XCTAssertEqual(agents.map(\.id), ["agent-1", "agent-2"])
        XCTAssertTrue(agents.first(where: { $0.id == "agent-1" })?.isComplete == true)
        XCTAssertEqual(agents.first(where: { $0.id == "agent-1" })?.result, "Early result")
        XCTAssertEqual(toolApprovalItemCount(in: grouper.items), 1)
    }

    func testPersistedEarlySubAgentResultRebuildsCompletedAgentRow() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let events = [
            agentResult(
                id: "agent-result-1",
                conversationId: conversationId,
                toolId: "agent-1",
                output: "Persisted result"
            ),
            agentCall(
                id: "agent-call-1",
                conversationId: conversationId,
                toolId: "agent-1",
                description: "Count HTML"
            )
        ]

        grouper.update(events: events, forceFullRebuild: true)

        let agent = onlySubAgent(in: grouper)
        XCTAssertEqual(agent?.id, "agent-1")
        XCTAssertTrue(agent?.isComplete == true)
        XCTAssertEqual(agent?.result, "Persisted result")
    }

    func testConsumedEarlySubAgentResultDoesNotApplyToUnrelatedAgent() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.append(event: agentResult(
            id: "agent-result-1",
            conversationId: conversationId,
            toolId: "agent-1",
            output: "Early result"
        ))
        grouper.append(event: agentCall(
            id: "agent-call-1",
            conversationId: conversationId,
            toolId: "agent-1",
            description: "Count HTML"
        ))
        grouper.append(event: agentCall(
            id: "agent-call-2",
            conversationId: conversationId,
            toolId: "agent-2",
            description: "Audit CSS"
        ))

        let agents = subAgents(in: grouper)
        XCTAssertTrue(agents.first(where: { $0.id == "agent-1" })?.isComplete == true)
        XCTAssertEqual(agents.first(where: { $0.id == "agent-1" })?.result, "Early result")
        XCTAssertFalse(agents.first(where: { $0.id == "agent-2" })?.isComplete == true)
        XCTAssertNil(agents.first(where: { $0.id == "agent-2" })?.result)
    }

    private func assertSingleCompletedParallelSubAgentBlock(in grouper: ChatItemGrouper) {
        let subAgentBlocks = grouper.items.compactMap { item -> [SubAgentEntry]? in
            guard case .subAgentBlock(_, let agents) = item else {
                return nil
            }
            return agents
        }
        XCTAssertEqual(subAgentBlocks.count, 1)
        guard let agents = subAgentBlocks.first else {
            return XCTFail("Expected one sub-agent block")
        }
        XCTAssertEqual(agents.map(\.id), ["agent-1", "agent-2"])
        XCTAssertTrue(agents.allSatisfy(\.isComplete))

        guard let secondAgent = agents.first(where: { $0.id == "agent-2" }) else {
            return XCTFail("Expected the second agent to stay in the grouped block")
        }
        XCTAssertEqual(secondAgent.tools.count, 1)
        XCTAssertEqual(secondAgent.tools.first?.id, "agent-2-bash")
        XCTAssertTrue(secondAgent.tools.first?.isComplete == true)
        XCTAssertEqual(toolApprovalItemCount(in: grouper.items), 1)
    }

    private func onlySubAgent(in grouper: ChatItemGrouper) -> SubAgentEntry? {
        let agents = subAgents(in: grouper)
        XCTAssertEqual(agents.count, 1)
        return agents.first
    }

    private func subAgents(in grouper: ChatItemGrouper) -> [SubAgentEntry] {
        grouper.items.compactMap { item -> [SubAgentEntry]? in
            guard case .subAgentBlock(_, let agents) = item else {
                return nil
            }
            return agents
        }.flatMap { $0 }
    }

    private func parallelSubAgentApprovalEvents(conversationId: String) -> [ConversationEventRecord] {
        [
            agentCall(
                id: "agent-call-1",
                conversationId: conversationId,
                toolId: "agent-1",
                description: "Count portfolio images"
            ),
            agentCall(
                id: "agent-call-2",
                conversationId: conversationId,
                toolId: "agent-2",
                description: "List ai-rules skills"
            ),
            agentResult(id: "agent-result-1", conversationId: conversationId, toolId: "agent-1", output: "Found 12 images"),
            secondAgentToolCall(conversationId: conversationId),
            secondAgentApproval(conversationId: conversationId),
            secondAgentToolResult(conversationId: conversationId),
            agentResult(id: "agent-result-2", conversationId: conversationId, toolId: "agent-2", output: "Listed 1 skill")
        ]
    }

    private func agentCall(
        id: String,
        conversationId: String,
        toolId: String,
        description: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_call",
            toolId: toolId,
            toolName: "Agent",
            toolInput: "{\"description\":\"\(description)\",\"subagent_type\":\"explorer\"}"
        )
    }

    private func agentResult(
        id: String,
        conversationId: String,
        toolId: String,
        output: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_result",
            toolId: toolId,
            toolOutput: output
        )
    }

    private func secondAgentToolCall(conversationId: String) -> ConversationEventRecord {
        ConversationEventRecord(
            id: "agent-2-bash-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "agent-2-bash",
            toolName: "Bash",
            toolInput: "{\"command\":\"find ai-rules/skills -maxdepth 2 -type f\"}",
            parentToolUseId: "agent-2"
        )
    }

    private func secondAgentApproval(conversationId: String) -> ConversationEventRecord {
        ConversationEventRecord(
            id: "approval-1",
            conversationId: conversationId,
            type: "tool_approval",
            content: "session-1",
            toolId: "agent-2-bash",
            toolName: "Bash",
            toolInput: "{\"command\":\"find ai-rules/skills -maxdepth 2 -type f\"}"
        )
    }

    private func secondAgentToolResult(conversationId: String) -> ConversationEventRecord {
        ConversationEventRecord(
            id: "agent-2-bash-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "agent-2-bash",
            toolOutput: "watermark-portfolio-images/SKILL.md",
            parentToolUseId: "agent-2"
        )
    }

    private func toolApprovalItemCount(in items: [ChatItem]) -> Int {
        items.filter { item in
            if case .toolApproval = item {
                return true
            }
            return false
        }.count
    }

}
