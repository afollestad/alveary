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

/// And for sampling whether the deferred half had finished at a given moment.
final class FlagBox: @unchecked Sendable {
    var value = false
}

/// The review footer's split-button selection and the agentic options it can run: the selection
/// persists per authorship, a spawn marks its own route working without moving the user anywhere,
/// and the route stays working until that thread's first turn ends.
@MainActor
extension PullRequestsViewModelTests {
    @MainActor
    private struct OpenedReviewPane {
        let viewModel: PullRequestsViewModel
        let id: PullRequestIdentifier
        /// The private bus both the tracker and the view model are on, so a test can stand in for
        /// the runtime by posting the status changes the tracker listens for.
        let notificationCenter: NotificationCenter

        var session: PullRequestPaneSession? {
            viewModel.paneSessions[.details(id)]
        }

        var workingKinds: Set<PullRequestAgenticThreadService.Kind> {
            session?.workingAgenticKinds ?? []
        }

        /// Stands in for `DefaultAgentsManager.updateStatus`.
        func post(_ signal: ActivitySignal, conversationID: String) {
            notificationCenter.post(
                name: .agentStatusChanged,
                object: nil,
                userInfo: [
                    AgentStatusChangedKey.conversationID: conversationID,
                    AgentStatusChangedKey.signal: signal
                ]
            )
        }
    }

