import Foundation
import XCTest

@testable import Alveary

// Agentic pull-request settings: the two sets of editable instructions, the pinned agent
// trio they share, and the footer's remembered split-button pick.
extension AppSettingsTests {
    func testPullRequestReviewDefaultsWhenFieldsAreMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestReviewPrompt, AppSettings.defaultPullRequestReviewPrompt)
        XCTAssertEqual(settings.pullRequestAddressFeedbackPrompt, AppSettings.defaultPullRequestAddressFeedbackPrompt)
        // Nil means "follow the Threads defaults" — not "no agent".
        XCTAssertNil(settings.pullRequestReviewProvider)
        XCTAssertNil(settings.pullRequestReviewModel)
        XCTAssertNil(settings.pullRequestReviewEffort)
        XCTAssertEqual(settings.pullRequestReviewFooterActionKind, "submitReview")
    }

    func testPullRequestReviewSettingsRoundTripThroughCodable() throws {
        var settings = AppSettings()
        settings.pullRequestReviewPrompt = "Review it carefully."
        settings.pullRequestAddressFeedbackPrompt = "Answer every thread."
        settings.pullRequestReviewProvider = "codex"
        settings.pullRequestReviewModel = "gpt-5"
        settings.pullRequestReviewEffort = "high"
        settings.pullRequestReviewFooterActionKind = "agenticReview"

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded.pullRequestReviewPrompt, "Review it carefully.")
        XCTAssertEqual(decoded.pullRequestAddressFeedbackPrompt, "Answer every thread.")
        XCTAssertEqual(decoded.pullRequestReviewProvider, "codex")
        XCTAssertEqual(decoded.pullRequestReviewModel, "gpt-5")
        XCTAssertEqual(decoded.pullRequestReviewEffort, "high")
        XCTAssertEqual(decoded.pullRequestReviewFooterActionKind, "agenticReview")
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

        let normalized = settings.normalized()
        XCTAssertNil(normalized.pullRequestReviewProvider)
        XCTAssertNil(normalized.pullRequestReviewModel)
        XCTAssertNil(normalized.pullRequestReviewEffort)
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

    func testNormalizationTrimsPinnedAgentValues() {
        var settings = AppSettings()
        settings.pullRequestReviewProvider = "  codex  "
        settings.pullRequestReviewEffort = " high "

        let normalized = settings.normalized()
        XCTAssertEqual(normalized.pullRequestReviewProvider, "codex")
        XCTAssertEqual(normalized.pullRequestReviewEffort, "high")
    }
}
