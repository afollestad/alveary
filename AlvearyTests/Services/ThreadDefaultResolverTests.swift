import AgentCLIKit
import XCTest

@testable import Alveary

/// `isSetupReady` is now auth-backed for Claude, so a signed-out CLI reaches this resolver as
/// `.needsSetup`. These cover that it is refused rather than started and then failed on the first turn.
final class ThreadDefaultResolverTests: XCTestCase {
    func testSignedOutHarnessIsNotReady() {
        let resolution = ThreadDefaultResolver.resolve(
            settings: AppSettings(),
            harnessOrdering: ["claude"],
            harnessStatuses: ["claude": Self.status(for: .claude, setup: .needsSetup)]
        )

        XCTAssertNil(resolution.harnessID)
        XCTAssertFalse(resolution.hasReadyHarness)
        XCTAssertEqual(resolution.readyHarnessIDs, [])
    }

    func testSignedOutHarnessFallsBackToAnotherReadyHarness() {
        var settings = AppSettings()
        settings.defaultHarness = "claude"

        let resolution = ThreadDefaultResolver.resolve(
            settings: settings,
            harnessOrdering: ["claude", "codex"],
            harnessStatuses: [
                "claude": Self.status(for: .claude, setup: .needsSetup),
                "codex": Self.status(for: .codex, setup: .ready)
            ]
        )

        XCTAssertEqual(resolution.harnessID, "codex")
        XCTAssertEqual(resolution.readyHarnessIDs, ["codex"])
    }

    /// An inconclusive probe reports `.ready`, so this is what an installed-and-working Claude looks
    /// like whether the probe answered or timed out.
    func testReadyHarnessResolves() {
        let resolution = ThreadDefaultResolver.resolve(
            settings: AppSettings(),
            harnessOrdering: ["claude"],
            harnessStatuses: ["claude": Self.status(for: .claude, setup: .ready)]
        )

        XCTAssertEqual(resolution.harnessID, "claude")
        XCTAssertEqual(resolution.readyHarnessIDs, ["claude"])
    }

    /// Before discovery reports statuses, the fallback options must be the real Claude catalog — the one-row
    /// harness-default placeholder resolved nothing, so pre-discovery UI flashed raw model ids.
    func testEmptyStatusesFallBackToTheStaticClaudeCatalog() {
        let claudeOptions = ThreadDefaultResolver.modelOptions(for: "claude", harnessStatuses: [:])
        let codexOptions = ThreadDefaultResolver.modelOptions(for: "codex", harnessStatuses: [:])

        XCTAssertEqual(claudeOptions.filter(\.isDefault).map(\.id), ["claude-sonnet-5"])
        XCTAssertEqual(codexOptions.map(\.id), ["default"])
    }

    /// The static-fallback paths (host tools, pull-request threads, nil-discovery view models) used to reset a stored
    /// pinned model to the default sentinel because the placeholder options could not resolve it.
    func testStaticFallbackPreservesAStoredPinnedModel() {
        var settings = AppSettings()
        settings.defaultHarness = "claude"
        settings.defaultModel = "claude-opus-5"

        let resolution = ThreadDefaultResolver.resolve(
            settings: settings,
            harnessOrdering: ["claude"],
            harnessStatuses: [:],
            allowStaticFallback: true
        )

        XCTAssertEqual(resolution.harnessID, "claude")
        XCTAssertEqual(resolution.storedThreadModel, "claude-opus-5")
    }

    private static func status(
        for harnessId: AgentCLIKit.AgentHarnessID,
        setup: AgentCLIKit.AgentHarnessReadinessState
    ) -> AgentCLIKit.AgentHarnessStatus {
        AgentCLIKit.AgentHarnessStatus(
            harnessId: harnessId,
            definition: harnessId == .claude
                ? AgentCLIKit.ClaudeHarnessDefinition.definition
                : AgentCLIKit.CodexHarnessDefinition.definition,
            installation: .installed,
            availability: AgentCLIKit.AgentHarnessAvailability(
                harnessId: harnessId,
                executablePath: "/usr/local/bin/\(harnessId.rawValue)"
            ),
            setup: setup,
            modelOptions: []
        )
    }
}
