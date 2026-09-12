import Foundation
import XCTest

@testable import Alveary

// Agentic pull-request settings: review criteria, address-feedback instructions, their independent
// agent options, the saved team, and the footer's two remembered split-button picks.
extension AppSettingsTests {
    func testPullRequestReviewDefaultsWhenFieldsAreMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestReviewPrompt, AppSettings.defaultPullRequestReviewPrompt)
        XCTAssertEqual(settings.pullRequestAddressFeedbackPrompt, AppSettings.defaultPullRequestAddressFeedbackPrompt)
        XCTAssertEqual(settings.pullRequestReviewMode, .singleAgent)
        XCTAssertEqual(settings.pullRequestReviewPeers, [])
        // Nil means "follow the Threads defaults" — not "no agent".
        XCTAssertNil(settings.pullRequestReviewProvider)
        XCTAssertNil(settings.pullRequestReviewModel)
        XCTAssertNil(settings.pullRequestReviewEffort)
        XCTAssertNil(settings.pullRequestReviewPermissionMode)
        // Nil here means the plain `Tasks` list, not "no placement".
        XCTAssertNil(settings.pullRequestAddressFeedbackSectionID)
        XCTAssertNil(settings.pullRequestReviewSectionID)
        XCTAssertEqual(settings.pullRequestOwnFooterActionKind, "addressFeedback")
        XCTAssertEqual(settings.pullRequestOthersFooterActionKind, "agenticReview")
    }

    func testPullRequestReviewSettingsRoundTripThroughCodable() throws {
        var settings = AppSettings()
        settings.pullRequestReviewPrompt = "Review it carefully."
        settings.pullRequestAddressFeedbackPrompt = "Answer every thread."
        settings.pullRequestReviewProvider = "codex"
        settings.pullRequestReviewModel = "gpt-5"
        settings.pullRequestReviewEffort = "high"
        settings.pullRequestReviewPermissionMode = "never"
        settings.pullRequestReviewMode = .reviewTeam
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer-1", providerID: "claude", model: "opus", effort: "high"),
            PullRequestReviewPeer(id: "peer-2", providerID: "codex", model: "gpt-5.5", effort: "xhigh")
        ]
        settings.pullRequestOwnFooterActionKind = "submitReview"
        settings.pullRequestOthersFooterActionKind = "addressFeedback"

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded.pullRequestReviewPrompt, "Review it carefully.")
        XCTAssertEqual(decoded.pullRequestAddressFeedbackPrompt, "Answer every thread.")
        XCTAssertEqual(decoded.pullRequestReviewProvider, "codex")
        XCTAssertEqual(decoded.pullRequestReviewModel, "gpt-5")
        XCTAssertEqual(decoded.pullRequestReviewEffort, "high")
        XCTAssertEqual(decoded.pullRequestReviewPermissionMode, "never")
        XCTAssertEqual(decoded.pullRequestReviewMode, .reviewTeam)
        XCTAssertEqual(decoded.pullRequestReviewPeers, settings.pullRequestReviewPeers)
        XCTAssertEqual(decoded.pullRequestOwnFooterActionKind, "submitReview")
        XCTAssertEqual(decoded.pullRequestOthersFooterActionKind, "addressFeedback")
    }

    func testAMalformedReviewPermissionDecodesAsInherit() throws {
        let json = Data(#"{"pullRequestReviewPermissionMode":true}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertNil(settings.pullRequestReviewPermissionMode)
    }

    func testLegacySharedAgentPinsMigrateToFeedbackOnce() throws {
        let json = Data(#"""
        {
            "pullRequestReviewProvider": "codex",
            "pullRequestReviewModel": "gpt-5.5",
            "pullRequestReviewEffort": "high",
            "pullRequestReviewPermissionMode": "never"
        }
        """#.utf8)
        var settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestAddressFeedbackAgent, settings.pullRequestReviewAgent)

        settings.pullRequestAddressFeedbackAgent = PullRequestAgentSettings()
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(restored.pullRequestAddressFeedbackAgent, PullRequestAgentSettings())
        XCTAssertEqual(restored.pullRequestReviewAgent, settings.pullRequestReviewAgent)
    }

    func testExplicitFeedbackPinsAndNullOutrankLegacyPinsDuringMigration() throws {
        let json = Data(#"""
        {
            "pullRequestReviewProvider": "codex",
            "pullRequestReviewModel": "gpt-5.5",
            "pullRequestReviewEffort": "high",
            "pullRequestReviewPermissionMode": "never",
            "pullRequestAddressFeedbackProvider": null,
            "pullRequestAddressFeedbackModel": "sonnet",
            "pullRequestAddressFeedbackEffort": true,
            "pullRequestAddressFeedbackPermissionMode": "acceptEdits"
        }
        """#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(
            settings.pullRequestAddressFeedbackAgent,
            PullRequestAgentSettings(model: "sonnet", permissionMode: "acceptEdits")
        )
    }

    func testFeedbackAndReviewAgentPinsRoundTripIndependently() throws {
        var settings = AppSettings()
        settings.pullRequestReviewAgent = PullRequestAgentSettings(provider: "codex", model: "gpt-5.5", effort: "high")
        settings.pullRequestAddressFeedbackAgent = PullRequestAgentSettings(
            provider: "claude", model: "sonnet", effort: "medium", permissionMode: "acceptEdits"
        )

        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(restored.pullRequestReviewAgent, settings.pullRequestReviewAgent)
        XCTAssertEqual(restored.pullRequestAddressFeedbackAgent, settings.pullRequestAddressFeedbackAgent)
    }

    func testFeedbackNormalizationTrimsPinsAndDropsUnsupportedValues() {
        var settings = AppSettings()
        settings.pullRequestAddressFeedbackAgent = PullRequestAgentSettings(
            provider: "unknown", model: " sonnet ", effort: " ", permissionMode: "plan"
        )

        XCTAssertEqual(settings.normalized().pullRequestAddressFeedbackAgent, PullRequestAgentSettings(model: "sonnet"))
    }

    func testAnUnknownReviewModeAndMalformedPeersDecodeAsDefaults() throws {
        let json = Data(#"{"pullRequestReviewMode":"unknown","pullRequestReviewPeers":true}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestReviewMode, .singleAgent)
        XCTAssertEqual(settings.pullRequestReviewPeers, [])
    }

    func testCustomLegacyReviewTextIsPreservedAsCriteria() throws {
        let json = Data(#"{"pullRequestReviewPrompt":"Use my exact custom criteria."}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestReviewPrompt, "Use my exact custom criteria.")
    }

    func testTheShippedLegacyReviewWorkflowMigratesToCriteriaOnly() throws {
        var legacySettings = AppSettings()
        legacySettings.pullRequestReviewPrompt = PullRequestReviewPromptDefaults.legacyDefaultPrompt

        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(legacySettings)
        )

        XCTAssertEqual(settings.pullRequestReviewPrompt, AppSettings.defaultPullRequestReviewPrompt)
        XCTAssertNotEqual(settings.pullRequestReviewPrompt, PullRequestReviewPromptDefaults.legacyDefaultPrompt)
        XCTAssertFalse(settings.pullRequestReviewPrompt.contains("get_pr_diff"))
    }

    // MARK: - The single footer pick that preceded the split

    /// Nobody chose the old default — every settings file ever encoded carries it — so honouring
    /// it would hand the whole install base a pick it never made and hide the new defaults.
    func testTheLegacyFooterPickIsIgnoredWhenItNamesTheOldDefault() throws {
        let json = Data(#"{"pullRequestReviewFooterActionKind":"submitReview"}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestOwnFooterActionKind, "addressFeedback")
        XCTAssertEqual(settings.pullRequestOthersFooterActionKind, "agenticReview")
    }

    /// Anything else was a deliberate trip to the caret, so it survives on both halves.
    func testADeliberateLegacyFooterPickSeedsBothNewKeys() throws {
        let json = Data(#"{"pullRequestReviewFooterActionKind":"agenticReview"}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestOwnFooterActionKind, "agenticReview")
        XCTAssertEqual(settings.pullRequestOthersFooterActionKind, "agenticReview")
    }

    /// Once the new keys exist they are the record; the legacy value lingers in the file until
    /// the next encode drops it, and must not overwrite them.
    func testTheNewFooterKeysOutrankTheLegacyOne() throws {
        let json = Data(
            #"{"pullRequestReviewFooterActionKind":"agenticReview","pullRequestOwnFooterActionKind":"submitReview"}"#
                .utf8
        )

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestOwnFooterActionKind, "submitReview")
        XCTAssertEqual(settings.pullRequestOthersFooterActionKind, "agenticReview")
    }

    /// Re-encoding drops the retired key rather than carrying it forward forever.
    func testEncodingDropsTheLegacyFooterKey() throws {
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"pullRequestReviewFooterActionKind":"agenticReview"}"#.utf8)
        )

        let reencoded = try XCTUnwrap(String(data: JSONEncoder().encode(decoded), encoding: .utf8))

        XCTAssertFalse(reencoded.contains("pullRequestReviewFooterActionKind"))
    }

    /// The two prompts are separate settings; editing one must not reach the other.
    func testTheTwoAgenticPromptsAreIndependent() throws {
        var settings = AppSettings()
        settings.pullRequestReviewPrompt = "Review it carefully."

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.pullRequestAddressFeedbackPrompt, AppSettings.defaultPullRequestAddressFeedbackPrompt)
    }

    func testNormalizationRestoresABlankReviewPrompt() {
        var settings = AppSettings()
        settings.pullRequestReviewPrompt = "   \n  "

        XCTAssertEqual(settings.normalized().pullRequestReviewPrompt, AppSettings.defaultPullRequestReviewPrompt)
    }

    func testNormalizationRestoresABlankAddressFeedbackPrompt() {
        var settings = AppSettings()
        settings.pullRequestAddressFeedbackPrompt = "  \n "

        XCTAssertEqual(
            settings.normalized().pullRequestAddressFeedbackPrompt,
            AppSettings.defaultPullRequestAddressFeedbackPrompt
        )
    }

    func testNormalizationCollapsesBlankAgentPinsToInherit() {
        var settings = AppSettings()
        settings.pullRequestReviewProvider = "  "
        settings.pullRequestReviewModel = ""
        settings.pullRequestReviewEffort = "\n"
        settings.pullRequestReviewPermissionMode = " \n "

        let normalized = settings.normalized()
        XCTAssertNil(normalized.pullRequestReviewProvider)
        XCTAssertNil(normalized.pullRequestReviewModel)
        XCTAssertNil(normalized.pullRequestReviewEffort)
        XCTAssertNil(normalized.pullRequestReviewPermissionMode)
    }

    func testNormalizationPreservesKnownReviewPermissionsAndDropsUnsupportedModes() {
        var settings = AppSettings()
        settings.pullRequestReviewProvider = "codex"
        settings.pullRequestReviewPermissionMode = "bypassPermissions"

        XCTAssertEqual(settings.normalized().pullRequestReviewPermissionMode, "bypassPermissions")

        for mode in ["unknown", "plan"] {
            settings.pullRequestReviewPermissionMode = mode
            XCTAssertNil(settings.normalized().pullRequestReviewPermissionMode, mode)
        }
    }

    func testNormalizationDropsAnUnsupportedReviewProvider() {
        var settings = AppSettings()
        settings.pullRequestReviewProvider = "nonexistent"
        settings.pullRequestReviewModel = "some-model"

        let normalized = settings.normalized()
        XCTAssertNil(normalized.pullRequestReviewProvider)
        // Model and effort are validated at spawn time against live provider discovery, so a
        // stored value survives normalization even when the provider does not.
        XCTAssertEqual(normalized.pullRequestReviewModel, "some-model")
    }

    func testTheTwoSectionPinsRoundTripSeparately() throws {
        var settings = AppSettings()
        settings.pullRequestAddressFeedbackSectionID = "feedback-section"
        settings.pullRequestReviewSectionID = "review-section"

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded.pullRequestAddressFeedbackSectionID, "feedback-section")
        XCTAssertEqual(decoded.pullRequestReviewSectionID, "review-section")
    }

    func testNormalizationCollapsesBlankSectionPinsToTasks() {
        var settings = AppSettings()
        settings.pullRequestAddressFeedbackSectionID = "  "
        settings.pullRequestReviewSectionID = "\n"

        let normalized = settings.normalized()
        XCTAssertNil(normalized.pullRequestAddressFeedbackSectionID)
        XCTAssertNil(normalized.pullRequestReviewSectionID)
    }

    func testNormalizationKeepsASectionIDThatNamesNoLiveRow() {
        var settings = AppSettings()
        settings.pullRequestReviewSectionID = " missing-section "

        // Section rows live in SwiftData, which this value type cannot reach; existence is the
        // spawn path's check, so normalization only trims.
        XCTAssertEqual(settings.normalized().pullRequestReviewSectionID, "missing-section")
    }

    func testNormalizationTrimsPinnedAgentValues() {
        var settings = AppSettings()
        settings.pullRequestReviewProvider = "  codex  "
        settings.pullRequestReviewEffort = " high "
        settings.pullRequestReviewPermissionMode = " never "

        let normalized = settings.normalized()
        XCTAssertEqual(normalized.pullRequestReviewProvider, "codex")
        XCTAssertEqual(normalized.pullRequestReviewEffort, "high")
        XCTAssertEqual(normalized.pullRequestReviewPermissionMode, "never")
    }
}
