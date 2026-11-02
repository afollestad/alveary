import Foundation
import XCTest

@testable import Alveary

// Ignoring pull requests: hiding them from the list, "Show ignored", the row and pane actions,
// the notifications-access flow a missing scope raises, and the sync's row refresh.
@MainActor
extension PullRequestsViewModelTests {
    func testIgnoredRowsHideFromEveryTabSectionAndKeyboardOrder() async {
        let fixture = await makeIgnoreFixture(ignored: [Self.requestedID])

        await fixture.viewModel.refresh()

        let all = fixture.viewModel.visibleRows(for: .all).map(\.id.number)
        XCTAssertEqual(all, [1, 3])
        let reviewing = fixture.viewModel.visibleSections(for: .reviewing).flatMap(\.rows).map(\.id.number)
        XCTAssertEqual(reviewing, [3])
        XCTAssertEqual(fixture.viewModel.hiddenIgnoredCount(for: .reviewing), 1)
        XCTAssertEqual(fixture.viewModel.hiddenIgnoredCount(for: .authored), 0)
        // Hidden from the list only: the row stays loaded for the pane, paging, and the cache.
        XCTAssertTrue(fixture.viewModel.items.contains { $0.id == Self.requestedID })
    }

    func testShowIgnoredRevealsRowsDimmedAndPersists() async {
        let settings = InMemorySettingsService()
        let fixture = await makeIgnoreFixture(ignored: [Self.requestedID], settings: settings)
        await fixture.viewModel.refresh()

        fixture.coordinator.setShowsIgnored(true)

        XCTAssertEqual(fixture.viewModel.visibleRows(for: .all).map(\.id.number), [1, 2, 3])
        XCTAssertEqual(fixture.viewModel.hiddenIgnoredCount(for: .all), 0)
        let ignoredRows = fixture.viewModel.visibleListItems(for: .all).compactMap { item -> PullRequestRowModel? in
            guard case .row(let model) = item, model.isIgnored else {
                return nil
            }
            return model
        }
        XCTAssertEqual(ignoredRows.map(\.id), [Self.requestedID])
        XCTAssertTrue(settings.current.pullRequestsShowIgnored)
        XCTAssertTrue(PullRequestIgnoreCoordinator(ignoreService: fixture.ignoreService, settingsService: settings).showsIgnored)
    }

    func testIgnoringHidesTheRowAtOnceAndUnsubscribes() async {
        let fixture = await makeIgnoreFixture()
        fixture.service.subscriptionStatesResult = .success([Self.requestedID: Self.snapshot(Self.requestedID)])
        let gate = PullRequestsServiceGate()
        fixture.service.updateSubscriptionGate = gate
        await fixture.viewModel.refresh()

        fixture.coordinator.ignore(Self.requestedID)

        // Before any request lands: the click itself hides the row.
        XCTAssertEqual(fixture.viewModel.visibleRows(for: .all).map(\.id.number), [1, 3])
        XCTAssertTrue(fixture.coordinator.isPending(Self.requestedID))
        gate.open()
        await waitFor { !fixture.coordinator.isPending(Self.requestedID) }
        XCTAssertEqual(fixture.service.subscriptionUpdates, [.init(nodeID: "PR_2", subscribed: false)])
        XCTAssertTrue(fixture.ignoreService.isIgnored(Self.requestedID))
        XCTAssertEqual(fixture.viewModel.visibleRows(for: .all).map(\.id.number), [1, 3])
    }

    func testFailedIgnoreBringsTheRowBackAndToasts() async {
        let fixture = await makeIgnoreFixture()
        fixture.service.subscriptionStatesResult = .success([Self.requestedID: Self.snapshot(Self.requestedID)])
        fixture.service.updateSubscriptionResult = .failure(.transport("boom"))
        await fixture.viewModel.refresh()

        fixture.coordinator.ignore(Self.requestedID)
        await waitFor { !fixture.coordinator.isPending(Self.requestedID) }

        XCTAssertEqual(fixture.viewModel.visibleRows(for: .all).map(\.id.number), [1, 2, 3])
        XCTAssertEqual(fixture.toasts.messages, ["Couldn't ignore octo/alpha#2: boom"])
    }

