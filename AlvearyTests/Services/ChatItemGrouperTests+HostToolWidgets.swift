import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testHostSchedulingToolRendersAsAWidgetBlockAndPatchesOnItsResult() {
        let grouper = ChatItemGrouper()
        let call = proposalCall()
        let result = proposalResult()

        grouper.update(events: [call])
        XCTAssertEqual(grouper.items.count, 1)
        XCTAssertEqual(grouper.items.first?.hostToolWidgetEntry?.isComplete, false)

        grouper.update(events: [call, result])
        XCTAssertEqual(grouper.items.count, 1)
        let entry = grouper.items.first?.hostToolWidgetEntry
        XCTAssertEqual(entry?.isComplete, true)
        XCTAssertEqual(entry?.scheduledProposalID, "p-1")
        guard case .scheduledTaskProposal(let content)? = entry?.content else {
            return XCTFail("Expected a scheduled-task proposal widget")
        }
        XCTAssertEqual(content.status, .pendingConfirmation)
        XCTAssertEqual(content.proposedTitle, "Daily hello")
    }

    /// Guards against drift from the real provider payload: this is the verbatim
    /// tool name and serialized input Claude Code emits for a create proposal.
    func testRealWorldProposalPayloadRoutesToAWidget() {
        let grouper = ChatItemGrouper()
        let call = ConversationEventRecord(
            id: "real-call",
            conversationId: Self.widgetConversationID,
            type: ConversationEventRecord.toolCallType,
            toolId: "tool-real",
            toolName: "mcp__alveary_host__propose_scheduled_task",
            toolInput: #"{"action": "create", "title": "Daily hello", "prompt": "Say hello", "schedule": {"kind": "daily", "hour": 8, "minute": 0}}"#
        )

        grouper.update(events: [call])

        XCTAssertNotNil(grouper.items.first?.hostToolWidgetEntry)
    }

    /// Codex reports the host tool without the `mcp__alveary_host__` prefix, which is the
    /// exact shape that used to fall through to a generic tool row.
    func testBareHostToolNameStillRoutesToAWidget() {
        let grouper = ChatItemGrouper()
        let call = proposalCall()
        call.toolName = ScheduledTaskHostToolCatalog.proposeToolName

        grouper.update(events: [call])

        XCTAssertNotNil(grouper.items.first?.hostToolWidgetEntry)
    }

    func testHostSchedulingToolResultArrivingBeforeItsCallStillRendersComplete() {
        let grouper = ChatItemGrouper()

        grouper.update(events: [proposalResult(), proposalCall()])

        XCTAssertEqual(grouper.items.count, 1)
        XCTAssertEqual(grouper.items.first?.hostToolWidgetEntry?.isComplete, true)
    }

    func testOutcomeMarkerResolvesItsWidgetInEitherArrivalOrder() {
        let afterResult = ChatItemGrouper()
        afterResult.update(events: [proposalCall(), proposalResult(), outcomeMarker()])
        XCTAssertEqual(afterResult.items.first?.hostToolWidgetEntry?.outcome, .confirmed)

        let beforeCall = ChatItemGrouper()
        beforeCall.update(events: [outcomeMarker(), proposalCall(), proposalResult()])
        XCTAssertEqual(beforeCall.items.first?.hostToolWidgetEntry?.outcome, .confirmed)
    }

    func testOutcomeMarkerResolvesEveryWidgetSharingItsProposal() {
        let grouper = ChatItemGrouper()
        let retryCall = proposalCall()
        retryCall.id = "widget-call-retry"
        retryCall.toolId = "tool-widget-retry"
        let retryResult = proposalResult()
        retryResult.id = "widget-result-retry"
        retryResult.toolId = "tool-widget-retry"

        // An exact tool retry returns the same proposal under a second tool id.
        grouper.update(events: [proposalCall(), proposalResult(), retryCall, retryResult, outcomeMarker()])

        let outcomes = grouper.items.compactMap(\.hostToolWidgetEntry).map(\.outcome)
        XCTAssertEqual(outcomes, [.confirmed, .confirmed])
    }

    /// Without a proposal id in the result, the marker resolves the newest unresolved
    /// proposal widget — the grouper is per-conversation and holds one at a time.
    func testOutcomeMarkerResolvesAKeylessWidgetForProvidersWithoutStructuredOutput() {
        let grouper = ChatItemGrouper()
        let result = proposalResult()
        result.toolOutput = "Opened a scheduling proposal for confirmation."

        grouper.update(events: [proposalCall(), result, outcomeMarker()])

        let entry = grouper.items.first?.hostToolWidgetEntry
        XCTAssertNil(entry?.outcomeKey)
        XCTAssertEqual(entry?.outcome, .confirmed)
    }

    /// An immediate action writes its marker between the call and the result, and a
    /// plain-text-fallback provider gives neither event a correlation key. The keyless
    /// marker must adopt the still-running widget, and the result patch must not drop
    /// the outcome it attached.
    func testKeylessMarkerBetweenCallAndResultResolvesAnImmediateAction() throws {
        let grouper = ChatItemGrouper()

        grouper.update(events: [pauseCall(), immediateOutcomeMarker(), pausePlainTextResult()])

        let entry = try XCTUnwrap(grouper.items.first?.hostToolWidgetEntry)
        XCTAssertTrue(entry.isComplete)
        XCTAssertEqual(entry.outcome, .confirmed)
        XCTAssertEqual(entry.outcomeDefinitionID, "task-1")
        XCTAssertEqual(entry.outcomeTitle, "Nightly audit")
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "Scheduled task paused: Nightly audit")
    }

    /// A plain-text immediate-action result parses as applied before its marker lands.
    /// The late marker must still pair with that widget — never with an unrelated
    /// pending proposal that happens to share the conversation.
    func testKeylessMarkerAfterAppliedResultSkipsAnUnrelatedPendingProposal() throws {
        let grouper = ChatItemGrouper()

        grouper.update(events: [
            proposalCall(), proposalResult(),
            pauseCall(), pausePlainTextResult(), immediateOutcomeMarker()
        ])

        let entries = grouper.items.compactMap(\.hostToolWidgetEntry)
        XCTAssertEqual(entries.count, 2)
        let pendingCreate = try XCTUnwrap(entries.first)
        XCTAssertNil(pendingCreate.outcome, "The pending create proposal must stay unresolved")
        let applied = try XCTUnwrap(entries.last)
        XCTAssertEqual(applied.outcome, .confirmed)
        XCTAssertEqual(applied.outcomeTitle, "Nightly audit")
    }

    /// A proposal's keyed marker must resolve the pending proposal, never a running
    /// immediate action that happens to share the conversation — proposal rejections
    /// carry no definition id, so they cannot pair with a marker-awaiting widget.
    func testProposalRejectionMarkerSkipsARunningImmediateAction() throws {
        let grouper = ChatItemGrouper()
        let pendingCreateResult = proposalResult()
        pendingCreateResult.toolOutput = "Opened a scheduling proposal for confirmation."
        let rejectMarker = outcomeMarker()
        rejectMarker.content = HostToolWidgetOutcomeMarker.content(for: .rejected)

        grouper.update(events: [
            proposalCall(), pendingCreateResult,
            pauseCall(), pausePlainTextResult(), rejectMarker
        ])

        let entries = grouper.items.compactMap(\.hostToolWidgetEntry)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.outcome, .rejected, "The pending proposal takes the rejection")
        XCTAssertNil(entries.last?.outcome, "The running pause keeps waiting for its own marker")
    }

    /// Two immediate actions in one turn pair with their markers oldest-first.
    func testKeylessMarkersPairWithParallelImmediateActionsInOrder() throws {
        let grouper = ChatItemGrouper()
        let secondCall = pauseCall()
        secondCall.id = "resume-call"
        secondCall.toolId = "tool-resume"
        secondCall.toolInput = #"{"action":"resume","task_id":"task-2","revision":4}"#
        let secondResult = pausePlainTextResult()
        secondResult.id = "resume-result"
        secondResult.toolId = "tool-resume"
        secondResult.toolOutput = "Resumed Weekly digest. Future occurrences continue from now."
        let secondMarker = immediateOutcomeMarker()
        secondMarker.id = "resume-outcome"
        secondMarker.toolId = "dedup-key-2"
        secondMarker.content = HostToolWidgetOutcomeMarker.content(
            for: .confirmed,
            definitionID: "task-2",
            title: "Weekly digest"
        )

        grouper.update(events: [
            pauseCall(), pausePlainTextResult(),
            secondCall, immediateOutcomeMarker(), secondResult, secondMarker
        ])

        let entries = grouper.items.compactMap(\.hostToolWidgetEntry)
        XCTAssertEqual(entries.map(\.outcomeTitle), ["Nightly audit", "Weekly digest"])
        XCTAssertEqual(entries.map(\.outcomeDefinitionID), ["task-1", "task-2"])
    }

    func testOutcomeMarkerNeverRendersItsOwnRow() {
        let grouper = ChatItemGrouper()
        grouper.update(events: [outcomeMarker()])
        XCTAssertTrue(grouper.items.isEmpty)
    }

    func testNestedHostToolCallKeepsTheGenericToolRow() {
        let grouper = ChatItemGrouper()
        let call = proposalCall()
        call.parentToolUseId = "parent-agent"

        grouper.update(events: [call])

        XCTAssertNil(grouper.items.first?.hostToolWidgetEntry)
    }

    func testUnreadableHostToolInputFallsBackToTheGenericToolRow() {
        let grouper = ChatItemGrouper()
        let call = proposalCall()
        call.toolInput = "not json"

        grouper.update(events: [call])

        XCTAssertNil(grouper.items.first?.hostToolWidgetEntry)
        XCTAssertEqual(grouper.items.count, 1)
    }

    func testInterruptedTurnTerminalizesAPendingWidget() {
        let grouper = ChatItemGrouper()
        let userMessage = ConversationEventRecord(
            id: "user",
            conversationId: Self.widgetConversationID,
            type: ConversationEventRecord.messageType,
            role: ConversationEventRecord.userRole,
            content: "Schedule it"
        )

        grouper.update(events: [userMessage, proposalCall()])
        grouper.markIncompleteTranscriptActivityInterrupted()

        let entry = grouper.items.last?.hostToolWidgetEntry
        XCTAssertEqual(entry?.isInterrupted, true)
        XCTAssertEqual(entry?.isComplete, true)
    }
}

