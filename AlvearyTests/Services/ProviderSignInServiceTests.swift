@preconcurrency import AppKit
import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class ProviderSignInServiceTests: XCTestCase {
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

        XCTAssertTrue(service.startSignIn(providerID: "claude", terminalManager: terminalManager))

        let session = try XCTUnwrap(terminalManager.sessions.last)
        // `.projectAction`, not `.shell`: only that kind reports the injected command's own completion.
        XCTAssertEqual(session.kind, .projectAction)
        XCTAssertEqual(session.title, "Sign in to Claude Code")
        XCTAssertEqual(session.currentDirectory, TerminalLaunchBuilder().homeDirectory())

        let configuration = try XCTUnwrap(factory.configurations[session.id])
        XCTAssertEqual(configuration.projectActionCommand, "claude auth login")
        XCTAssertEqual(service.pendingProviderID, "claude")
    }

    func testStartSignInOpensNoTabForAProviderWithoutACommand() {
        let service = makeService()
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())

        XCTAssertFalse(service.startSignIn(providerID: "not-a-provider", terminalManager: terminalManager))

        XCTAssertTrue(terminalManager.sessions.isEmpty)
        XCTAssertNil(service.pendingProviderID)
    }

    /// The completion trigger is `TerminalManager.runningProjectActionSessionIDs` losing the session,
    /// which the app root already observes; a ready provider is what stops the tracking.
    func testFinishedSignInClearsPendingProviderOnceItReportsReady() async throws {
        let service = makeService(claudeSetup: .ready)
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())
        XCTAssertTrue(service.startSignIn(providerID: "claude", terminalManager: terminalManager))

        service.handleRunningProjectActionSessionIDsChange([])

        try await waitForPendingProviderID(nil, on: service)
    }

    func testFinishedSignInKeepsPendingProviderWhileItStillNeedsSetup() async throws {
        let (service, discovery) = makeFixture()
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())
        XCTAssertTrue(service.startSignIn(providerID: "claude", terminalManager: terminalManager))

        try await waitForRefresh(service.handleRunningProjectActionSessionIDsChange([]))

        let probes = await discovery.providerStatusesInvocations()
        XCTAssertEqual(probes, 1)
        XCTAssertEqual(service.pendingProviderID, "claude")
    }

    /// A live browser round trip must neither launch discovery nor spend the later activation retry.
    func testActivationDuringTheLiveSignInTabDoesNotSpendTheRetry() async throws {
        let (service, discovery) = makeFixture()
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())
        XCTAssertTrue(service.startSignIn(providerID: "claude", terminalManager: terminalManager))

        XCTAssertNil(service.handleAppDidBecomeActive())
        XCTAssertEqual(service.pendingProviderID, "claude")
        let liveProbes = await discovery.providerStatusesInvocations()
        XCTAssertEqual(liveProbes, 0)

        try await waitForRefresh(service.handleRunningProjectActionSessionIDsChange([]))
        XCTAssertEqual(service.pendingProviderID, "claude")
        let finishedProbes = await discovery.providerStatusesInvocations()
        XCTAssertEqual(finishedProbes, 1)

        let retry = service.handleAppDidBecomeActive()
        XCTAssertNil(service.pendingProviderID)
        try await waitForRefresh(retry)
        let retryProbes = await discovery.providerStatusesInvocations()
        XCTAssertEqual(retryProbes, 2)
    }

    /// The final activation refresh stops tracking immediately, then still completes discovery once.
    func testActivationAfterTheTabIsGoneStopsTrackingEvenWhenStillNotReady() async throws {
        let (service, discovery) = makeFixture()
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())
        XCTAssertTrue(service.startSignIn(providerID: "claude", terminalManager: terminalManager))
        try await waitForRefresh(service.handleRunningProjectActionSessionIDsChange([]))
        let finishedProbes = await discovery.providerStatusesInvocations()
        XCTAssertEqual(finishedProbes, 1)

        let retry = service.handleAppDidBecomeActive()
        XCTAssertNil(service.pendingProviderID)
        try await waitForRefresh(retry)
        let retryProbes = await discovery.providerStatusesInvocations()
        XCTAssertEqual(retryProbes, 2)

        XCTAssertNil(service.handleAppDidBecomeActive())
        XCTAssertNil(service.pendingProviderID)
        let finalProbes = await discovery.providerStatusesInvocations()
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
        claudeSetup: AgentCLIKit.AgentProviderReadinessState = .needsSetup
    ) -> ProviderSignInService {
        makeFixture(claudeSetup: claudeSetup).0
    }

    private func makeFixture(
        claudeSetup: AgentCLIKit.AgentProviderReadinessState = .needsSetup
    ) -> (ProviderSignInService, RecordingProviderDiscoveryService) {
        let base = RecordingProviderDiscoveryService(statuses: [
            .claude: AgentCLIKit.AgentProviderStatus(
                providerId: .claude,
                definition: AgentCLIKit.ClaudeProviderDefinition.definition,
                installation: .installed,
                availability: AgentCLIKit.AgentProviderAvailability(
                    providerId: .claude,
                    executablePath: "/usr/local/bin/claude"
                ),
                setup: claudeSetup,
                modelOptions: []
            )
        ])
        let service = ProviderSignInService(
            agentRegistry: DefaultAgentRegistry(),
            discoveryService: CachingAgentProviderDiscoveryService(base: base),
            settingsService: InMemorySettingsService()
        )
        return (service, base)
    }

    /// The readiness refresh runs in an unstructured `Task`, so poll rather than assert immediately.
    private func waitForPendingProviderID(
        _ expected: String?,
        on service: ProviderSignInService
    ) async throws {
        for _ in 0..<200 where service.pendingProviderID != expected {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(service.pendingProviderID, expected)
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
