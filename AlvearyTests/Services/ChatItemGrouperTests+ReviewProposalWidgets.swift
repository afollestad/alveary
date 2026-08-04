import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testReviewProposalRendersAsAWidgetAndResolvesOnItsMarker() {
        let grouper = ChatItemGrouper()
        let call = reviewProposalCall()
        let result = reviewProposalResult()

        grouper.update(events: [call, result])
        let entry = grouper.items.first?.hostToolWidgetEntry
        XCTAssertEqual(entry?.reviewProposalID, "review-1")
        XCTAssertEqual(entry?.isUnresolvedReviewProposal, true)
        // Submitting always needs the user, so the tool result alone never settles this card.
        XCTAssertEqual(entry?.isSettledWithoutDecision, false)
        XCTAssertNil(entry?.openableTarget)

        grouper.update(events: [call, result, reviewOutcomeMarker()])
        let resolved = grouper.items.first?.hostToolWidgetEntry
        XCTAssertEqual(resolved?.outcome, .confirmed)
        // The user may confirm a verdict other than the one proposed, so the marker carries it.
        XCTAssertEqual(resolved?.outcomeTitle, "request_changes")
    }

    /// The grouper patches a rendered widget only when its parser returns content, so a parser
    /// that declines a landed result leaves the card spinning at "Finding pull requests…" while
    /// the answer lands in an ordinary message below it.
    func testAPullRequestListCardLandsEvenWhenItsResultCarriesNoRows() {
        let grouper = ChatItemGrouper()
        let call = ConversationEventRecord(
            id: "list-call",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.toolCallType,
            toolId: "tool-list",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.listToolName),
            toolInput: #"{"filter":"all"}"#
        )
        grouper.update(events: [call])
        guard case .pullRequestList(let running)? = grouper.items.first?.hostToolWidgetEntry?.content else {
            return XCTFail("Expected a pull request list widget")
        }
        XCTAssertEqual(running.status, .running)

        // Neither structured content nor the tool's own text shape.
        let unreadableResult = ConversationEventRecord(
            id: "list-result",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.toolResultType,
            toolId: "tool-list",
            toolOutput: "Something entirely unexpected."
        )
        grouper.update(events: [call, unreadableResult])

        guard case .pullRequestList(let landed)? = grouper.items.first?.hostToolWidgetEntry?.content else {
            return XCTFail("Expected a pull request list widget")
        }
        XCTAssertEqual(landed.status, .listedWithoutRows)
        XCTAssertEqual(grouper.items.first?.hostToolWidgetEntry?.isComplete, true)
    }

    func testAPullRequestListCardRendersARowPerResult() {
        let grouper = ChatItemGrouper()
        let call = ConversationEventRecord(
            id: "list-call",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.toolCallType,
            toolId: "tool-list",
            toolName: PullRequestHostToolCatalog.listToolName,
            toolInput: #"{"filter":"reviewing"}"#
        )
        let result = ConversationEventRecord(
            id: "list-result",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.toolResultType,
            toolId: "tool-list",
            toolOutput: """
            {"filter":"reviewing","pull_requests":[\
            {"number":7,"repository":"octo/alpha","status":"open","title":"One"},\
            {"number":9,"repository":"octo/beta","status":"merged","title":"Two"}],"total_count":2}
            """
        )

        grouper.update(events: [call, result])

        guard case .pullRequestList(let content)? = grouper.items.first?.hostToolWidgetEntry?.content else {
            return XCTFail("Expected a pull request list widget")
        }
        XCTAssertEqual(content.rows.map(\.identifier.displayKey), ["octo/alpha#7", "octo/beta#9"])
        // Each row opens its own pull request, so the card is not a single button.
        XCTAssertNil(grouper.items.first?.hostToolWidgetEntry?.openableTarget)
    }

    /// Scheduling and pull-request reviews both open confirmations. A keyless marker — what a
    /// plain-text-fallback provider leaves behind — must not resolve the other feature's card,
    /// or a review would report a decision the user never made.
    func testAKeylessSchedulingMarkerDoesNotResolveAReviewProposal() {
        let grouper = ChatItemGrouper()
        let reviewCall = reviewProposalCall()
        let reviewResult = reviewProposalResult()
        grouper.update(events: [reviewCall, reviewResult])
        XCTAssertEqual(grouper.items.first?.hostToolWidgetEntry?.isUnresolvedReviewProposal, true)

        let unrelatedMarker = ConversationEventRecord(
            id: "scheduling-outcome",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.hostToolOutcomeType,
            content: HostToolWidgetOutcomeMarker.content(for: .confirmed),
            toolId: "some-other-key",
            toolName: HostToolTranscriptCatalog.toolName(ScheduledTaskHostToolCatalog.proposeToolName)
        )
        grouper.update(events: [reviewCall, reviewResult, unrelatedMarker])

        XCTAssertNil(grouper.items.first?.hostToolWidgetEntry?.outcome)
    }

    /// The mirror of the case above: a review marker must not resolve a scheduling proposal.
    func testAKeylessReviewMarkerDoesNotResolveASchedulingProposal() {
        let grouper = ChatItemGrouper()
        let call = schedulingProposalCall()
        let result = schedulingProposalResult()
        grouper.update(events: [call, result])

        let reviewMarker = ConversationEventRecord(
            id: "review-outcome",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.hostToolOutcomeType,
            content: HostToolWidgetOutcomeMarker.content(for: .confirmed),
            toolId: "unmatched-review-key",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName)
        )
        grouper.update(events: [call, result, reviewMarker])

        XCTAssertNil(grouper.items.first?.hostToolWidgetEntry?.outcome)
    }

    /// A plain-text-fallback provider leaves the widget no proposal id, so its own feature's
    /// marker still has to reach it.
    func testAKeylessReviewMarkerResolvesAPlainTextReviewCard() {
        let grouper = ChatItemGrouper()
        let call = reviewProposalCall()
        let plainTextResult = ConversationEventRecord(
            id: "review-result",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.toolResultType,
            toolId: "tool-review",
            toolOutput: "Opened a review confirmation in Alveary for octo/alpha#7."
        )
        grouper.update(events: [call, plainTextResult])
        XCTAssertNil(grouper.items.first?.hostToolWidgetEntry?.outcomeKey)

        let marker = ConversationEventRecord(
            id: "review-outcome",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.hostToolOutcomeType,
            content: HostToolWidgetOutcomeMarker.content(for: .rejected),
            toolId: "review-1",
            toolName: PullRequestHostToolCatalog.proposeReviewToolName
        )
        grouper.update(events: [call, plainTextResult, marker])

        XCTAssertEqual(grouper.items.first?.hostToolWidgetEntry?.outcome, .rejected)
    }
}