    private func openedReviewPane(
        settingsService: (any SettingsService)? = nil,
        origin: PullRequestPaneOrigin = .screen,
        presentToast: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        startupGrace: Duration = .seconds(30),
        starter: (
            @MainActor (PullRequestAgenticThreadRequest) async throws -> PullRequestAgenticThreadStart
        )? = nil
    ) async -> OpenedReviewPane {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7, status: .open)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, status: .open, viewerCanUpdate: true))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.listResult = .success(PullRequestListResult(summaries: [summary], warnings: []))
        // One private bus for both, so the tracker's announcements reach this view model's mirror
        // and nothing on `.default` can disturb the suite.
        let notificationCenter = NotificationCenter()
        let activity = PullRequestAgenticThreadActivity(
            notificationCenter: notificationCenter,
            startupGrace: startupGrace
        )
        let viewModel = makePullRequestsViewModel(
            service: service,
            settingsService: settingsService,
            presentToast: presentToast,
            agenticThreadStarter: starter,
            agenticThreadActivity: activity,
            notificationCenter: notificationCenter
        )
        await viewModel.refresh()
        viewModel.requestDetails(summary, origin: origin)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        return OpenedReviewPane(
            viewModel: viewModel,
            id: summary.id,
            notificationCenter: notificationCenter
        )
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

    /// The regression this pins: the footer used to select the spawned thread the moment it
    /// existed, throwing away the pull request the user was reading.
    func testStartingAnAgenticThreadLeavesTheUserOnThePullRequest() async {
        let requested = RequestBox()
        let pane = await openedReviewPane(starter: { request in
            requested.value = request
            return makeAgenticThreadStart(conversationID: "conversation-1")
        })
        let requestedConversationID = RequestedConversationIDBox()
        // Sidebar selection is app-wide, so a navigation would have to come through `.default`.
        let observer = NotificationCenter.default.addObserver(
            forName: .threadOpenRequested,
            object: nil,
            queue: .main
        ) { notification in
            let request = notification.userInfo?[ThreadOpenRequestNotificationKey.request] as? ThreadOpenRequest
            requestedConversationID.value = request?.conversationID
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        pane.viewModel.startAgenticThread(kind: .review)
        await drainMainQueue()

        XCTAssertNil(requestedConversationID.value, "Spawning must not move the sidebar selection")
        XCTAssertEqual(requested.value?.kind, .review)
        XCTAssertEqual(requested.value?.url.absoluteString, "https://github.com/octo/alpha/pull/7")
        // The pane's own detail and row ride along so linking need not refetch either.
        XCTAssertEqual(requested.value?.knownDetail?.id, pane.id)
        XCTAssertEqual(requested.value?.knownSummary?.id, pane.id)
        XCTAssertNil(pane.session?.agenticThreadError)
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
            await drainMainQueue()

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
        await drainMainQueue()

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
        await drainMainQueue()

        XCTAssertNil(requested.value?.preferredProjectID)
    }

    // MARK: - The working indicator

    /// The click's own turn, before any suspension — otherwise the button sits idle through a
    /// provider-discovery round trip that can run into seconds.
    func testTheRouteIsMarkedWorkingSynchronouslyOnTheClick() async {
        let pane = await openedReviewPane(starter: { _ in
            makeAgenticThreadStart(conversationID: "conversation-1")
        })

        pane.viewModel.startAgenticThread(kind: .review)

        XCTAssertEqual(pane.workingKinds, [.review])
    }

    /// The whole point of the split: the button reflects a real thread without waiting on linking,
    /// a checkout, or the first prompt, all of which reach the network.
    func testTheRouteIsWorkingBeforeTheDeferredHalfFinishes() async {
        let dispatchFinished = FlagBox()
        let pane = await openedReviewPane(starter: { _ in
            makeAgenticThreadStart(conversationID: "conversation-1") {
                try await Task.sleep(for: .milliseconds(200))
                dispatchFinished.value = true
            }
        })

        pane.viewModel.startAgenticThread(kind: .review)
        await drainMainQueue()

        XCTAssertEqual(pane.workingKinds, [.review])
        XCTAssertFalse(dispatchFinished.value, "The indicator must not wait on linking or the prompt")
    }

    /// "Until the first turn becomes idle" — the run has to be seen starting before it can be
    /// seen ending, or the `.idle` the runtime writes at buffer install would end it early.
    func testTheRouteStaysWorkingUntilTheFirstTurnGoesIdle() async {
        let pane = await openedReviewPane(starter: { _ in
            makeAgenticThreadStart(conversationID: "conversation-1")
        })
        pane.viewModel.startAgenticThread(kind: .review)
        await drainMainQueue()

        pane.post(.busy, conversationID: "conversation-1")
        XCTAssertEqual(pane.workingKinds, [.review])

        pane.post(.idle, conversationID: "conversation-1")
        XCTAssertEqual(pane.workingKinds, [])
    }

    /// An approval pause is the run needing the user, not the run being over.
    func testAnApprovalPauseKeepsTheRouteWorking() async {
        let pane = await openedReviewPane(starter: { _ in
            makeAgenticThreadStart(conversationID: "conversation-1")
        })
        pane.viewModel.startAgenticThread(kind: .review)
        await drainMainQueue()
        pane.post(.busy, conversationID: "conversation-1")

        pane.post(.waitingForUser, conversationID: "conversation-1")

        XCTAssertEqual(pane.workingKinds, [.review])
    }

    /// `DefaultNotificationManager` shares this bus for unread flips, posting the conversation with
    /// no signal; reading one as a transition would end a run on an unread change.
    func testAnUnreadFlipOnTheSharedBusIsNotATransition() async {
        let pane = await openedReviewPane(starter: { _ in
            makeAgenticThreadStart(conversationID: "conversation-1")
        })
        pane.viewModel.startAgenticThread(kind: .review)
        await drainMainQueue()
        pane.post(.busy, conversationID: "conversation-1")

        pane.notificationCenter.post(
            name: .agentStatusChanged,
            object: nil,
            userInfo: [AgentStatusChangedKey.conversationID: "conversation-1"]
        )

        XCTAssertEqual(pane.workingKinds, [.review])
    }

    /// A spawn whose provider never starts would otherwise spin forever.
    func testARunThatNeverStartsIsDroppedByTheStartupGrace() async {
        let pane = await openedReviewPane(
            startupGrace: .milliseconds(10),
            starter: { _ in makeAgenticThreadStart(conversationID: "conversation-1") }
        )

        pane.viewModel.startAgenticThread(kind: .review)
        await waitFor { pane.workingKinds.isEmpty }

        XCTAssertEqual(pane.workingKinds, [])
    }

    /// The two halves of a pull request's life are separate work, so one running must not hold the
    /// other hostage.
    func testTheTwoRoutesTrackIndependently() async {
        var startCount = 0
        let pane = await openedReviewPane(starter: { request in
            startCount += 1
            return makeAgenticThreadStart(conversationID: "conversation-\(request.kind)")
        })

        pane.viewModel.startAgenticThread(kind: .review)
        await drainMainQueue()
        pane.viewModel.startAgenticThread(kind: .addressFeedback)
        await drainMainQueue()

        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(pane.workingKinds, [.review, .addressFeedback])
    }

    /// One click cannot spawn two threads on the *same* route, which is what the dimmed button
    /// says and this enforces behind it.
    func testASecondClickOnAWorkingRouteIsRefused() async {
        var startCount = 0
        let pane = await openedReviewPane(starter: { _ in
            startCount += 1
            try await Task.sleep(for: .milliseconds(200))
            return makeAgenticThreadStart(conversationID: "conversation-1")
        })

        pane.viewModel.startAgenticThread(kind: .review)
        pane.viewModel.startAgenticThread(kind: .review)
        // The tracker is written synchronously, which is what refuses the second click.
        XCTAssertEqual(pane.workingKinds, [.review])
        await drainMainQueue()

        XCTAssertEqual(startCount, 1)
    }

    /// The pane is origin-scoped, so it unmounts whenever the user looks elsewhere; a session
    /// created after the run began has no announcement left to hear.
    func testAReopenedPaneSeedsItsWorkingRoutesFromTheTracker() async throws {
        let pane = await openedReviewPane(starter: { _ in
            makeAgenticThreadStart(conversationID: "conversation-1")
        })
        pane.viewModel.startAgenticThread(kind: .review)
        await drainMainQueue()
        pane.post(.busy, conversationID: "conversation-1")

        let generation = try XCTUnwrap(pane.session?.generation)
        pane.viewModel.dismissPane(.details(pane.id), generation: generation)
        XCTAssertNil(pane.session, "The dismissed session must be gone before the reopen")
        pane.viewModel.requestDetails(pane.id, origin: .screen)

        XCTAssertEqual(pane.workingKinds, [.review])
    }

    // MARK: - Failures

    func testAFailedDeferredDispatchToastsAndEndsTheRun() async {
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
        // The prompt never went out, so nothing will ever report a turn for this thread.
        XCTAssertEqual(pane.workingKinds, [])
        // A deferred failure is not the footer's to report — it can outlive the pane.
        XCTAssertNil(pane.session?.agenticThreadError)
    }

    /// Linking is best-effort, so its failure must not read as the run having died — the agent is
    /// working either way, and the toast is the whole of the report.
    func testALinkFailureToastsWithoutEndingTheRun() async {
        let toasted = expectation(description: "toast presented")
        let message = MessageBox()
        let pane = await openedReviewPane(
            presentToast: { text in
                message.value = text
                toasted.fulfill()
            },
            starter: { _ in
                makeAgenticThreadStart(conversationID: "conversation-1", linkFailure: "gh exploded")
            }
        )

        pane.viewModel.startAgenticThread(kind: .review)
        await fulfillment(of: [toasted], timeout: 2)

        XCTAssertEqual(message.value, "gh exploded")
        XCTAssertEqual(pane.workingKinds, [.review])
    }

    func testAFailedStartSurfacesAsAFooterBannerAndReleasesTheButton() async {
        let pane = await openedReviewPane(starter: { _ in
            throw PullRequestAgenticThreadService.StartError.noReadyProvider
        })

        pane.viewModel.startAgenticThread(kind: .addressFeedback)
        await drainMainQueue()

        XCTAssertEqual(pane.workingKinds, [])
        XCTAssertEqual(
            pane.session?.agenticThreadError,
            PullRequestAgenticThreadService.StartError.noReadyProvider.localizedDescription
        )

        pane.viewModel.clearAgenticThreadError()
        XCTAssertNil(pane.session?.agenticThreadError)
    }

    /// The one agentic failure the user can act on, and the action is outside this pane — so it
    /// gets the modal rather than the inline banner the others share.
    func testAMissingProjectRefusalLandsOnTheModalNotTheBanner() async {
        let pane = await openedReviewPane(starter: { _ in
            throw PullRequestAgenticThreadService.StartError.projectMissing(repository: "octo/alpha")
        })

        pane.viewModel.startAgenticThread(kind: .addressFeedback)
        await drainMainQueue()

        XCTAssertEqual(pane.session?.agenticThreadMissingProject, "octo/alpha")
        XCTAssertNil(pane.session?.agenticThreadError)
        XCTAssertEqual(pane.workingKinds, [])

        pane.viewModel.clearAgenticThreadMissingProject()
        XCTAssertNil(pane.session?.agenticThreadMissingProject)
    }

    func testWithoutAStarterTheAgenticOptionsDoNothing() async {
        let pane = await openedReviewPane()

        pane.viewModel.startAgenticThread(kind: .review)

        XCTAssertEqual(pane.workingKinds, [])
    }
}

/// Records what the starter was handed, from a closure that cannot capture a `var`.
@MainActor
final class RequestBox {
    var value: PullRequestAgenticThreadRequest?
}
