import Foundation
import SwiftData
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

/// The review footer's split-button selection and the agentic options it can run: the selection
/// persists per authorship, the spawn reports busy and errors on the pane session, and a success
/// navigates to the new thread.
@MainActor
extension PullRequestsViewModelTests {
    private struct OpenedReviewPane {
        let viewModel: PullRequestsViewModel
        let id: PullRequestIdentifier
    }

    private func openedReviewPane(
        settingsService: (any SettingsService)? = nil,
        origin: PullRequestPaneOrigin = .screen,
        presentToast: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        starter: (
            @MainActor (PullRequestAgenticThreadRequest) async throws -> PullRequestAgenticThreadStart
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
            agenticThreadStarter: starter
        )
        await viewModel.refresh()
        viewModel.requestDetails(summary, origin: origin)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        return OpenedReviewPane(viewModel: viewModel, id: summary.id)
    }

    private func footerViewModel(settingsService: (any SettingsService)? = nil) -> PullRequestsViewModel {
        makePullRequestsViewModel(service: StubPullRequestsService(), settingsService: settingsService)
    }

    // MARK: - Split-button selection

    /// The two halves of a pull request's life want opposite doors, so authorship picks the
    /// default rather than one packaged kind serving both.
    func testTheFooterDefaultsToAddressingYourOwnFeedbackAndReviewingEveryoneElses() {
        let viewModel = footerViewModel()

        XCTAssertEqual(viewModel.selectedReviewFooterActionKind(for: .authored), .addressFeedback)
        XCTAssertEqual(viewModel.selectedReviewFooterActionKind(for: .other), .agenticReview)
    }

    /// Authorship is unknown only while a detail is in flight; landing on the reviewing default
    /// is the safer read, and the footer re-seeds once it settles.
    func testUnknownAuthorshipTakesTheOthersDefault() {
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestOthersFooterActionKind = "submitReview" }
        let viewModel = footerViewModel(settingsService: settingsService)

