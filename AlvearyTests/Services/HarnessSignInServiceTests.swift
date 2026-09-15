@preconcurrency import AppKit
import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class HarnessSignInServiceTests: XCTestCase {
    func testSignInCommandComesFromRegistry() {
        let service = makeService()

        XCTAssertEqual(service.signInCommand(for: "claude"), "claude auth login")
        XCTAssertEqual(service.signInCommand(for: "codex"), "codex login")
        XCTAssertNil(service.signInCommand(for: "not-a-provider"))
    }

    func testStartSignInOpensProjectActionTabRunningTheRegistryCommand() throws {
        let service = makeService()
        let factory = StubTerminalControllerFactory()
        let terminalManager = TerminalManager(controllerFactory: factory)

        XCTAssertTrue(service.startSignIn(harnessID: "claude", terminalManager: terminalManager))

        let session = try XCTUnwrap(terminalManager.sessions.last)
        // `.projectAction`, not `.shell`: only that kind reports the injected command's own completion.
        XCTAssertEqual(session.kind, .projectAction)
        XCTAssertEqual(session.title, "Sign in to Claude Code")
        XCTAssertEqual(session.currentDirectory, TerminalLaunchBuilder().homeDirectory())

        let configuration = try XCTUnwrap(factory.configurations[session.id])
        XCTAssertEqual(configuration.projectActionCommand, "claude auth login")
        XCTAssertEqual(service.pendingHarnessID, "claude")
    }

    func testStartSignInOpensNoTabForAHarnessWithoutACommand() {
        let service = makeService()
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())

        XCTAssertFalse(service.startSignIn(harnessID: "not-a-provider", terminalManager: terminalManager))

        XCTAssertTrue(terminalManager.sessions.isEmpty)
        XCTAssertNil(service.pendingHarnessID)
    }

    /// The completion trigger is `TerminalManager.runningProjectActionSessionIDs` losing the session,
    /// which the app root already observes; a ready harness is what stops the tracking.
    func testFinishedSignInClearsPendingHarnessOnceItReportsReady() async throws {
        let service = makeService(claudeSetup: .ready)
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())
        XCTAssertTrue(service.startSignIn(harnessID: "claude", terminalManager: terminalManager))

        service.handleRunningProjectActionSessionIDsChange([])

        try await waitForPendingHarnessID(nil, on: service)
    }

    func testFinishedSignInKeepsPendingHarnessWhileItStillNeedsSetup() async throws {
        let (service, discovery) = makeFixture()
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())
        XCTAssertTrue(service.startSignIn(harnessID: "claude", terminalManager: terminalManager))

        try await waitForRefresh(service.handleRunningProjectActionSessionIDsChange([]))

        let probes = await discovery.harnessStatusesInvocations()
        XCTAssertEqual(probes, 1)
        XCTAssertEqual(service.pendingHarnessID, "claude")
    }

    /// A live browser round trip must neither launch discovery nor spend the later activation retry.
    func testActivationDuringTheLiveSignInTabDoesNotSpendTheRetry() async throws {
        let (service, discovery) = makeFixture()
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())
        XCTAssertTrue(service.startSignIn(harnessID: "claude", terminalManager: terminalManager))

        XCTAssertNil(service.handleAppDidBecomeActive())
        XCTAssertEqual(service.pendingHarnessID, "claude")
        let liveProbes = await discovery.harnessStatusesInvocations()
        XCTAssertEqual(liveProbes, 0)

        try await waitForRefresh(service.handleRunningProjectActionSessionIDsChange([]))
        XCTAssertEqual(service.pendingHarnessID, "claude")
        let finishedProbes = await discovery.harnessStatusesInvocations()
        XCTAssertEqual(finishedProbes, 1)

        let retry = service.handleAppDidBecomeActive()
        XCTAssertNil(service.pendingHarnessID)
        try await waitForRefresh(retry)
        let retryProbes = await discovery.harnessStatusesInvocations()
        XCTAssertEqual(retryProbes, 2)
    }

    /// The final activation refresh stops tracking immediately, then still completes discovery once.
    func testActivationAfterTheTabIsGoneStopsTrackingEvenWhenStillNotReady() async throws {
        let (service, discovery) = makeFixture()
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())
        XCTAssertTrue(service.startSignIn(harnessID: "claude", terminalManager: terminalManager))
        try await waitForRefresh(service.handleRunningProjectActionSessionIDsChange([]))
        let finishedProbes = await discovery.harnessStatusesInvocations()
        XCTAssertEqual(finishedProbes, 1)

        let retry = service.handleAppDidBecomeActive()
        XCTAssertNil(service.pendingHarnessID)
        try await waitForRefresh(retry)
        let retryProbes = await discovery.harnessStatusesInvocations()
        XCTAssertEqual(retryProbes, 2)

        XCTAssertNil(service.handleAppDidBecomeActive())
        XCTAssertNil(service.pendingHarnessID)
        let finalProbes = await discovery.harnessStatusesInvocations()
        XCTAssertEqual(finalProbes, 2)
    }

    /// Probe entry alone precedes status consumption; observe the actual scheduled task finishing.
    private func waitForRefresh(_ scheduledTask: Task<Void, Never>?) async throws {
        let task = try XCTUnwrap(scheduledTask)
        let completed = expectation(description: "Sign-in readiness refresh completed")
        let observer = Task {
            await task.value
            completed.fulfill()
        }
        defer {
            task.cancel()
            observer.cancel()
        }
        await fulfillment(of: [completed], timeout: 3)
    }

    private func makeService(
        claudeSetup: AgentCLIKit.AgentHarnessReadinessState = .needsSetup
    ) -> HarnessSignInService {
        makeFixture(claudeSetup: claudeSetup).0
    }

    private func makeFixture(
        claudeSetup: AgentCLIKit.AgentHarnessReadinessState = .needsSetup
    ) -> (HarnessSignInService, RecordingHarnessDiscoveryService) {
        let base = RecordingHarnessDiscoveryService(statuses: [
            .claude: AgentCLIKit.AgentHarnessStatus(
                harnessId: .claude,
                definition: AgentCLIKit.ClaudeHarnessDefinition.definition,
                installation: .installed,
                availability: AgentCLIKit.AgentHarnessAvailability(
                    harnessId: .claude,
                    executablePath: "/usr/local/bin/claude"
                ),
                setup: claudeSetup,
                modelOptions: []
            )
        ])
        let service = HarnessSignInService(
            agentRegistry: DefaultAgentRegistry(),
            discoveryService: CachingAgentHarnessDiscoveryService(base: base),
            settingsService: InMemorySettingsService()
        )
        return (service, base)
    }

    /// The readiness refresh runs in an unstructured `Task`, so poll rather than assert immediately.
    private func waitForPendingHarnessID(
        _ expected: String?,
        on service: HarnessSignInService
    ) async throws {
        for _ in 0..<200 where service.pendingHarnessID != expected {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(service.pendingHarnessID, expected)
    }
}

@MainActor
private final class StubTerminalControllerFactory: TerminalSessionControllerFactory {
    private(set) var configurations: [UUID: TerminalLaunchConfiguration] = [:]

    func makeController(
        sessionID: UUID,
        configuration: TerminalLaunchConfiguration,
        delegate: any TerminalSessionControllerDelegate
    ) -> any TerminalSessionControlling {
        configurations[sessionID] = configuration
        return StubTerminalController()
    }
}

@MainActor
private final class StubTerminalController: TerminalSessionControlling {
    let view = NSView()

    func start() {}
    func terminate() {}
    func requestFocus() {}
    func reapplyTheme() {}
}
