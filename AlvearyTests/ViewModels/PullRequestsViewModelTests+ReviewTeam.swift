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
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
        let isProviderReady = FlagBox()
        var validationCalls = 0
        let pane = await openedReviewPane(
            settingsService: settingsService,
            reviewTeamSettingsValidator: { _ in
                validationCalls += 1
                if !isProviderReady.value {
                    throw ReviewTeamError.invalidOutput("CLI needs repair")
                }
            }
        )
        await pane.viewModel.reviewTeamValidationTask?.value
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .invalid("CLI needs repair"))
        let callsBeforeRepair = validationCalls
        let savedSettings = settingsService.current

        isProviderReady.value = true
        pane.viewModel.requestDetails(pane.id, origin: .screen)
        await pane.viewModel.reviewTeamValidationTask?.value

        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
        XCTAssertEqual(validationCalls, callsBeforeRepair + 1)
        XCTAssertEqual(settingsService.current, savedSettings)
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
