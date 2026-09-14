import XCTest

@testable import Alveary

@MainActor
extension PullRequestsViewModelTests {
    func testTeamModeValidationIsMirroredIntoThePaneSession() async {
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
        let pane = await openedReviewPane(
            settingsService: settingsService,
            reviewTeamSettingsValidator: { _ in }
        )

        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }

        XCTAssertEqual(pane.session?.pullRequestReviewMode, .reviewTeam)
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
    }

    func testASettingsChangeRevalidatesEveryOpenPane() async {
        let settingsService = InMemorySettingsService()
        let gate = PullRequestsServiceGate()
        let pane = await openedReviewPane(
            settingsService: settingsService,
            reviewTeamSettingsValidator: { _ in await gate.wait() }
        )
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .notRequired)

        settingsService.update { $0.pullRequestReviewMode = .reviewTeam }

        XCTAssertEqual(pane.session?.pullRequestReviewMode, .reviewTeam)
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .validating)

        gate.open()
        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }
    }

    func testAnUnvalidatedTeamBlocksReviewButLeavesAddressFeedbackAvailable() async {
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
        var requestedKinds: [PullRequestAgenticThreadService.Kind] = []
        let pane = await openedReviewPane(
            settingsService: settingsService,
            starter: { request in
                requestedKinds.append(request.kind)
                return makeAgenticThreadStart(conversationID: "conversation-1")
            }
        )
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .unvalidated)

        pane.viewModel.startAgenticThread(kind: .review)
        pane.viewModel.startAgenticThread(kind: .addressFeedback)
        await drainMainQueue()

        XCTAssertEqual(requestedKinds, [.addressFeedback])
    }

    func testAnInvalidTeamBlocksReviewAndKeepsTheResolutionError() async {
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
        let resolutionError = PullRequestReviewTeamResolutionError.invalidTeamSize(1)
        var startCount = 0
        let pane = await openedReviewPane(
            settingsService: settingsService,
            reviewTeamSettingsValidator: { _ in throw resolutionError },
            starter: { _ in
                startCount += 1
                return makeAgenticThreadStart(conversationID: "conversation-1")
            }
        )
        await waitFor {
            pane.session?.pullRequestReviewTeamValidationStatus == .invalid(resolutionError.localizedDescription)
        }

        pane.viewModel.startAgenticThread(kind: .review)
        await drainMainQueue()

        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(
            pane.session?.pullRequestReviewTeamValidationStatus,
            .invalid("Review teams need 2–5 reviewers; this team has 1.")
        )
    }

    func testTheReviewTeamRepairActionOpensGitSettings() {
        let opened = FlagBox()
        let viewModel = makePullRequestsViewModel(
            service: StubPullRequestsService(),
            openGitSettings: { opened.value = true }
        )

        viewModel.openPullRequestReviewSettings()

        XCTAssertTrue(opened.value)
    }

    func testReopeningAPaneRevalidatesAfterAnExternalProviderRepair() async {
        let failures: [(Error, PullRequestReviewTeamValidationStatus)] = [
            (ReviewTeamError.invalidOutput("CLI needs repair"), .invalid("CLI needs repair")),
            (CancellationError(), .failed("Review team check was interrupted. Try again."))
        ]
        for (error, expectedStatus) in failures {
            let settingsService = InMemorySettingsService()
            settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
            let isProviderReady = FlagBox()
            let canRepairProvider = FlagBox()
            var validationCalls = 0
            var refreshCalls = 0
            let pane = await openedReviewPane(
                settingsService: settingsService,
                reviewTeamSettingsValidator: { _ in
                    validationCalls += 1
                    if !isProviderReady.value {
                        throw error
                    }
                },
                refreshReviewTeamProviderDiscovery: {
                    refreshCalls += 1
                    isProviderReady.value = canRepairProvider.value
                }
            )
            await pane.viewModel.reviewTeamValidationTask?.value
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, expectedStatus)
            let callsBeforeRepair = validationCalls
            let refreshesBeforeRepair = refreshCalls
            let savedSettings = settingsService.current

            canRepairProvider.value = true
            pane.viewModel.requestDetails(pane.id, origin: .screen)
            await pane.viewModel.reviewTeamValidationTask?.value

            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
            XCTAssertEqual(validationCalls, callsBeforeRepair + 1)
            XCTAssertEqual(refreshCalls, refreshesBeforeRepair + 1)
            XCTAssertEqual(settingsService.current, savedSettings)
        }
    }

    func testSuccessfulTeamValidationIsReusedAcrossPullRequestsAndReviewLaunches() async {
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
        let service = StubPullRequestsService()
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        var validationCalls = 0
        var refreshCalls = 0
        var startedReviews: [PullRequestIdentifier] = []
        let viewModel = makePullRequestsViewModel(
            service: service,
            settingsService: settingsService,
            agenticThreadStarter: { request in
                startedReviews.append(request.identifier)
                return makeAgenticThreadStart(conversationID: "review-\(request.identifier.number)")
            },
            reviewTeamSettingsValidator: { _ in validationCalls += 1 },
            refreshReviewTeamProviderDiscovery: { refreshCalls += 1 }
        )
        await viewModel.reviewTeamValidationTask?.value

        let summaries = (7...11).map { makePullRequestSummary(number: $0) }
        for (index, summary) in summaries.enumerated() {
            service.detailResult = .success(makePullRequestDetail(id: summary.id, viewerCanUpdate: true))
            viewModel.requestDetails(summary)
            let target = PullRequestPaneTarget.details(summary.id)

            XCTAssertEqual(viewModel.paneSessions[target]?.pullRequestReviewTeamValidationStatus, .valid)
            XCTAssertNil(viewModel.reviewTeamValidationTask)
            await waitForPaneContent(viewModel, target: target)
            viewModel.startAgenticThread(kind: .review)
            await waitFor { startedReviews.count == index + 1 }
            XCTAssertTrue(viewModel.paneSessions.values.allSatisfy { $0.pullRequestReviewTeamValidationStatus == .valid })
            viewModel.agenticThreadActivity.end(summary.id, kind: .review)
        }

        service.detailResult = .success(makePullRequestDetail(id: summaries[0].id, viewerCanUpdate: true))
        viewModel.requestDetails(summaries[0])

        XCTAssertEqual(viewModel.activePaneTarget, .details(summaries[0].id))
        await waitForPaneContent(viewModel, target: .details(summaries[0].id))
        XCTAssertTrue(viewModel.paneSessions.values.allSatisfy { $0.pullRequestReviewTeamValidationStatus == .valid })
        XCTAssertEqual(startedReviews, summaries.map(\.id))
        XCTAssertEqual(validationCalls, 1)
        XCTAssertEqual(refreshCalls, 0)
        XCTAssertNil(viewModel.reviewTeamValidationTask)
    }

    func testOnlyRelevantSettingsInvalidateSuccessfulTeamValidation() async {
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
        let replacementGate = PullRequestsServiceGate()
        defer { replacementGate.open() }
        var validatedModels: [String?] = []
        var refreshCalls = 0
        let pane = await openedReviewPane(
            settingsService: settingsService,
            reviewTeamSettingsValidator: { settings in
                validatedModels.append(settings.pullRequestReviewModel)
                if validatedModels.count > 1 {
                    await replacementGate.wait()
                }
            },
            refreshReviewTeamProviderDiscovery: { refreshCalls += 1 }
        )
        // A duplicate initial validation would be held at replacementGate; report it without awaiting that task.
        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }

        settingsService.update { $0.pullRequestsSelectedTab = "authored" }
        pane.viewModel.requestDetails(pane.id, origin: .screen)

        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
        XCTAssertNil(pane.viewModel.reviewTeamValidationTask)
        XCTAssertEqual(validatedModels.count, 1)

        settingsService.update { $0.pullRequestReviewModel = "replacement-model" }

        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .validating)
        await waitFor { validatedModels.count == 2 }
        XCTAssertEqual(validatedModels.last ?? nil, "replacement-model")
        replacementGate.open()
        await pane.viewModel.reviewTeamValidationTask?.value
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
        XCTAssertEqual(refreshCalls, 0)
    }

    func testExplicitRetryRefreshesDiscoveryBeforeReplacingSuccessfulValidation() async {
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
        let refreshGate = PullRequestsServiceGate()
        defer { refreshGate.open() }
        var events: [String] = []
        let pane = await openedReviewPane(
            settingsService: settingsService,
            reviewTeamSettingsValidator: { _ in events.append("validate") },
            refreshReviewTeamProviderDiscovery: {
                events.append("refresh")
                await refreshGate.wait()
            }
        )
        // An unexpected initial refresh must fail this checkpoint instead of trapping the test behind its own gate.
        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
        XCTAssertEqual(events, ["validate"])

        pane.viewModel.retryReviewTeamValidation()

        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .validating)
        await waitFor { events.last == "refresh" }
        XCTAssertEqual(events, ["validate", "refresh"])

        refreshGate.open()
        await pane.viewModel.reviewTeamValidationTask?.value

        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
        XCTAssertEqual(events, ["validate", "refresh", "validate"])
        pane.viewModel.requestDetails(pane.id, origin: .screen)
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
        XCTAssertEqual(events, ["validate", "refresh", "validate"])
    }

    func testRepeatedPaneOpensShareTheSameInFlightTeamValidation() async {
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
        let gate = PullRequestsServiceGate()
        var validationCalls = 0
        let pane = await openedReviewPane(
            settingsService: settingsService,
            reviewTeamSettingsValidator: { _ in
                validationCalls += 1
                await gate.wait()
            }
        )

        pane.viewModel.requestDetails(pane.id, origin: .screen)
        pane.viewModel.requestDetails(pane.id, origin: .screen)
        gate.open()
        await pane.viewModel.reviewTeamValidationTask?.value

        XCTAssertEqual(validationCalls, 1)
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
    }
}
