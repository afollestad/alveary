import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension PullRequestsViewModelTests {
    func testRetryReplacesTimedOutDiscoveryWithoutWaitingForTheAbandonedProbe() async {
        let discovery = ReviewTeamRetryDiscovery()
        let cache = CachingAgentHarnessDiscoveryService(base: discovery)
        let deadlines = [PullRequestsServiceGate(), PullRequestsServiceGate()]
        var deadlineCalls = 0
        defer {
            discovery.firstProbe.open()
            discovery.replacementProbe.open()
            deadlines.forEach { $0.open() }
        }
        let pane = await openedReviewPane(
            settingsService: reviewTeamValidationSettings(),
            reviewTeamSettingsValidator: { _ in
                _ = await cache.harnessStatuses(projectURL: nil)
            },
            reviewTeamValidationSleeper: {
                guard deadlines.indices.contains(deadlineCalls) else {
                    return XCTFail("Unexpected extra validation deadline")
                }
                let gate = deadlines[deadlineCalls]
                deadlineCalls += 1
                await gate.wait()
            },
            refreshReviewTeamHarnessDiscovery: { await cache.refresh() }
        )
        await waitFor { discovery.calls == 1 && deadlineCalls == 1 }
        let abandonedValidation = pane.viewModel.reviewTeamValidationTask
        let deadline = pane.viewModel.reviewTeamValidationDeadlineTask

        deadlines[0].open()
        await deadline?.value
        XCTAssertEqual(
            pane.session?.pullRequestReviewTeamValidationStatus,
            .failed("Review team check timed out. Try again.")
        )

        pane.viewModel.retryReviewTeamValidation()
        await waitFor { discovery.calls == 2 && deadlineCalls == 2 }
        let retry = pane.viewModel.reviewTeamValidationTask
        let retryDeadline = pane.viewModel.reviewTeamValidationDeadlineTask
        discovery.replacementProbe.open()
        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }

        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
        XCTAssertEqual(discovery.completedCalls, [2], "Retry must finish while the abandoned probe remains suspended")
        XCTAssertEqual(discovery.calls, 2, "Validation must consume the cache populated by its recovery refresh")

        discovery.firstProbe.open()
        deadlines.forEach { $0.open() }
        await abandonedValidation?.value
        await retry?.value
        await retryDeadline?.value
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
    }

    func testTeamValidationTimeoutAndRetryReachEveryRetainedPane() async {
        let harness = ReviewTeamValidationHarness(outcomes: [.success(()), .success(())])
        let pane = await openedValidationPane(harness)
        let other = makePullRequestSummary(number: 8)
        await harness.run(pane.viewModel) {
            pane.viewModel.requestDetails(other)
            await harness.waitForAttempts(1)
            let expiredValidation = pane.viewModel.reviewTeamValidationTask
            let deadline = pane.viewModel.reviewTeamValidationDeadlineTask

            harness.deadlines[0].open()
            await deadline?.value

            let failed = PullRequestReviewTeamValidationStatus.failed("Review team check timed out. Try again.")
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, failed)
            XCTAssertEqual(pane.viewModel.paneSessions[.details(other.id)]?.pullRequestReviewTeamValidationStatus, failed)
            XCTAssertNil(pane.viewModel.reviewTeamValidationTask)
            XCTAssertNil(pane.viewModel.reviewTeamValidationDeadlineTask)
            XCTAssertNil(pane.viewModel.reviewTeamValidationToken)
            XCTAssertTrue(expiredValidation?.isCancelled == true)

            // A harness that ignores cancellation must not resurrect a timed-out check.
            harness.validations[0].open()
            await expiredValidation?.value
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, failed)

            pane.viewModel.retryReviewTeamValidation()
            harness.capture(pane.viewModel)
            pane.viewModel.retryReviewTeamValidation()
            pane.viewModel.requestDetails(pane.id, origin: .screen)
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .validating)
            await harness.waitForAttempts(2)
            XCTAssertEqual(harness.settings.count, 2)

            let retry = pane.viewModel.reviewTeamValidationTask
            harness.validations[1].open()
            await retry?.value
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
            XCTAssertEqual(pane.viewModel.paneSessions[.details(other.id)]?.pullRequestReviewTeamValidationStatus, .valid)
        }
    }

    func testLateTeamValidationFailureCannotOverwriteASuccessfulRetry() async {
        let harness = ReviewTeamValidationHarness(outcomes: [.failure(ReviewTeamError.invalidOutput("Old failure")), .success(())])
        let pane = await openedValidationPane(harness)
        await harness.run(pane.viewModel) {
            await harness.waitForAttempts(1)
            let expiredValidation = pane.viewModel.reviewTeamValidationTask
            let deadline = pane.viewModel.reviewTeamValidationDeadlineTask
            harness.deadlines[0].open()
            await deadline?.value

            pane.viewModel.retryReviewTeamValidation()
            harness.capture(pane.viewModel)
            await harness.waitForAttempts(2)
            let retry = pane.viewModel.reviewTeamValidationTask
            harness.validations[1].open()
            await retry?.value
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)

            harness.validations[0].open()
            await expiredValidation?.value
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
        }
    }

    func testInterruptedTeamValidationCanRetryWithoutItsOldDeadlineExpiringTheRetry() async {
        let harness = ReviewTeamValidationHarness(outcomes: [.failure(CancellationError()), .success(())])
        let pane = await openedValidationPane(harness)
        await harness.run(pane.viewModel) {
            await harness.waitForAttempts(1)
            let validation = pane.viewModel.reviewTeamValidationTask
            let oldDeadline = pane.viewModel.reviewTeamValidationDeadlineTask
            harness.validations[0].open()
            await validation?.value

            XCTAssertEqual(
                pane.session?.pullRequestReviewTeamValidationStatus,
                .failed("Review team check was interrupted. Try again.")
            )
            XCTAssertNil(pane.viewModel.reviewTeamValidationTask)
            XCTAssertTrue(oldDeadline?.isCancelled == true)

            pane.viewModel.retryReviewTeamValidation()
            harness.capture(pane.viewModel)
            await harness.waitForAttempts(2)
            harness.deadlines[0].open()
            await oldDeadline?.value
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .validating)

            let retry = pane.viewModel.reviewTeamValidationTask
            harness.validations[1].open()
            await retry?.value
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
        }
    }

    func testCompletedTeamValidationIgnoresItsLateDeadline() async {
        let cases: [(Result<Void, Error>, PullRequestReviewTeamValidationStatus)] = [
            (.success(()), .valid),
            (.failure(ReviewTeamError.invalidOutput("CLI needs repair")), .invalid("CLI needs repair"))
        ]
        for (outcome, expectedStatus) in cases {
            let harness = ReviewTeamValidationHarness(outcomes: [outcome])
            let pane = await openedValidationPane(harness)
            await harness.run(pane.viewModel) {
                await harness.waitForAttempts(1)
                let validation = pane.viewModel.reviewTeamValidationTask
                let deadline = pane.viewModel.reviewTeamValidationDeadlineTask
                harness.validations[0].open()
                await validation?.value
                XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, expectedStatus)
                XCTAssertTrue(deadline?.isCancelled == true)

                harness.deadlines[0].open()
                await deadline?.value
                XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, expectedStatus)
                XCTAssertNil(pane.viewModel.reviewTeamValidationTask)
                XCTAssertNil(pane.viewModel.reviewTeamValidationDeadlineTask)
            }
        }
    }

    func testOnlyReviewSettingsReplaceAnInFlightTeamValidationAndItsDeadline() async {
        let settingsService = reviewTeamValidationSettings()
        let harness = ReviewTeamValidationHarness(outcomes: [.failure(CancellationError()), .success(())])
        let pane = await openedValidationPane(harness, settingsService: settingsService)
        await harness.run(pane.viewModel) {
            await harness.waitForAttempts(1)
            let oldValidation = pane.viewModel.reviewTeamValidationTask
            let oldDeadline = pane.viewModel.reviewTeamValidationDeadlineTask
            let oldToken = pane.viewModel.reviewTeamValidationToken

            settingsService.update { $0.pullRequestsSelectedTab = "authored" }
            pane.viewModel.requestDetails(pane.id, origin: .screen)
            XCTAssertEqual(pane.viewModel.reviewTeamValidationToken, oldToken)
            XCTAssertFalse(oldValidation?.isCancelled == true)
            XCTAssertFalse(oldDeadline?.isCancelled == true)

            settingsService.update { $0.pullRequestReviewModel = "replacement-model" }
            harness.capture(pane.viewModel)
            await harness.waitForAttempts(2)
            XCTAssertNotEqual(pane.viewModel.reviewTeamValidationToken, oldToken)
            XCTAssertEqual(harness.settings.last?.pullRequestReviewModel, "replacement-model")
            XCTAssertTrue(oldValidation?.isCancelled == true)
            XCTAssertTrue(oldDeadline?.isCancelled == true)

            harness.validations[0].open()
            harness.deadlines[0].open()
            await oldValidation?.value
            await oldDeadline?.value
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .validating)

            let current = pane.viewModel.reviewTeamValidationTask
            harness.validations[1].open()
            await current?.value
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
        }
    }

    func testSwitchingToSingleAgentDisownsTeamValidationAndItsDeadline() async {
        let settingsService = reviewTeamValidationSettings()
        let harness = ReviewTeamValidationHarness(outcomes: [.success(())])
        let pane = await openedValidationPane(harness, settingsService: settingsService)
        await harness.run(pane.viewModel) {
            await harness.waitForAttempts(1)
            let validation = pane.viewModel.reviewTeamValidationTask
            let deadline = pane.viewModel.reviewTeamValidationDeadlineTask
            settingsService.update { $0.pullRequestReviewMode = .singleAgent }

            XCTAssertEqual(pane.session?.pullRequestReviewMode, .singleAgent)
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .notRequired)
            XCTAssertNil(pane.viewModel.reviewTeamValidationTask)
            XCTAssertNil(pane.viewModel.reviewTeamValidationDeadlineTask)
            XCTAssertNil(pane.viewModel.reviewTeamValidationToken)

            harness.validations[0].open()
            harness.deadlines[0].open()
            await validation?.value
            await deadline?.value
            XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .notRequired)
            XCTAssertNil(pane.viewModel.reviewTeamValidationTask)
        }
    }

    func testPendingTeamValidationDoesNotRetainTheViewModel() async {
        let harness = ReviewTeamValidationHarness(outcomes: [.success(())])
        var viewModel: PullRequestsViewModel? = makePullRequestsViewModel(
            service: StubPullRequestsService(),
            settingsService: reviewTeamValidationSettings(),
            reviewTeamSettingsValidator: harness.validate,
            reviewTeamValidationSleeper: harness.sleep
        )
        weak let releasedViewModel = viewModel
        let validation = viewModel?.reviewTeamValidationTask
        let deadline = viewModel?.reviewTeamValidationDeadlineTask
        await harness.waitForAttempts(1)

        viewModel = nil

        XCTAssertNil(releasedViewModel)
        XCTAssertTrue(validation?.isCancelled == true)
        XCTAssertTrue(deadline?.isCancelled == true)
        harness.validations[0].open()
        harness.deadlines[0].open()
        await validation?.value
        await deadline?.value
    }

    private func openedValidationPane(
        _ harness: ReviewTeamValidationHarness,
        settingsService: InMemorySettingsService? = nil
    ) async -> OpenedReviewPane {
        await openedReviewPane(
            settingsService: settingsService ?? reviewTeamValidationSettings(),
            reviewTeamSettingsValidator: harness.validate,
            reviewTeamValidationSleeper: harness.sleep
        )
    }

    private func reviewTeamValidationSettings() -> InMemorySettingsService {
        let settingsService = InMemorySettingsService()
        settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
        return settingsService
    }
}

