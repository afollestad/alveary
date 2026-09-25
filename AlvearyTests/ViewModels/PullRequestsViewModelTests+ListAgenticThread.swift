import Foundation
import XCTest

@testable import Alveary

/// The list row menu's agentic entry: it starts a route with no pane open, so its failures land on
/// a toast or the screen's alert, and the row carries the working indicator instead of a footer.
@MainActor
extension PullRequestsViewModelTests {
    func testARowMenuStartRunsInTheBackgroundFromTheSummary() async throws {
        let requested = RequestBox()
        let list = await openedReviewPane(origin: nil, starter: { request in
            requested.value = request
            return makeAgenticThreadStart(conversationID: "conversation-1")
        })
        let requestedConversationID = RequestedConversationIDBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .threadOpenRequested,
            object: nil,
            queue: .main
        ) { notification in
            let request = notification.userInfo?[ThreadOpenRequestNotificationKey.request] as? ThreadOpenRequest
            requestedConversationID.value = request?.conversationID
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        list.viewModel.startAgenticThread(kind: .review, for: list.summary)
        await drainMainQueue()

        XCTAssertNil(requestedConversationID.value, "Spawning must not move the sidebar selection")
        XCTAssertNil(list.viewModel.activePaneTarget, "A row menu start must not open the pane")
        XCTAssertEqual(requested.value?.kind, .review)
        XCTAssertEqual(requested.value?.url.absoluteString, "https://github.com/octo/alpha/pull/7")
        XCTAssertEqual(requested.value?.knownSummary?.id, list.id)
        XCTAssertNil(requested.value?.knownDetail)
        XCTAssertNil(requested.value?.preferredProjectID)
        let row = try XCTUnwrap(rowModels(in: list.viewModel.visibleListItems(for: .all)).first)
        XCTAssertEqual(row.workingAgenticKinds, [.review])
        XCTAssertTrue(row.accessibilityLabel.contains("Agent working"))
    }

    func testARowMenuStartOnAWorkingRouteIsRefused() async {
        var startCount = 0
        let list = await openedReviewPane(origin: nil, starter: { _ in
            startCount += 1
            return makeAgenticThreadStart(conversationID: "conversation-1")
        })

        list.viewModel.startAgenticThread(kind: .review, for: list.summary)
        await drainMainQueue()
        list.viewModel.startAgenticThread(kind: .review, for: list.summary)
        await drainMainQueue()

        XCTAssertEqual(startCount, 1)
    }

    /// The row mirror follows the shared tracker, so a run the pane's footer started shows too.
    func testARowShowsAFooterStartedRouteUntilItsFirstTurnGoesIdle() async throws {
        let pane = await openedReviewPane(starter: { _ in
            makeAgenticThreadStart(conversationID: "conversation-1")
        })
        pane.viewModel.startAgenticThread(kind: .addressFeedback)
        await drainMainQueue()
        pane.post(.busy, conversationID: "conversation-1")

        let working = try XCTUnwrap(rowModels(in: pane.viewModel.visibleListItems(for: .all)).first)
        XCTAssertEqual(working.workingAgenticKinds, [.addressFeedback])

        pane.post(.idle, conversationID: "conversation-1")

        let idle = try XCTUnwrap(rowModels(in: pane.viewModel.visibleListItems(for: .all)).first)
        XCTAssertFalse(idle.isAgentWorking)
    }

    func testARowMenuMissingProjectRaisesTheScreenAlertInsteadOfAToast() async {
        let message = MessageBox()
        let list = await openedReviewPane(
            origin: nil,
            presentToast: { message.value = $0 },
            starter: { _ in
                throw PullRequestAgenticThreadService.StartError.projectMissing(repository: "octo/alpha")
            }
        )

        list.viewModel.startAgenticThread(kind: .addressFeedback, for: list.summary)
        await drainMainQueue()

        XCTAssertEqual(list.viewModel.listAgenticThreadMissingProject, "octo/alpha")
        XCTAssertNil(message.value)

        list.viewModel.clearListAgenticThreadMissingProject()
        XCTAssertNil(list.viewModel.listAgenticThreadMissingProject)
    }

    /// No footer is mounted to carry the banner a pane start would raise.
    func testARowMenuStartFailureToasts() async {
        let toasted = expectation(description: "toast presented")
        let message = MessageBox()
        let list = await openedReviewPane(
            origin: nil,
            presentToast: { text in
                message.value = text
                toasted.fulfill()
            },
            starter: { _ in throw PullRequestAgenticThreadService.StartError.noReadyHarness }
        )

        list.viewModel.startAgenticThread(kind: .review, for: list.summary)
        await fulfillment(of: [toasted], timeout: 2)

        XCTAssertEqual(message.value, PullRequestAgenticThreadService.StartError.noReadyHarness.localizedDescription)
        XCTAssertNil(list.viewModel.listAgenticThreadMissingProject)
    }

    func testARowMenuTeamReviewIsRefusedUntilTheTeamValidates() async {
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
        let message = MessageBox()
        var startCount = 0
        let list = await openedReviewPane(
            settingsService: settingsService,
            origin: nil,
            presentToast: { message.value = $0 },
            starter: { _ in
                startCount += 1
                return makeAgenticThreadStart(conversationID: "conversation-1")
            }
        )

        list.viewModel.startAgenticThread(kind: .review, for: list.summary)
        await drainMainQueue()

        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(message.value, PullRequestReviewTeamValidationStatus.unvalidated.footerMessage)
    }
}
