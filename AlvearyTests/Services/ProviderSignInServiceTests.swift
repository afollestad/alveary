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
        let service = makeService(claudeSetup: .needsSetup)
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())
        XCTAssertTrue(service.startSignIn(providerID: "claude", terminalManager: terminalManager))

        service.handleRunningProjectActionSessionIDsChange([])
        // Draining the refresh's own task hop is enough to observe it not clearing.
        for _ in 0..<20 {
            await Task.yield()
        }

        // Still pending, so the one activation retry is still available.
        XCTAssertEqual(service.pendingProviderID, "claude")
    }

    /// The browser round trip happens while the sign-in command is still waiting, so an activation
    /// during it must not spend the one retry — nor pay discovery's fan-out.
    func testActivationDuringTheLiveSignInTabDoesNotSpendTheRetry() {
        let service = makeService(claudeSetup: .needsSetup)
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())
        XCTAssertTrue(service.startSignIn(providerID: "claude", terminalManager: terminalManager))

        service.handleAppDidBecomeActive()

        XCTAssertEqual(service.pendingProviderID, "claude")
    }

    /// Bounded at one attempt: staying pending would put discovery's fan-out on every app switch for
    /// the rest of the session.
    func testActivationAfterTheTabIsGoneStopsTrackingEvenWhenStillNotReady() async throws {
        let service = makeService(claudeSetup: .needsSetup)
        let terminalManager = TerminalManager(controllerFactory: StubTerminalControllerFactory())
        XCTAssertTrue(service.startSignIn(providerID: "claude", terminalManager: terminalManager))
        service.handleRunningProjectActionSessionIDsChange([])

        service.handleAppDidBecomeActive()
        XCTAssertNil(service.pendingProviderID)

        // A second activation is now a no-op rather than another refresh.
        service.handleAppDidBecomeActive()
        XCTAssertNil(service.pendingProviderID)
    }

    private func makeService(
        claudeSetup: AgentCLIKit.AgentProviderReadinessState = .needsSetup
    ) -> ProviderSignInService {
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
        return ProviderSignInService(
            agentRegistry: DefaultAgentRegistry(),
            discoveryService: CachingAgentProviderDiscoveryService(base: base),
            settingsService: InMemorySettingsService()
        )
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
