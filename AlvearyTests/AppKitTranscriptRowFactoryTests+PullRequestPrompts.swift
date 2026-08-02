@preconcurrency import AppKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptRowFactoryTests {
    func testPromptRowsFollowTheirMessageBubble() {
        let factory = AppKitTranscriptRowFactory()
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.pullRequestLinkPromptsByMessageID = [
            "assistant": [prompt(number: 42, messageEventID: "assistant")]
        ]

        let rows = factory.makeRows(
            for: [
                .userMessage(id: "user", text: "Ship it"),
                .assistantMessage(id: "assistant", text: "Opened https://github.com/octo/alpha/pull/42")
            ],
            configuration: configuration
        )

        XCTAssertEqual(rows.map(\.id), ["user", "assistant", "assistant-pr-prompt-octo/alpha#42"])
        XCTAssertTrue(rows[2].view is AppKitTranscriptPullRequestPromptView)
    }

    func testEachPullRequestOnOneMessageGetsItsOwnRow() {
        let factory = AppKitTranscriptRowFactory()
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.pullRequestLinkPromptsByMessageID = [
            "user": [
                prompt(number: 42, messageEventID: "user"),
                prompt(number: 9, messageEventID: "user", repo: "beta")
            ]
        ]

        let rows = factory.makeRows(for: [.userMessage(id: "user", text: "Two PRs")], configuration: configuration)

        XCTAssertEqual(rows.map(\.id), ["user", "user-pr-prompt-octo/alpha#42", "user-pr-prompt-octo/beta#9"])
    }

    func testMessagesWithoutPromptsEmitOnlyTheirBubble() {
        let factory = AppKitTranscriptRowFactory()

        let rows = factory.makeRows(for: [.userMessage(id: "user", text: "Hello")], configuration: .init())

        XCTAssertEqual(rows.map(\.id), ["user"])
    }

    func testPromptRowViewsAreReusedAcrossRebuilds() {
        let factory = AppKitTranscriptRowFactory()
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.pullRequestLinkPromptsByMessageID = [
            "assistant": [prompt(number: 42, messageEventID: "assistant")]
        ]
        let items: [ChatItem] = [.assistantMessage(id: "assistant", text: "Opened a PR")]

        let firstRows = factory.makeRows(for: items, configuration: configuration)
        let secondRows = factory.makeRows(for: items, configuration: configuration)

        XCTAssertTrue(firstRows[1].view === secondRows[1].view)
    }

    func testAcceptAndDeclineCallbacksCarryTheSelectedAction() throws {
        let factory = AppKitTranscriptRowFactory()
        let pending = prompt(number: 42, messageEventID: "assistant")
        var accepted: [(PendingPullRequestPrompt, Bool)] = []
        var declined: [(PendingPullRequestPrompt, Bool)] = []
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.pullRequestLinkPromptsByMessageID = ["assistant": [pending]]
        configuration.selectedPullRequestPromptSelection = { _ in
            PullRequestLinkPromptSelection(acceptsAlways: true, declinesForever: true)
        }
        configuration.onAcceptPullRequestLinkPrompt = { accepted.append(($0, $1)) }
        configuration.onDeclinePullRequestLinkPrompt = { declined.append(($0, $1)) }

        let rows = factory.makeRows(
            for: [.assistantMessage(id: "assistant", text: "Opened a PR")],
            configuration: configuration
        )
        let view = try XCTUnwrap(rows[1].view as? AppKitTranscriptPullRequestPromptView)
        view.onAccept?(true)
        view.onDecline?(true)

        XCTAssertEqual(accepted.map(\.0.id), [pending.id])
        XCTAssertEqual(accepted.map(\.1), [true])
        XCTAssertEqual(declined.map(\.0.id), [pending.id])
        XCTAssertEqual(declined.map(\.1), [true])
    }

    private func prompt(
        number: Int,
        messageEventID: String,
        repo: String = "alpha"
    ) -> PendingPullRequestPrompt {
        PendingPullRequestPrompt(
            identifier: PullRequestIdentifier(owner: "octo", repo: repo, number: number),
            messageEventID: messageEventID,
            conversationID: "conversation-1",
            createdAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
    }
}