/// Both operations deliberately ignore cancellation so tests can release obsolete work after its replacement settles.
@MainActor
private final class ReviewTeamValidationHarness {
    let validations: [PullRequestsServiceGate]
    let deadlines: [PullRequestsServiceGate]
    private let outcomes: [Result<Void, Error>]
    private var tasks: [Task<Void, Never>] = []
    private(set) var settings: [AppSettings] = []
    private(set) var sleepCalls = 0

    init(outcomes: [Result<Void, Error>]) {
        self.outcomes = outcomes
        validations = outcomes.map { _ in PullRequestsServiceGate() }
        deadlines = outcomes.map { _ in PullRequestsServiceGate() }
    }

    func validate(_ settings: AppSettings) async throws {
        let index = self.settings.count
        self.settings.append(settings)
        guard validations.indices.contains(index) else {
            XCTFail("Unexpected extra review-team validation")
            return
        }
        await validations[index].wait()
        try outcomes[index].get()
    }

    func sleep() async throws {
        let index = sleepCalls
        sleepCalls += 1
        guard deadlines.indices.contains(index) else {
            XCTFail("Unexpected extra review-team deadline")
            return
        }
        await deadlines[index].wait()
    }

    func waitForAttempts(_ count: Int) async {
        await waitFor { self.settings.count == count && self.sleepCalls == count }
    }

    func capture(_ viewModel: PullRequestsViewModel) {
        tasks.append(contentsOf: [viewModel.reviewTeamValidationTask, viewModel.reviewTeamValidationDeadlineTask].compactMap { $0 })
    }

    func run(_ viewModel: PullRequestsViewModel, operation: () async -> Void) async {
        capture(viewModel)
        await operation()
        capture(viewModel)
        for task in tasks { task.cancel() }
        for gate in validations + deadlines { gate.open() }
        for task in tasks { await task.value }
    }
}

/// A cold probe that ignores cancellation, with independent release of its replacement during Retry.
@MainActor
private final class ReviewTeamRetryDiscovery: AgentHarnessDiscoveryService {
    let firstProbe = PullRequestsServiceGate()
    let replacementProbe = PullRequestsServiceGate()
    private(set) var calls = 0
    private(set) var completedCalls: [Int] = []

    func harnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        calls += 1
        let call = calls
        await (call == 1 ? firstProbe : replacementProbe).wait()
        completedCalls.append(call)
        return [:]
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { [:] }
    func availableHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { [:] }
    func modelOptions(for harnessId: AgentHarnessID) async -> [AgentModelOption] { [] }
    func stableHarnessOrdering() async -> [AgentHarnessID] { [] }
}
