import AgentCLIKit
import XCTest

@testable import Alveary

/// The agentic review's seed resolution. Its contract is to degrade rather than fail: a
/// pinned provider, model, or effort that a provider no longer offers falls back to what a
/// typed thread would get, because a footer button has nowhere to explain a refusal.
@MainActor
final class PullRequestAgenticThreadServiceTests: XCTestCase {
    private func resolution(
        providerID: String? = "claude",
        storedThreadModel: String? = nil,
        permissionMode: String = "default",
        effort: String = "medium",
        readyProviderIDs: [String] = ["claude", "codex"],
        modelOptions: [AgentCLIKit.AgentModelOption] = AgentModelOptionTestFixtures.claudeModelOptions
    ) -> ThreadDefaultResolution {
        ThreadDefaultResolution(
            providerID: providerID,
            storedThreadModel: storedThreadModel,
            permissionMode: permissionMode,
            effort: effort,
            readyProviderIDs: readyProviderIDs,
            modelOptions: modelOptions
        )
    }

    private func seed(
        settings: AppSettings,
        resolution: ThreadDefaultResolution,
        provider: String = "claude",
        modelOptions: [AgentCLIKit.AgentModelOption] = AgentModelOptionTestFixtures.claudeModelOptions
    ) -> PullRequestAgenticThreadService.SeedSettings {
        PullRequestAgenticThreadService.resolveSeedSettings(
            settings: settings,
            resolution: resolution,
            provider: provider,
            modelOptions: modelOptions
        )
    }

    func testUnpinnedSettingsInheritTheThreadDefaults() {
        var settings = AppSettings()
        settings.permissionMode = "acceptEdits"
        let resolved = seed(
            settings: settings,
            resolution: resolution(storedThreadModel: "opus", permissionMode: "acceptEdits", effort: "high")
        )

        XCTAssertEqual(resolved.provider, "claude")
        XCTAssertEqual(resolved.model, "opus")
        XCTAssertEqual(resolved.effort, "high")
        XCTAssertEqual(resolved.permissionMode, "acceptEdits")
    }

    func testAPinnedModelAndEffortWinOverTheThreadDefaults() {
        var settings = AppSettings()
        settings.pullRequestReviewModel = "haiku"
        settings.pullRequestReviewEffort = "low"
        let resolved = seed(settings: settings, resolution: resolution(storedThreadModel: "opus", effort: "high"))

        XCTAssertEqual(resolved.model, "haiku")
        XCTAssertEqual(resolved.effort, "low")
    }

    /// The failure this guards: a model the user pinned months ago that the provider has since
    /// retired must not refuse the review, it must run on the thread default instead.
    func testAPinnedModelTheProviderNoLongerOffersDegradesToTheInheritedOne() {
        var settings = AppSettings()
        settings.pullRequestReviewModel = "retired-model"
        let resolved = seed(settings: settings, resolution: resolution(storedThreadModel: "opus"))

        XCTAssertEqual(resolved.model, "opus")
    }

    func testAPinnedEffortTheModelDoesNotSupportDegradesToTheInheritedOne() {
        var settings = AppSettings()
        settings.pullRequestReviewModel = "haiku"
        // Haiku offers low/medium/high, not xhigh.
        settings.pullRequestReviewEffort = "xhigh"
        let resolved = seed(settings: settings, resolution: resolution(effort: "medium"))

        XCTAssertEqual(resolved.model, "haiku")
        XCTAssertEqual(resolved.effort, "medium")
    }

    /// `"default"` is the picker's sentinel for "the provider's own default", so it resolves to
    /// that model by name rather than being passed through — the literal would make the adapter
    /// pass `--model=default` to the CLI. Matches `ThreadHostToolService.validatedModel`.
    func testTheDefaultModelSentinelResolvesToTheProvidersDefaultModel() {
        var settings = AppSettings()
        settings.pullRequestReviewModel = AppSettings.defaultModelValue
        let resolved = seed(settings: settings, resolution: resolution(storedThreadModel: "opus"))

        XCTAssertEqual(resolved.model, "sonnet")
        XCTAssertNotEqual(resolved.model, AppSettings.defaultModelValue)
    }

