import Foundation
import XCTest

@testable import Alveary

/// Lets the notification observer's closure record what it saw without capturing a `var`.
final class RequestedConversationIDBox: @unchecked Sendable {
    var value: String?
}

/// Same trick for the `@Sendable` toast closure.
final class MessageBox: @unchecked Sendable {
    var value: String?
}

/// And for sampling whether the deferred half had finished by the time navigation fired.
final class FlagBox: @unchecked Sendable {
    var value = false
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
        presentToast: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        starter: (
            @MainActor (PullRequestIdentifier, URL, PullRequestDetail?) async throws -> PullRequestAgenticThreadStart
        )? = nil
    ) async -> OpenedReviewPane {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7, status: .open)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, status: .open, viewerCanUpdate: true))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.listResult = .success(PullRequestListResult(summaries: [summary], warnings: []))
        let viewModel = makePullRequestsViewModel(
            service: service,
            settingsService: settingsService,
            presentToast: presentToast,
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
        var receivedDetail: PullRequestDetail?
        let pane = await openedReviewPane(starter: { _, url, detail in
            receivedURL = url
            receivedDetail = detail
            return makeAgenticReviewStart(conversationID: "conversation-1")
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
        // The pane's own detail rides along so linking need not refetch it.
        XCTAssertEqual(receivedDetail?.id, pane.id)
        XCTAssertEqual(pane.viewModel.paneSessions[.details(pane.id)]?.isStartingAgenticReview, false)
        XCTAssertNil(pane.viewModel.paneSessions[.details(pane.id)]?.agenticReviewError)
    }

    /// The whole point of the split: the sidebar selection must not wait on linking or the first
    /// prompt, both of which reach GitHub.
    func testNavigationHappensBeforeTheDeferredHalfFinishes() async {
        let dispatchFinished = FlagBox()
        let pane = await openedReviewPane(starter: { _, _, _ in
            makeAgenticReviewStart(conversationID: "conversation-1") {
                try await Task.sleep(for: .milliseconds(200))
                dispatchFinished.value = true
            }
        })
        let opened = expectation(description: "thread open requested")
        let finishedAtNavigation = FlagBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .threadOpenRequested,
            object: nil,
            queue: .main
        ) { _ in
            finishedAtNavigation.value = dispatchFinished.value
            opened.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        pane.viewModel.startAgenticReview()
        await fulfillment(of: [opened], timeout: 2)

        XCTAssertFalse(finishedAtNavigation.value, "The selection must not wait on linking or the first prompt")
    }

    func testAFailedDeferredDispatchSurfacesAsAToast() async {
        let toasted = expectation(description: "toast presented")
        let message = MessageBox()
        let pane = await openedReviewPane(
            presentToast: { text in
                message.value = text
                toasted.fulfill()
            },
            starter: { _, _, _ in
                makeAgenticReviewStart(conversationID: "conversation-1") {
                    throw PullRequestAgenticThreadService.StartError.conversationMissing
                }
            }
        )

        pane.viewModel.startAgenticReview()
        await fulfillment(of: [toasted], timeout: 2)

        XCTAssertEqual(
            message.value,
            PullRequestAgenticThreadService.StartError.conversationMissing.localizedDescription
        )
        // A deferred failure is not the footer's to report — navigation already unmounted it.
        XCTAssertNil(pane.viewModel.paneSessions[.details(pane.id)]?.agenticReviewError)
    }

    func testAFailedStartSurfacesAsAFooterBannerAndReleasesTheButton() async {
        let pane = await openedReviewPane(starter: { _, _, _ in
            throw PullRequestAgenticThreadService.StartError.noReadyProvider
        })

        pane.viewModel.startAgenticReview()
        try? await Task.sleep(for: .milliseconds(50))

        let session = pane.viewModel.paneSessions[.details(pane.id)]
        XCTAssertEqual(session?.isStartingAgenticReview, false)
        XCTAssertEqual(
            session?.agenticReviewError,
            PullRequestAgenticThreadService.StartError.noReadyProvider.localizedDescription
        )

        pane.viewModel.clearAgenticReviewError()
        XCTAssertNil(pane.viewModel.paneSessions[.details(pane.id)]?.agenticReviewError)
    }

    func testAnInFlightStartRefusesASecondSoOneClickCannotSpawnTwoThreads() async {
        var startCount = 0
        let pane = await openedReviewPane(starter: { _, _, _ in
            startCount += 1
            try await Task.sleep(for: .milliseconds(200))
            return makeAgenticReviewStart(conversationID: "conversation-1")
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
