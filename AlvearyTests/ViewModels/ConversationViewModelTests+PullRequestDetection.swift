import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    // MARK: - Behavior matrix

    func testPromptIsRecordedWhenAutomaticLinkingIsOff() throws {
        let fixture = try makeDetectionFixture()

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "Opened https://github.com/octo/alpha/pull/42")
        )

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts.map(\.identifier), [identifier(number: 42)])
        XCTAssertEqual(fixture.thread.pullRequestScanWatermark, Date(timeIntervalSince1970: 100))
    }

    func testAutomaticLinkingPostsARequestInsteadOfPrompting() throws {
        let fixture = try makeDetectionFixture(automaticallyLinkPullRequests: true)
        let observer = PullRequestLinkRequestObserver()

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "Opened https://github.com/octo/alpha/pull/42")
        )

        XCTAssertEqual(observer.requests.map(\.identifier), [identifier(number: 42)])
        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
    }

    /// A `list_involved_prs` answer names every pull request the user touches; without this the
    /// transcript stacked one question per row under the bubble.
    func testAMessageListingManyPullRequestsPromptsForNone() throws {
        let fixture = try makeDetectionFixture()
        let listing = (1...8)
            .map { "https://github.com/octo/alpha/pull/\($0)" }
            .joined(separator: "\n")

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: listing)
        )

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
        // Scanned and deliberately empty, so the message is fenced rather than re-asked later.
        XCTAssertEqual(fixture.thread.pullRequestScanWatermark, Date(timeIntervalSince1970: 100))
    }

    /// Automatic linking is the same judgement: a listing is not eight pull requests the user
    /// wants bookmarked on this thread.
    func testAMessageListingManyPullRequestsLinksNoneAutomatically() throws {
        let fixture = try makeDetectionFixture(automaticallyLinkPullRequests: true)
        let observer = PullRequestLinkRequestObserver()
        let listing = (1...8)
            .map { "https://github.com/octo/alpha/pull/\($0)" }
            .joined(separator: "\n")

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: listing)
        )

        XCTAssertTrue(observer.requests.isEmpty)
    }

    func testAMessageDiscussingAFewPullRequestsStillPrompts() throws {
        let fixture = try makeDetectionFixture()
        let discussion = (1...ConversationViewModel.maximumDetectedPullRequestsPerMessage)
            .map { "https://github.com/octo/alpha/pull/\($0)" }
            .joined(separator: " and ")

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: discussion)
        )

        XCTAssertEqual(
            fixture.thread.pendingPullRequestLinkPrompts.count,
            ConversationViewModel.maximumDetectedPullRequestsPerMessage
        )
    }

    func testSuppressedPromptsWithoutAutomaticLinkingDoNothing() throws {
        let fixture = try makeDetectionFixture(suppressPullRequestLinkPrompts: true)
        let observer = PullRequestLinkRequestObserver()

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "Opened https://github.com/octo/alpha/pull/42")
        )

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
        XCTAssertEqual(observer.requests.count, 0)
        XCTAssertNil(fixture.thread.pullRequestScanWatermark)
    }

    /// Suppression silences the question, not the setting: with auto-linking on the
    /// link still lands.
    func testSuppressedPromptsStillAutoLink() throws {
        let fixture = try makeDetectionFixture(
            automaticallyLinkPullRequests: true,
            suppressPullRequestLinkPrompts: true
        )
        let observer = PullRequestLinkRequestObserver()

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "Opened https://github.com/octo/alpha/pull/42")
        )

        XCTAssertEqual(observer.requests.map(\.identifier), [identifier(number: 42)])
    }

    // MARK: - Gates

    func testDisabledPullRequestIntegrationDetectsNothing() throws {
        let fixture = try makeDetectionFixture(pullRequestsEnabled: false)

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "Opened https://github.com/octo/alpha/pull/42")
        )

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
    }

    /// A draft has no sidebar row and no link owner yet, so the first send rescans
    /// after materialization instead.
    func testDraftThreadDetectsNothingAndLeavesTheWatermarkUnset() throws {
        let fixture = try makeDetectionFixture(isDraft: true)

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "Opened https://github.com/octo/alpha/pull/42")
        )

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
        XCTAssertNil(fixture.thread.pullRequestScanWatermark)
    }

    /// Sub-agent messages render inside their sub-agent block, so a prompt anchored
    /// to one would have no bubble to sit under.
    func testSubAgentMessagesAreSkipped() throws {
        let fixture = try makeDetectionFixture()
        let record = try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42")
        record.parentToolUseId = "tool-1"

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(record)

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
    }

    func testNonMessageRecordsAreSkipped() throws {
        let fixture = try makeDetectionFixture()
        let record = ConversationEventRecord(
            conversationId: fixture.conversation.id,
            type: ConversationEventRecord.toolCallType,
            role: ConversationEventRecord.assistantRole,
            content: "https://github.com/octo/alpha/pull/42",
            timestamp: Date(timeIntervalSince1970: 100),
            conversation: fixture.conversation
        )
        fixture.context.insert(record)

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(record)

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
    }

    // MARK: - Watermark

    func testWatermarkFencesAReplayOfTheSameMessage() throws {
        let fixture = try makeDetectionFixture()
        let record = try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42")
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(record)
        fixture.thread.pendingPullRequestLinkPrompts = []

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(record)

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
    }

    /// Advancing on every message would dirty the thread row constantly; a message
    /// with no links leaves the fence where it was.
    func testWatermarkAdvancesOnlyForMessagesThatCarryLinks() throws {
        let fixture = try makeDetectionFixture()

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "No links here.", at: 100)
        )
        XCTAssertNil(fixture.thread.pullRequestScanWatermark)

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42", at: 200)
        )
        XCTAssertEqual(fixture.thread.pullRequestScanWatermark, Date(timeIntervalSince1970: 200))
    }

    func testMessagesOlderThanTheWatermarkAreSkipped() throws {
        let fixture = try makeDetectionFixture()
        fixture.thread.pullRequestScanWatermark = Date(timeIntervalSince1970: 500)

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42", at: 100)
        )

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
    }

    // MARK: - Deduplication

    func testAlreadyLinkedPullRequestsDoNotPrompt() throws {
        let fixture = try makeDetectionFixture()
        fixture.thread.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 42), linkedAt: Date(timeIntervalSince1970: 1))
        ]

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42")
        )

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
    }

    func testAPullRequestAlreadyPendingDoesNotPromptTwice() throws {
        let fixture = try makeDetectionFixture()
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42", at: 100)
        )

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "again https://github.com/octo/alpha/pull/42", at: 200)
        )

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts.count, 1)
    }

    /// A question left over from before auto-linking was turned on — including one
    /// hidden by `Never` — must not block the link forever.
    func testAPendingPromptDoesNotBlockAutomaticLinking() throws {
        let fixture = try makeDetectionFixture()
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42", at: 100)
        )
        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts.count, 1)
        let observer = PullRequestLinkRequestObserver()
        fixture.settingsService.update { $0.automaticallyLinkPullRequests = true }

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "still https://github.com/octo/alpha/pull/42", at: 200)
        )

        XCTAssertEqual(observer.requests.map(\.identifier), [identifier(number: 42)])
    }

    func testEveryPullRequestInOneMessageGetsItsOwnPrompt() throws {
        let fixture = try makeDetectionFixture()

        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(
                in: fixture,
                content: "https://github.com/octo/alpha/pull/42 and https://github.com/octo/beta/pull/9"
            )
        )

        XCTAssertEqual(
            fixture.thread.pendingPullRequestLinkPrompts.map(\.identifier),
            [identifier(number: 42), PullRequestIdentifier(owner: "octo", repo: "beta", number: 9)]
        )
    }

    // MARK: - Answering

    func testAcceptingAlwaysTurnsAutomaticLinkingOnAndRequestsTheLink() throws {
        let fixture = try makeDetectionFixture()
        let observer = PullRequestLinkRequestObserver()
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42")
        )
        let prompt = try XCTUnwrap(fixture.thread.pendingPullRequestLinkPrompts.first)

        fixture.viewModel.acceptPullRequestLinkPrompt(prompt, always: true)

        XCTAssertTrue(fixture.settingsService.current.automaticallyLinkPullRequests)
        XCTAssertEqual(observer.requests.map(\.identifier), [identifier(number: 42)])
        // The entry clears when the link lands, so a failed link stays answerable.
        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts.count, 1)
    }

    func testAcceptingOnceChangesNoSettings() throws {
        let fixture = try makeDetectionFixture()
        let observer = PullRequestLinkRequestObserver()
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42")
        )
        let prompt = try XCTUnwrap(fixture.thread.pendingPullRequestLinkPrompts.first)

        fixture.viewModel.acceptPullRequestLinkPrompt(prompt, always: false)

        XCTAssertFalse(fixture.settingsService.current.automaticallyLinkPullRequests)
        XCTAssertEqual(observer.requests.map(\.identifier), [identifier(number: 42)])
    }

    func testDecliningRemovesOnlyThatPrompt() throws {
        let fixture = try makeDetectionFixture()
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(
                in: fixture,
                content: "https://github.com/octo/alpha/pull/42 and https://github.com/octo/beta/pull/9"
            )
        )
        let prompt = try XCTUnwrap(fixture.thread.pendingPullRequestLinkPrompts.first)

        fixture.viewModel.declinePullRequestLinkPrompt(prompt, never: false)

        XCTAssertEqual(
            fixture.thread.pendingPullRequestLinkPrompts.map(\.identifier),
            [PullRequestIdentifier(owner: "octo", repo: "beta", number: 9)]
        )
        XCTAssertFalse(fixture.settingsService.current.suppressPullRequestLinkPrompts)
    }

    func testDecliningForeverSuppressesFuturePrompts() throws {
        let fixture = try makeDetectionFixture()
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42", at: 100)
        )
        let prompt = try XCTUnwrap(fixture.thread.pendingPullRequestLinkPrompts.first)

        fixture.viewModel.declinePullRequestLinkPrompt(prompt, never: true)

        XCTAssertTrue(fixture.settingsService.current.suppressPullRequestLinkPrompts)
        XCTAssertFalse(fixture.settingsService.current.automaticallyLinkPullRequests)
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(
            try insertAssistantMessage(in: fixture, content: "https://github.com/octo/beta/pull/9", at: 200)
        )
        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
    }

    // MARK: - Rendering map

    func testPromptsAreGroupedByAnchoringMessage() throws {
        let fixture = try makeDetectionFixture()
        let record = try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42")
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(record)

        let grouped = fixture.viewModel.pendingPullRequestLinkPromptsByMessageID()

        XCTAssertEqual(grouped[record.id]?.map(\.identifier), [identifier(number: 42)])
    }

    func testSuppressedAndLinkedPromptsAreFilteredOutOfTheRenderingMap() throws {
        let fixture = try makeDetectionFixture()
        let record = try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42")
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(record)

        fixture.settingsService.update { $0.suppressPullRequestLinkPrompts = true }
        XCTAssertEqual(fixture.viewModel.pendingPullRequestLinkPromptsByMessageID(), [:])

        fixture.settingsService.update { $0.suppressPullRequestLinkPrompts = false }
        fixture.thread.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 42), linkedAt: Date(timeIntervalSince1970: 1))
        ]
        XCTAssertEqual(fixture.viewModel.pendingPullRequestLinkPromptsByMessageID(), [:])
    }

    // MARK: - Pruning

    func testRebuildDropsPromptsWhoseAnchoringMessageIsGone() throws {
        let fixture = try makeDetectionFixture()
        let record = try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42")
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(record)
        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts.count, 1)

        fixture.context.delete(record)
        try fixture.context.save()
        fixture.viewModel.rebuildChatItemsIfNeeded(from: [], forceFullRebuild: true)

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts, [])
    }

    func testRebuildKeepsPromptsWhoseAnchoringMessageSurvives() throws {
        let fixture = try makeDetectionFixture()
        let record = try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42")
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(record)

        fixture.viewModel.rebuildChatItemsIfNeeded(from: [record], forceFullRebuild: true)

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts.count, 1)
    }

    /// Rebuild callers can pass a stale query snapshot, or an empty array standing in
    /// for a failed fetch; pruning off that would delete real questions.
    func testRebuildDoesNotPruneAgainstAnIncompleteRecordSet() throws {
        let fixture = try makeDetectionFixture()
        let record = try insertAssistantMessage(in: fixture, content: "https://github.com/octo/alpha/pull/42")
        fixture.viewModel.scanInsertedMessageRecordForPullRequestLinks(record)

        fixture.viewModel.rebuildChatItemsIfNeeded(from: [], forceFullRebuild: true)

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts.count, 1)
    }

    /// Prompts belong to the thread but anchor to one conversation's message, so a
    /// sibling tab's rebuild must not prune them.
    func testRebuildKeepsPromptsBelongingToAnotherConversation() throws {
        let fixture = try makeDetectionFixture()
        fixture.thread.pendingPullRequestLinkPrompts = [
            PendingPullRequestPrompt(
                identifier: identifier(number: 42),
                messageEventID: "message-from-other-tab",
                conversationID: "other-conversation",
                createdAt: Date(timeIntervalSince1970: 1)
            )
        ]

        fixture.viewModel.rebuildChatItemsIfNeeded(from: [], forceFullRebuild: true)

        XCTAssertEqual(fixture.thread.pendingPullRequestLinkPrompts.count, 1)
    }

    // MARK: - Helpers

    private func makeDetectionFixture(
        pullRequestsEnabled: Bool = true,
        automaticallyLinkPullRequests: Bool = false,
        suppressPullRequestLinkPrompts: Bool = false,
        isDraft: Bool = false
    ) throws -> ConversationViewModelTestFixture {
        let fixture = try ConversationViewModelTestFixture(isDraft: isDraft)
        fixture.settingsService.update {
            $0.pullRequestsEnabled = pullRequestsEnabled
            $0.automaticallyLinkPullRequests = automaticallyLinkPullRequests
            $0.suppressPullRequestLinkPrompts = suppressPullRequestLinkPrompts
        }
        return fixture
    }

    private func insertAssistantMessage(
        in fixture: ConversationViewModelTestFixture,
        content: String,
        at timestamp: TimeInterval = 100
    ) throws -> ConversationEventRecord {
        let record = ConversationEventRecord(
            conversationId: fixture.conversation.id,
            type: ConversationEventRecord.messageType,
            role: ConversationEventRecord.assistantRole,
            content: content,
            timestamp: Date(timeIntervalSince1970: timestamp),
            conversation: fixture.conversation
        )
        fixture.context.insert(record)
        return record
    }

    private func identifier(number: Int) -> PullRequestIdentifier {
        PullRequestIdentifier(owner: "octo", repo: "alpha", number: number)
    }
}

/// Collects `.pullRequestLinkRequested` posts for the lifetime of one test.
@MainActor
final class PullRequestLinkRequestObserver {
    private(set) var requests: [PullRequestLinkRequest] = []
    // `nonisolated(unsafe)` so the nonisolated `deinit` can unregister: the token is
    // only ever written once, in `init`.
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .pullRequestLinkRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let request = notification.userInfo?[
                PullRequestLinkRequestNotificationKey.request
            ] as? PullRequestLinkRequest else {
                return
            }
            MainActor.assumeIsolated {
                self?.requests.append(request)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
