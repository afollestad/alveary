import Foundation
import XCTest

@testable import Alveary

/// Lets the notification observer's closure record what it saw without capturing a `var`.
final class RequestedConversationIDBox: @unchecked Sendable {
    var value: String?
}

/// The review footer's split-button selection and the agentic option it can run:
/// the selection persists, the spawn reports busy and errors on the pane session,
/// and a success navigates to the new thread.
@MainActor
extension PullRequestsViewModelTests {
    private struct OpenedReviewPane {
        let viewModel: PullRequestsViewModel
        let id: PullRequestIdentifier
    }

    private func openedReviewPane(
        settingsService: (any SettingsService)? = nil,
        starter: (@MainActor (PullRequestIdentifier, URL) async throws -> String)? = nil
    ) async -> OpenedReviewPane {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7, status: .open)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, status: .open, viewerCanUpdate: true))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.listResult = .success(PullRequestListResult(summaries: [summary], warnings: []))
        let viewModel = makePullRequestsViewModel(
            service: service,
            settingsService: settingsService,
            agenticReviewStarter: starter
        )
        await viewModel.refresh()
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        return OpenedReviewPane(viewModel: viewModel, id: summary.id)
    }

    func testSelectedFooterActionFallsBackToSubmitReviewWithoutSettings() async {
        let pane = await openedReviewPane()

        XCTAssertEqual(pane.viewModel.selectedReviewFooterActionKind, .submitReview)
    }

    func testSelectingTheFooterActionPersistsItForTheNextLaunch() async {
        let settingsService = InMemorySettingsService()
        let pane = await openedReviewPane(settingsService: settingsService)

        pane.viewModel.selectReviewFooterAction(.agenticReview)

        XCTAssertEqual(settingsService.current.pullRequestReviewFooterActionKind, "agenticReview")
        XCTAssertEqual(pane.viewModel.selectedReviewFooterActionKind, .agenticReview)
    }

    func testAStoredFooterActionThisBuildDoesNotKnowFallsBackToSubmitReview() async {
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestReviewFooterActionKind = "someFutureKind" }
        let pane = await openedReviewPane(settingsService: settingsService)

        XCTAssertEqual(pane.viewModel.selectedReviewFooterActionKind, .submitReview)
    }

    func testStartingAnAgenticReviewNavigatesToTheSpawnedThread() async {
        var receivedURL: URL?
        let pane = await openedReviewPane(starter: { _, url in
            receivedURL = url
            return "conversation-1"
        })
        let opened = expectation(description: "thread open requested")
        let requestedConversationID = RequestedConversationIDBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .threadOpenRequested,
            object: nil,
            queue: .main
        ) { notification in
            let request = notification.userInfo?[ThreadOpenRequestNotificationKey.request] as? ThreadOpenRequest
            requestedConversationID.value = request?.conversationID
            opened.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        pane.viewModel.startAgenticReview()
        await fulfillment(of: [opened], timeout: 2)

        XCTAssertEqual(requestedConversationID.value, "conversation-1")
        XCTAssertEqual(receivedURL?.absoluteString, "https://github.com/octo/alpha/pull/7")
        XCTAssertEqual(pane.viewModel.paneSessions[.details(pane.id)]?.isStartingAgenticReview, false)
        XCTAssertNil(pane.viewModel.paneSessions[.details(pane.id)]?.agenticReviewError)
    }

    func testAFailedStartSurfacesAsAFooterBannerAndReleasesTheButton() async {
        let pane = await openedReviewPane(starter: { _, _ in
            throw PullRequestAgenticReviewService.StartError.noReadyProvider
        })

        pane.viewModel.startAgenticReview()
        try? await Task.sleep(for: .milliseconds(50))

        let session = pane.viewModel.paneSessions[.details(pane.id)]
        XCTAssertEqual(session?.isStartingAgenticReview, false)
        XCTAssertEqual(
            session?.agenticReviewError,
            PullRequestAgenticReviewService.StartError.noReadyProvider.localizedDescription
        )

        pane.viewModel.clearAgenticReviewError()
        XCTAssertNil(pane.viewModel.paneSessions[.details(pane.id)]?.agenticReviewError)
    }

    func testAnInFlightStartRefusesASecondSoOneClickCannotSpawnTwoThreads() async {
        var startCount = 0
        let pane = await openedReviewPane(starter: { _, _ in
            startCount += 1
            try await Task.sleep(for: .milliseconds(200))
            return "conversation-1"
        })

        pane.viewModel.startAgenticReview()
        pane.viewModel.startAgenticReview()
        // The busy flag is set synchronously, which is what refuses the second click; the
        // starter itself runs in a Task, so the count needs a hop to be observable.
        XCTAssertEqual(pane.viewModel.paneSessions[.details(pane.id)]?.isStartingAgenticReview, true)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(startCount, 1)
    }

    func testWithoutAStarterTheAgenticOptionDoesNothing() async {
        let pane = await openedReviewPane()

        pane.viewModel.startAgenticReview()

        XCTAssertEqual(pane.viewModel.paneSessions[.details(pane.id)]?.isStartingAgenticReview, false)
    }
}
