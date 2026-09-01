import AgentCLIKit
import XCTest

@testable import Alveary

/// `isSetupReady` is now auth-backed for Claude, so a signed-out CLI reaches this resolver as
/// `.needsSetup`. These cover that it is refused rather than started and then failed on the first turn.
final class ThreadDefaultResolverTests: XCTestCase {
    func testSignedOutProviderIsNotReady() {
        let resolution = ThreadDefaultResolver.resolve(
            settings: AppSettings(),
            providerOrdering: ["claude"],
            providerStatuses: ["claude": Self.status(for: .claude, setup: .needsSetup)]
        )

        XCTAssertNil(resolution.providerID)
        XCTAssertFalse(resolution.hasReadyProvider)
        XCTAssertEqual(resolution.readyProviderIDs, [])
    }

    func testSignedOutProviderFallsBackToAnotherReadyProvider() {
        var settings = AppSettings()
        settings.defaultProvider = "claude"

        let resolution = ThreadDefaultResolver.resolve(
            settings: settings,
            providerOrdering: ["claude", "codex"],
            providerStatuses: [
                "claude": Self.status(for: .claude, setup: .needsSetup),
                "codex": Self.status(for: .codex, setup: .ready)
            ]
        )

        XCTAssertEqual(resolution.providerID, "codex")
        XCTAssertEqual(resolution.readyProviderIDs, ["codex"])
    }

    /// An inconclusive probe reports `.ready`, so this is what an installed-and-working Claude looks
    /// like whether the probe answered or timed out.
    func testReadyProviderResolves() {
        let resolution = ThreadDefaultResolver.resolve(
            settings: AppSettings(),
            providerOrdering: ["claude"],
            providerStatuses: ["claude": Self.status(for: .claude, setup: .ready)]
        )

        XCTAssertEqual(resolution.providerID, "claude")
        XCTAssertEqual(resolution.readyProviderIDs, ["claude"])
    }

    /// Before discovery reports statuses, the fallback options must be the real Claude catalog — the one-row
    /// provider-default placeholder resolved nothing, so pre-discovery UI flashed raw model ids.
    func testEmptyStatusesFallBackToTheStaticClaudeCatalog() {
        let claudeOptions = ThreadDefaultResolver.modelOptions(for: "claude", providerStatuses: [:])
        let codexOptions = ThreadDefaultResolver.modelOptions(for: "codex", providerStatuses: [:])

        XCTAssertEqual(claudeOptions.filter(\.isDefault).map(\.id), ["claude-sonnet-5"])
        XCTAssertEqual(codexOptions.map(\.id), ["default"])
    }

    /// The static-fallback paths (host tools, pull-request threads, nil-discovery view models) used to reset a stored
    /// pinned model to the default sentinel because the placeholder options could not resolve it.
    func testStaticFallbackPreservesAStoredPinnedModel() {
        var settings = AppSettings()
        settings.defaultProvider = "claude"
        settings.defaultModel = "claude-opus-5"

        let resolution = ThreadDefaultResolver.resolve(
            settings: settings,
            providerOrdering: ["claude"],
            providerStatuses: [:],
            allowStaticFallback: true
        )

        XCTAssertEqual(resolution.providerID, "claude")
        XCTAssertEqual(resolution.storedThreadModel, "claude-opus-5")
    }

    private static func status(
        for providerId: AgentCLIKit.AgentProviderID,
        setup: AgentCLIKit.AgentProviderReadinessState
    ) -> AgentCLIKit.AgentProviderStatus {
        AgentCLIKit.AgentProviderStatus(
            providerId: providerId,
            definition: providerId == .claude
                ? AgentCLIKit.ClaudeProviderDefinition.definition
                : AgentCLIKit.CodexProviderDefinition.definition,
            installation: .installed,
            availability: AgentCLIKit.AgentProviderAvailability(
                providerId: providerId,
                executablePath: "/usr/local/bin/\(providerId.rawValue)"
            ),
            setup: setup,
            modelOptions: []
        )
    }
}