private extension ChatItemGrouperTests {
    /// This file's own conversation id and scheduling fixtures: the companion holding the
    /// originals keeps them fileprivate.
    static var reviewWidgetConversationID: String { "conversation-widget" }

    func schedulingProposalCall() -> ConversationEventRecord {
        ConversationEventRecord(
            id: "sched-call",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.toolCallType,
            toolId: "tool-sched",
            toolName: HostToolTranscriptCatalog.toolName(ScheduledTaskHostToolCatalog.proposeToolName),
            toolInput: #"{"action":"create","title":"Daily hello","prompt":"Say hello.","schedule":{"kind":"daily","hour":8,"minute":0}}"#
        )
    }

    func schedulingProposalResult() -> ConversationEventRecord {
        ConversationEventRecord(
            id: "sched-result",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.toolResultType,
            toolId: "tool-sched",
            toolOutput: #"{"action":"create","message":"Opened.","proposal_id":"p-9","status":"pending_confirmation","title":"Daily hello"}"#
        )
    }

    func reviewProposalCall() -> ConversationEventRecord {
        ConversationEventRecord(
            id: "review-call",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.toolCallType,
            toolId: "tool-review",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName),
            toolInput: #"{"body":"Looks good.","event":"approve","url":"https://github.com/octo/alpha/pull/7"}"#
        )
    }

    func reviewProposalResult() -> ConversationEventRecord {
        ConversationEventRecord(
            id: "review-result",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.toolResultType,
            toolId: "tool-review",
            toolOutput: #"{"event":"approve","message":"Opened.","number":7,"proposal_id":"review-1","# +
                #""repository":"octo/alpha","status":"pending_confirmation"}"#
        )
    }

    func reviewOutcomeMarker() -> ConversationEventRecord {
        ConversationEventRecord(
            id: "review-outcome",
            conversationId: Self.reviewWidgetConversationID,
            type: ConversationEventRecord.hostToolOutcomeType,
            content: HostToolWidgetOutcomeMarker.content(for: .confirmed, title: "request_changes"),
            toolId: "review-1",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName)
        )
    }
}
