import SwiftData
import XCTest

@testable import Alveary

/// The pane lane is shared between the Pull Requests screen and a thread's
/// linked pull requests, so the root filters the active target by the surface
/// that opened it.
@MainActor
extension PullRequestsViewModelTests {
    func testScreenOriginTargetIsWithheldFromAThread() async throws {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let threadID = makeThreadIdentifier()

        viewModel.requestDetails(summary)
        XCTAssertEqual(viewModel.activePaneOrigin, .screen)
        XCTAssertEqual(viewModel.activePaneTarget(for: .screen), .details(summary.id))

        XCTAssertNil(viewModel.activePaneTarget(for: .thread(threadID)))
    }

    func testThreadOriginTargetIsWithheldFromTheScreenAndOtherThreads() async throws {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let threadID = makeThreadIdentifier()
        let otherThreadID = makeThreadIdentifier()

        viewModel.requestDetails(summary, origin: .thread(threadID))

        XCTAssertEqual(viewModel.activePaneOrigin, .thread(threadID))
        XCTAssertEqual(viewModel.activePaneTarget(for: .thread(threadID)), .details(summary.id))
        XCTAssertNil(viewModel.activePaneTarget(for: .thread(otherThreadID)))
        XCTAssertNil(viewModel.activePaneTarget(for: .screen))
    }

    /// Only one pane is active at a time, so reopening from another surface
    /// takes ownership rather than leaving both reachable.
    func testReopeningFromAnotherOriginTakesOwnership() async throws {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let threadID = makeThreadIdentifier()

        viewModel.requestDetails(summary, origin: .thread(threadID))
        viewModel.requestDetails(summary)

        XCTAssertEqual(viewModel.activePaneTarget(for: .screen), .details(summary.id))
        XCTAssertNil(viewModel.activePaneTarget(for: .thread(threadID)))
    }

    /// A project selection scopes its pane exactly like a thread does, and the
    /// origin built from a link owner matches the owner's own case.
    func testProjectOriginTargetIsWithheldFromTheScreenAndThreads() async throws {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let identifiers = makeOwnerIdentifiers()

        viewModel.requestDetails(summary, origin: PullRequestPaneOrigin(owner: .project(identifiers.project)))

        XCTAssertEqual(viewModel.activePaneOrigin, .project(identifiers.project))
        XCTAssertEqual(viewModel.activePaneTarget(for: .project(identifiers.project)), .details(summary.id))
        XCTAssertNil(viewModel.activePaneTarget(for: .thread(identifiers.thread)))
        XCTAssertNil(viewModel.activePaneTarget(for: .screen))
    }

    /// The toolbar button toggles on a lone linked pull request, and it decides
    /// by asking whether the active target is already that pane.
    func testDeactivatingAThreadPaneClearsItsScopedTarget() async throws {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let threadID = makeThreadIdentifier()

        viewModel.requestDetails(summary, origin: .thread(threadID))
        XCTAssertEqual(viewModel.activePaneTarget(for: .thread(threadID)), .details(summary.id))

        viewModel.deactivatePane()

        XCTAssertNil(viewModel.activePaneTarget(for: .thread(threadID)))
        // Route-only deactivation keeps the session so reopening is instant.
        XCTAssertNotNil(viewModel.paneSessions[.details(summary.id)])
    }

    private func makeThreadIdentifier() -> PersistentIdentifier {
        makeOwnerIdentifiers().thread
    }

    /// These origins are compared as values; no owner lookup or persistence is involved.
    func makeOwnerIdentifiers() -> (thread: PersistentIdentifier, project: PersistentIdentifier) {
        let thread = AgentThread(name: "Thread")
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        return (thread.persistentModelID, project.persistentModelID)
    }
}
