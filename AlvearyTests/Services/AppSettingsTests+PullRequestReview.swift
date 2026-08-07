import Foundation
import XCTest

@testable import Alveary

// Agentic review settings: the editable instructions, the pinned agent trio, and the
// footer's remembered split-button pick.
extension AppSettingsTests {
    func testPullRequestReviewDefaultsWhenFieldsAreMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestReviewPrompt, AppSettings.defaultPullRequestReviewPrompt)
        // Nil means "follow the Threads defaults" — not "no agent".
        XCTAssertNil(settings.pullRequestReviewProvider)
        XCTAssertNil(settings.pullRequestReviewModel)
        XCTAssertNil(settings.pullRequestReviewEffort)
        XCTAssertEqual(settings.pullRequestReviewFooterActionKind, "submitReview")
    }

    func testPullRequestReviewSettingsRoundTripThroughCodable() throws {
        var settings = AppSettings()
        settings.pullRequestReviewPrompt = "Review it carefully."
        settings.pullRequestReviewProvider = "codex"
        settings.pullRequestReviewModel = "gpt-5"
        settings.pullRequestReviewEffort = "high"
        settings.pullRequestReviewFooterActionKind = "agenticReview"

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded.pullRequestReviewPrompt, "Review it carefully.")
        XCTAssertEqual(decoded.pullRequestReviewProvider, "codex")
        XCTAssertEqual(decoded.pullRequestReviewModel, "gpt-5")
        XCTAssertEqual(decoded.pullRequestReviewEffort, "high")
        XCTAssertEqual(decoded.pullRequestReviewFooterActionKind, "agenticReview")
    }

    func testNormalizationRestoresABlankReviewPrompt() {
        var settings = AppSettings()
        settings.pullRequestReviewPrompt = "   \n  "

        XCTAssertEqual(settings.normalized().pullRequestReviewPrompt, AppSettings.defaultPullRequestReviewPrompt)
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