    /// Nothing runs on the missing scope until Continue, and the browser opens only from Open
    /// GitHub, once the code is on screen.
    func testMissingScopeExplainsBeforeLaunchingAnythingThenRetries() async throws {
        let cli = OnboardingConnectGitHubCLIFake(isAuthenticated: true, deviceCode: Self.deviceCode)
        let fixture = await makeIgnoreFixture(gitHubCLI: cli)
        fixture.service.subscriptionStatesResult = .success([Self.requestedID: Self.snapshot(Self.requestedID)])
        fixture.service.updateSubscriptionResults = [.failure(.insufficientScopes)]
        await fixture.viewModel.refresh()

        fixture.coordinator.ignore(Self.requestedID)
        await waitFor { fixture.coordinator.notificationsAccessRequest != nil }

        XCTAssertEqual(fixture.coordinator.notificationsAccessRequest?.phase, .explain)
        XCTAssertTrue(cli.refreshedScopes.isEmpty)
        XCTAssertEqual(fixture.viewModel.visibleRows(for: .all).map(\.id.number), [1, 3], "The row holds while the sheet asks")

        fixture.coordinator.continueNotificationsAccess()
        await waitFor { fixture.coordinator.notificationsAccessRequest?.phase == .code(Self.deviceCode, didOpenBrowser: false) }
        XCTAssertEqual(cli.refreshedScopes, [["notifications"]])
        XCTAssertTrue(fixture.openedURLs.isEmpty)

        fixture.coordinator.copyNotificationsAccessCode()
        fixture.coordinator.openNotificationsAccessBrowser()
        XCTAssertEqual(fixture.copiedText, ["ABCD-1234"])
        XCTAssertEqual(fixture.openedURLs, [Self.deviceCode.verificationURL])
        XCTAssertEqual(fixture.coordinator.notificationsAccessRequest?.phase, .code(Self.deviceCode, didOpenBrowser: true))

        await waitFor { cli.isAwaitingAuthentication }
        cli.completeAuthentication(with: true)
        await waitFor { fixture.coordinator.notificationsAccessRequest == nil && !fixture.coordinator.isPending(Self.requestedID) }

        XCTAssertEqual(fixture.service.subscriptionUpdates.count, 2)
        XCTAssertTrue(fixture.ignoreService.isIgnored(Self.requestedID))
        XCTAssertEqual(fixture.viewModel.visibleRows(for: .all).map(\.id.number), [1, 3])
    }

    func testCancellingAccessRevertsEveryParkedAction() async {
        let cli = OnboardingConnectGitHubCLIFake(isAuthenticated: true, deviceCode: Self.deviceCode)
        let fixture = await makeIgnoreFixture(gitHubCLI: cli)
        fixture.service.subscriptionStatesResult = .success([
            Self.authoredID: Self.snapshot(Self.authoredID),
            Self.requestedID: Self.snapshot(Self.requestedID)
        ])
        fixture.service.updateSubscriptionResult = .failure(.insufficientScopes)
        await fixture.viewModel.refresh()

        fixture.coordinator.ignore(Self.authoredID)
        fixture.coordinator.ignore(Self.requestedID)
        // A second scope failure joins the open request rather than raising another sheet.
        await waitFor { fixture.coordinator.notificationsAccessRequest?.pendingActions.count == 2 }
        XCTAssertEqual(fixture.viewModel.visibleRows(for: .all).map(\.id.number), [3])

        fixture.coordinator.cancelNotificationsAccess()

        XCTAssertNil(fixture.coordinator.notificationsAccessRequest)
        // Nothing was launched, so nothing is stopped — a sign-in running from Settings survives.
        XCTAssertFalse(cli.didCancelAuthentication)
        XCTAssertEqual(fixture.viewModel.visibleRows(for: .all).map(\.id.number), [1, 2, 3])
    }

    func testUnconfirmedAccessOffersRetryWhileTheRowHolds() async {
        let cli = OnboardingConnectGitHubCLIFake(isAuthenticated: true, deviceCode: Self.deviceCode)
        let fixture = await makeIgnoreFixture(gitHubCLI: cli)
        fixture.service.subscriptionStatesResult = .success([Self.requestedID: Self.snapshot(Self.requestedID)])
        fixture.service.updateSubscriptionResult = .failure(.insufficientScopes)
        await fixture.viewModel.refresh()
        fixture.coordinator.ignore(Self.requestedID)
        await waitFor { fixture.coordinator.notificationsAccessRequest != nil }

        fixture.coordinator.continueNotificationsAccess()
        await waitFor { cli.isAwaitingAuthentication }
        cli.completeAuthentication(with: false)
        await waitFor {
            if case .failed? = fixture.coordinator.notificationsAccessRequest?.phase { return true }
            return false
        }
        XCTAssertEqual(fixture.viewModel.visibleRows(for: .all).map(\.id.number), [1, 3])

        fixture.coordinator.retryNotificationsAccess()
        await waitFor { cli.refreshedScopes.count == 2 && cli.isAwaitingAuthentication }
        fixture.coordinator.cancelNotificationsAccess()
        XCTAssertTrue(cli.didCancelAuthentication)
        XCTAssertEqual(fixture.viewModel.visibleRows(for: .all).map(\.id.number), [1, 2, 3])
    }

    /// The sync's rows refresh what the buckets already hold, keep each bucket's involvement, and
    /// never add a row a search did not return.
    func testSyncRefreshesHeldRowsWithoutInsertingOrChangingInvolvement() async {
        let stranger = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 99)
        let fixture = await makeIgnoreFixture(ignored: [Self.authoredID, stranger])
        // The list lands first; the sync and the bucket fetch otherwise race, and in production
        // either order is right since both read GitHub at the same moment.
        await fixture.viewModel.refresh()
        fixture.service.subscriptionStatesResult = .success([
            Self.authoredID: Self.snapshot(Self.authoredID, title: "Renamed on GitHub"),
            stranger: Self.snapshot(stranger)
        ])