private extension ChatItemGrouperTests {
    static let widgetConversationID = "conversation-widget"

    func proposalCall() -> ConversationEventRecord {
        ConversationEventRecord(
            id: "widget-call",
            conversationId: Self.widgetConversationID,
            type: ConversationEventRecord.toolCallType,
            toolId: "tool-widget",
            toolName: HostToolTranscriptCatalog.toolName(ScheduledTaskHostToolCatalog.proposeToolName),
            toolInput: #"{"action":"create","title":"Daily hello","prompt":"Say hello.","schedule":{"kind":"daily","hour":8,"minute":0}}"#
        )
    }

    func proposalResult() -> ConversationEventRecord {
        ConversationEventRecord(
            id: "widget-result",
            conversationId: Self.widgetConversationID,
            type: ConversationEventRecord.toolResultType,
            toolId: "tool-widget",
            toolOutput: #"{"action":"create","message":"Opened.","proposal_id":"p-1","status":"pending_confirmation","title":"Daily hello"}"#
        )
    }

    func outcomeMarker() -> ConversationEventRecord {
        ConversationEventRecord(
            id: "widget-outcome",
            conversationId: Self.widgetConversationID,
            type: ConversationEventRecord.hostToolOutcomeType,
            content: HostToolWidgetOutcomeMarker.content(for: .confirmed),
            toolId: "p-1",
            toolName: HostToolTranscriptCatalog.toolName(ScheduledTaskHostToolCatalog.proposeToolName)
        )
    }

    func pauseCall() -> ConversationEventRecord {
        ConversationEventRecord(
            id: "pause-call",
            conversationId: Self.widgetConversationID,
            type: ConversationEventRecord.toolCallType,
            toolId: "tool-pause",
            toolName: ScheduledTaskHostToolCatalog.proposeToolName,
            toolInput: #"{"action":"pause","task_id":"task-1","revision":3}"#
        )
    }

    func pausePlainTextResult() -> ConversationEventRecord {
        ConversationEventRecord(
            id: "pause-result",
            conversationId: Self.widgetConversationID,
            type: ConversationEventRecord.toolResultType,
            toolId: "tool-pause",
            toolOutput: "Paused Nightly audit. Future occurrences stop until it is resumed."
        )
    }

    func immediateOutcomeMarker() -> ConversationEventRecord {
        ConversationEventRecord(
            id: "pause-outcome",
            conversationId: Self.widgetConversationID,
            type: ConversationEventRecord.hostToolOutcomeType,
            content: HostToolWidgetOutcomeMarker.content(
                for: .confirmed,
                definitionID: "task-1",
                title: "Nightly audit"
            ),
            toolId: "dedup-key-1",
            toolName: ScheduledTaskHostToolCatalog.proposeToolName
        )
    }
}