    /// A provider whose default option carries no model name has nothing to pass, and the
    /// sentinel must not reach the CLI in its place.
    func testAModellessDefaultOptionResolvesToNoModelOverride() {
        var settings = AppSettings()
        settings.pullRequestReviewModel = AppSettings.defaultModelValue
        let modelless = [
            AgentCLIKit.AgentModelOption(
                providerId: .claude,
                id: "default",
                model: nil,
                label: "Default",
                isDefault: true,
                supportedEffortOptions: [],
                defaultEffortOption: nil
            )
        ]
        let resolved = seed(
            settings: settings,
            resolution: resolution(modelOptions: modelless),
            modelOptions: modelless
        )

        XCTAssertNil(resolved.model)
    }

    func testAProviderOtherThanTheThreadDefaultInheritsNothingFromIt() {
        let resolved = seed(
            settings: AppSettings(),
            resolution: resolution(providerID: "claude", storedThreadModel: "opus", permissionMode: "acceptEdits"),
            provider: "codex",
            modelOptions: AgentModelOptionTestFixtures.codexModelOptions
        )

        // A Claude model means nothing on Codex, so the review runs on Codex's own default.
        XCTAssertNil(resolved.model)
        XCTAssertEqual(resolved.permissionMode, AppSettings.defaultPermissionMode(forProvider: "codex"))
    }

    func testAProviderWithNoEffortCatalogKeepsThePinnedEffort() {
        var settings = AppSettings()
        settings.pullRequestReviewEffort = "high"
        // An empty catalog means the provider reports no efforts, not that it rejects this one.
        let resolved = seed(settings: settings, resolution: resolution(modelOptions: []), modelOptions: [])

        XCTAssertEqual(resolved.effort, "high")
    }

    /// The spawned thread's first message stands in for something the user would type: the URL
    /// alone, with no shorthand or title beside it, and none of the instructions — the agent
    /// fetches those with the same tool a manual ask uses.
    func testTheSpawnedPromptIsJustTheRequestAndTheLink() {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://github.com/octo/alpha/pull/7")!

        for kind in PullRequestAgenticThreadService.Kind.allCases {
            let prompt = kind.requestPrompt(url: url)

            XCTAssertTrue(prompt.hasSuffix("https://github.com/octo/alpha/pull/7"), prompt)
            XCTAssertFalse(prompt.contains(PullRequestHostToolCatalog.diffToolName), prompt)
        }
        XCTAssertEqual(
            PullRequestAgenticThreadService.Kind.review.requestPrompt(url: url),
            "Review pull request: https://github.com/octo/alpha/pull/7"
        )
        XCTAssertEqual(
            PullRequestAgenticThreadService.Kind.addressFeedback.requestPrompt(url: url),
            "Address feedback on pull request: https://github.com/octo/alpha/pull/7"
        )
    }

    /// The sidebar row has to say which job the thread is doing; both kinds spawn from the same
    /// footer, so a shared name would leave two indistinguishable rows on one pull request.
    func testEachKindNamesItsThreadForTheSidebar() {
        let identifier = makePullRequestSummary(number: 7, status: .open).id

        XCTAssertEqual(
            PullRequestAgenticThreadService.Kind.review.threadName(for: identifier),
            "Review \(identifier.displayKey)"
        )
        XCTAssertEqual(
            PullRequestAgenticThreadService.Kind.addressFeedback.threadName(for: identifier),
            "Address feedback \(identifier.displayKey)"
        )
    }

    /// Reviewing is deliberately project-less; addressing feedback edits, tests, and pushes.
    func testOnlyAddressingFeedbackWantsACheckout() {
        XCTAssertFalse(PullRequestAgenticThreadService.Kind.review.needsCheckout)
        XCTAssertTrue(PullRequestAgenticThreadService.Kind.addressFeedback.needsCheckout)
    }

    func testNoReadyProviderIsTheOnlyStartFailure() {
        XCTAssertEqual(
            PullRequestAgenticThreadService.StartError.noReadyProvider.errorDescription,
            "No agent is ready to start this thread. Check the Agents settings."
        )
    }
}