        fixture.viewModel.applyRefreshedSummaries(await fixture.ignoreService.reconcileIfNeeded(force: true))

        let row = fixture.viewModel.items.first { $0.id == Self.authoredID }
        XCTAssertEqual(row?.title, "Renamed on GitHub")
        XCTAssertEqual(row?.isAuthored, true)
        XCTAssertFalse(fixture.viewModel.items.contains { $0.id == stranger })
    }

    /// Ignoring the pull request whose pane is open leaves the pane alone, and the arrow keys
    /// then start from the edge of what is visible, as they do with no selection.
    func testArrowKeysStillMoveWhenTheOpenRowIsHidden() async {
        let fixture = await makeIgnoreFixture()
        fixture.service.subscriptionStatesResult = .success([Self.requestedID: Self.snapshot(Self.requestedID)])
        await fixture.viewModel.refresh()
        guard let requested = fixture.viewModel.items.first(where: { $0.id == Self.requestedID }) else {
            return XCTFail("The fixture's review-requested row did not load")
        }
        fixture.viewModel.requestDetails(requested)

        fixture.coordinator.ignore(Self.requestedID)
        await waitFor { !fixture.coordinator.isPending(Self.requestedID) }

        XCTAssertTrue(fixture.viewModel.isDetailActive(Self.requestedID))
        let rows = fixture.viewModel.visibleSections(for: .all).flatMap(\.rows)
        let next = fixture.viewModel.selectAdjacentRow(in: rows, forward: true)
        XCTAssertEqual(next, rows.first?.id)
        XCTAssertNotEqual(next, Self.requestedID)
    }
}

// MARK: - Fixture

@MainActor
private struct IgnoreFixture {
    let viewModel: PullRequestsViewModel
    let service: StubPullRequestsService
    let coordinator: PullRequestIgnoreCoordinator
    let ignoreService: PullRequestIgnoreService
    let toasts: ToastRecorder
    let recorder: IgnoreFixtureRecorder

    var openedURLs: [URL] { recorder.openedURLs }
    var copiedText: [String] { recorder.copiedText }
}

@MainActor
private final class IgnoreFixtureRecorder {
    var openedURLs: [URL] = []
    var copiedText: [String] = []
}

@MainActor
private extension PullRequestsViewModelTests {
    static let authoredID = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 1)
    static let requestedID = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 2)
    static let deviceCode = GitHubDeviceCode(
        code: "ABCD-1234",
        verificationURL: URL(string: "https://github.com/login/device") ?? URL(fileURLWithPath: "/")
    )

    /// An authored row, a review-requested one, and a previously reviewed one, with `ignored`
    /// already on the ignore list.
    func makeIgnoreFixture(
        ignored: [PullRequestIdentifier] = [],
        settings: InMemorySettingsService? = nil,
        gitHubCLI: (any GitHubCLIService)? = nil
    ) async -> IgnoreFixture {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [
                makePullRequestSummary(number: 1, isAuthored: true),
                makePullRequestSummary(number: 2, isReviewRequested: true),
                makePullRequestSummary(number: 3, hasReviewed: true)
            ],
            warnings: []
        ))
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("ignored-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: storeURL) }
        let store = IgnoredPullRequestsStore(fileURL: storeURL)
        let seededAt = Date(timeIntervalSince1970: 1_000)
        await store.save(IgnoredPullRequestsSnapshot(
            entries: ignored.map { IgnoredPullRequestEntry(id: $0, ignoredAt: seededAt, lastSeenAt: Date()) },
            lastReconciledAt: nil
        ))
        let ignoreService = PullRequestIgnoreService(service: service, store: store)
        await ignoreService.loadIfNeeded()
        let toasts = ToastRecorder()
        let recorder = IgnoreFixtureRecorder()
        let coordinator = PullRequestIgnoreCoordinator(
            ignoreService: ignoreService,
            gitHubCLI: gitHubCLI,
            settingsService: settings,
            presentToast: { toasts.record($0) },
            openURL: { recorder.openedURLs.append($0) },
            copyToPasteboard: { recorder.copiedText.append($0) }
        )
        let viewModel = makePullRequestsViewModel(service: service, settingsService: settings, ignoring: coordinator)
        return IgnoreFixture(
            viewModel: viewModel,
            service: service,
            coordinator: coordinator,
            ignoreService: ignoreService,
            toasts: toasts,
            recorder: recorder
        )
    }

    static func snapshot(_ id: PullRequestIdentifier, title: String = "Change something") -> PullRequestSubscriptionSnapshot {
        PullRequestSubscriptionSnapshot(
            nodeID: "PR_\(id.number)",
            summary: makePullRequestSummary(number: id.number, repo: id.nameWithOwner, title: title),
            subscription: .unsubscribed,
            viewerCanSubscribe: true
        )
    }
}