        XCTAssertEqual(viewModel.selectedReviewFooterActionKind(for: .unknown), .submitReview)
    }

    func testSelectingTheFooterActionPersistsItForThatAuthorshipAlone() {
        let settingsService = InMemorySettingsService()
        let viewModel = footerViewModel(settingsService: settingsService)

        viewModel.selectReviewFooterAction(.submitReview, for: .authored)

        XCTAssertEqual(settingsService.current.pullRequestOwnFooterActionKind, "submitReview")
        XCTAssertEqual(viewModel.selectedReviewFooterActionKind(for: .authored), .submitReview)
        // Reviewing other people's pull requests is a separate pick and is untouched.
        XCTAssertEqual(settingsService.current.pullRequestOthersFooterActionKind, "agenticReview")
        XCTAssertEqual(viewModel.selectedReviewFooterActionKind(for: .other), .agenticReview)
    }

    /// `.unknown` reads the others' key, so a pick made before the detail lands has to write
    /// there too — otherwise it would be forgotten the moment authorship settled.
    func testAPickMadeBeforeAuthorshipSettlesWritesTheOthersKey() {
        let settingsService = InMemorySettingsService()
        let viewModel = footerViewModel(settingsService: settingsService)

        viewModel.selectReviewFooterAction(.submitReview, for: .unknown)

        XCTAssertEqual(settingsService.current.pullRequestOthersFooterActionKind, "submitReview")
        // The own key keeps its packaged default: the unknown pick lands on the others' side
        // alone. Picked deliberately to differ from both defaults so this proves a non-write.
        XCTAssertEqual(settingsService.current.pullRequestOwnFooterActionKind, "addressFeedback")
    }

    /// A kind written by a newer build must still leave a usable button, and which one depends on
    /// whose pull request it is.
    func testAStoredFooterActionThisBuildDoesNotKnowFallsBackToTheAuthorshipDefault() {
        let settingsService = InMemorySettingsService()
        settingsService.update {
            $0.pullRequestOwnFooterActionKind = "someFutureKind"
            $0.pullRequestOthersFooterActionKind = "someFutureKind"
        }
        let viewModel = footerViewModel(settingsService: settingsService)

        XCTAssertEqual(viewModel.selectedReviewFooterActionKind(for: .authored), .addressFeedback)
        XCTAssertEqual(viewModel.selectedReviewFooterActionKind(for: .other), .agenticReview)
    }

    // MARK: - Spawning

    func testStartingAnAgenticThreadNavigatesToTheSpawnedThread() async {
        let requested = RequestBox()
        let pane = await openedReviewPane(starter: { request in
            requested.value = request
            return makeAgenticThreadStart(conversationID: "conversation-1")
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

        pane.viewModel.startAgenticThread(kind: .review)
        await fulfillment(of: [opened], timeout: 2)

        XCTAssertEqual(requestedConversationID.value, "conversation-1")
        XCTAssertEqual(requested.value?.kind, .review)
        XCTAssertEqual(requested.value?.url.absoluteString, "https://github.com/octo/alpha/pull/7")
        // The pane's own detail rides along so linking need not refetch it.
        XCTAssertEqual(requested.value?.knownDetail?.id, pane.id)
        XCTAssertEqual(pane.viewModel.paneSessions[.details(pane.id)]?.isStartingAgenticThread, false)
        XCTAssertNil(pane.viewModel.paneSessions[.details(pane.id)]?.agenticThreadError)
    }

    /// Both footer options run the same spawn, so the kind the caller asks for is the only thing
    /// that separates them.
    func testEachFooterOptionSpawnsItsOwnKind() async {
        for kind in PullRequestAgenticThreadService.Kind.allCases {
            let requested = RequestBox()
            let pane = await openedReviewPane(starter: { request in
                requested.value = request
                return makeAgenticThreadStart(conversationID: "conversation-1")
            })

            pane.viewModel.startAgenticThread(kind: kind)
            try? await Task.sleep(for: .milliseconds(50))

            XCTAssertEqual(requested.value?.kind, kind)
        }
    }

    /// Several clones can hold one repository, so a pane opened from a project names the one the
    /// user is looking at; the checkout ladder takes it from there.
    func testAProjectPaneNamesItsCloneForTheCheckout() async throws {
        let projectID = try makeOwnerIdentifiers().project
        let requested = RequestBox()
        let pane = await openedReviewPane(origin: .project(projectID), starter: { request in
            requested.value = request
            return makeAgenticThreadStart(conversationID: "conversation-1")
        })

        pane.viewModel.startAgenticThread(kind: .addressFeedback)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(requested.value?.preferredProjectID, projectID)
    }

    /// The screen and a thread's linked pull requests name no clone, so the ladder chooses.
    func testAScreenPaneNamesNoClone() async {
        let requested = RequestBox()
        let pane = await openedReviewPane(starter: { request in
            requested.value = request
            return makeAgenticThreadStart(conversationID: "conversation-1")
        })

        pane.viewModel.startAgenticThread(kind: .addressFeedback)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(requested.value?.preferredProjectID)
    }

    /// The whole point of the split: the sidebar selection must not wait on linking, a checkout,
    /// or the first prompt, all of which reach the network.
    func testNavigationHappensBeforeTheDeferredHalfFinishes() async {
        let dispatchFinished = FlagBox()
        let pane = await openedReviewPane(starter: { _ in
            makeAgenticThreadStart(conversationID: "conversation-1") {
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

        pane.viewModel.startAgenticThread(kind: .review)
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
            starter: { _ in
                makeAgenticThreadStart(conversationID: "conversation-1") {
                    throw PullRequestAgenticThreadService.StartError.conversationMissing
                }
            }
        )

        pane.viewModel.startAgenticThread(kind: .review)
        await fulfillment(of: [toasted], timeout: 2)

        XCTAssertEqual(
            message.value,
            PullRequestAgenticThreadService.StartError.conversationMissing.localizedDescription
        )
        // A deferred failure is not the footer's to report — navigation already unmounted it.
        XCTAssertNil(pane.viewModel.paneSessions[.details(pane.id)]?.agenticThreadError)
    }

    func testAFailedStartSurfacesAsAFooterBannerAndReleasesTheButton() async {
        let pane = await openedReviewPane(starter: { _ in
            throw PullRequestAgenticThreadService.StartError.noReadyProvider
        })

        pane.viewModel.startAgenticThread(kind: .addressFeedback)
        try? await Task.sleep(for: .milliseconds(50))

        let session = pane.viewModel.paneSessions[.details(pane.id)]
        XCTAssertEqual(session?.isStartingAgenticThread, false)
        XCTAssertEqual(
            session?.agenticThreadError,
            PullRequestAgenticThreadService.StartError.noReadyProvider.localizedDescription
        )

        pane.viewModel.clearAgenticThreadError()
        XCTAssertNil(pane.viewModel.paneSessions[.details(pane.id)]?.agenticThreadError)
    }

    /// One busy flag for both kinds, so the second click cannot start the other half of the pull
    /// request's life on top of the first.
    func testAnInFlightStartRefusesASecondSoOneClickCannotSpawnTwoThreads() async {
        var startCount = 0
        let pane = await openedReviewPane(starter: { _ in
            startCount += 1
            try await Task.sleep(for: .milliseconds(200))
            return makeAgenticThreadStart(conversationID: "conversation-1")
        })

        pane.viewModel.startAgenticThread(kind: .review)
        pane.viewModel.startAgenticThread(kind: .addressFeedback)
        // The busy flag is set synchronously, which is what refuses the second click; the
        // starter itself runs in a Task, so the count needs a hop to be observable.
        XCTAssertEqual(pane.viewModel.paneSessions[.details(pane.id)]?.isStartingAgenticThread, true)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(startCount, 1)
    }

    func testWithoutAStarterTheAgenticOptionsDoNothing() async {
        let pane = await openedReviewPane()

        pane.viewModel.startAgenticThread(kind: .review)

        XCTAssertEqual(pane.viewModel.paneSessions[.details(pane.id)]?.isStartingAgenticThread, false)
    }
}

/// Records what the starter was handed, from a closure that cannot capture a `var`.
@MainActor
final class RequestBox {
    var value: PullRequestAgenticThreadRequest?
}
