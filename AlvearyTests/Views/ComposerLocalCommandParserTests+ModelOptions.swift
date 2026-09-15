import XCTest

@testable import Alveary

extension ComposerLocalCommandParserTests {
    func testModelArgumentHintJoinsShortNamesInHarnessOrder() {
        let availability = ComposerLocalCommandAvailability(modelOptions: [
            option(harnessID: "claude", value: "sonnet", shortName: "sonnet", title: "Sonnet"),
            option(harnessID: "claude", value: "opus", shortName: "opus", title: "Opus")
        ])

        XCTAssertEqual(availability.modelArgumentHint, "sonnet|opus")
    }

    func testModelArgumentHintTruncatesLongListsWithEllipsis() {
        let availability = ComposerLocalCommandAvailability(modelOptions: [
            option(harnessID: "claude", value: "sonnet", shortName: "sonnet", title: "Sonnet"),
            option(harnessID: "claude", value: "fable", shortName: "fable", title: "Fable"),
            option(harnessID: "claude", value: "opus", shortName: "opus", title: "Opus"),
            option(harnessID: "claude", value: "haiku", shortName: "haiku", title: "Haiku"),
            // Codex ids that earn no alias stay long, which is what pushes the hint over its budget.
            option(harnessID: "codex", value: "gpt-5.4-mini", shortName: "gpt-5.4-mini", title: "GPT-5.4-Mini"),
            option(harnessID: "codex", value: "gpt-5.5", shortName: "gpt-5.5", title: "GPT-5.5")
        ])

        let hint = availability.modelArgumentHint

        XCTAssertEqual(hint, "sonnet|fable|opus|haiku|gpt-5.4-mini|…")
    }

    /// Claude puts a family alias on only its newest version, so catalog order alone would spend the budget on
    /// `claude-sonnet-4-6` before `opus` or `haiku` were ever shown.
    func testModelArgumentHintListsAliasedOptionsBeforeBareIDs() {
        let availability = ComposerLocalCommandAvailability(modelOptions: [
            option(harnessID: "claude", value: "claude-fable-5", shortName: "fable", title: "Fable 5"),
            option(harnessID: "claude", value: "claude-opus-5", shortName: "opus", title: "Opus 5"),
            option(harnessID: "claude", value: "claude-opus-4-8", shortName: "claude-opus-4-8", title: "Opus 4.8"),
            option(harnessID: "claude", value: "claude-opus-4-7", shortName: "claude-opus-4-7", title: "Opus 4.7"),
            option(harnessID: "claude", value: "claude-sonnet-5", shortName: "sonnet", title: "Sonnet 5"),
            option(harnessID: "claude", value: "claude-sonnet-4-6", shortName: "claude-sonnet-4-6", title: "Sonnet 4.6"),
            option(harnessID: "claude", value: "claude-haiku-4-5", shortName: "haiku", title: "Haiku 4.5")
        ])

        XCTAssertEqual(availability.modelArgumentHint, "fable|opus|sonnet|haiku|claude-opus-4-8|…")
    }

    func testModelOptionResolvesAFamilyAliasAndItsPinnedVersions() {
        let availability = ComposerLocalCommandAvailability(modelOptions: [
            option(harnessID: "claude", value: "claude-opus-5", shortName: "opus", title: "Opus 5"),
            option(harnessID: "claude", value: "claude-opus-4-8", shortName: "claude-opus-4-8", title: "Opus 4.8")
        ])

        XCTAssertEqual(availability.modelOption(matching: "opus")?.value, "claude-opus-5")
        XCTAssertEqual(availability.modelOption(matching: "claude-opus-4-8")?.value, "claude-opus-4-8")
        XCTAssertEqual(availability.modelOption(matching: "Opus 4.8")?.value, "claude-opus-4-8")
    }

    func testModelArgumentHintDeduplicatesSharedShortNames() {
        let availability = ComposerLocalCommandAvailability(modelOptions: [
            option(harnessID: "claude", value: "default", shortName: "default", title: "Default"),
            option(harnessID: "codex", value: "default", shortName: "default", title: "Default")
        ])

        XCTAssertEqual(availability.modelArgumentHint, "default")
    }

    func testModelOptionMatchesShortNameThenValueThenTitle() {
        let availability = ComposerLocalCommandAvailability(modelOptions: [
            option(harnessID: "codex", value: "gpt-5.6-sol", shortName: "sol", title: "GPT-5.6-Sol"),
            option(harnessID: "claude", value: "opus", shortName: "opus", title: "Opus")
        ])

        XCTAssertEqual(availability.modelOption(matching: "SOL")?.value, "gpt-5.6-sol")
        XCTAssertEqual(availability.modelOption(matching: "gpt-5.6-sol")?.value, "gpt-5.6-sol")
        XCTAssertEqual(availability.modelOption(matching: "  opus  ")?.value, "opus")
        XCTAssertEqual(availability.modelOption(matching: "GPT-5.6-Sol")?.value, "gpt-5.6-sol")
        XCTAssertNil(availability.modelOption(matching: "nonsense"))
        XCTAssertNil(availability.modelOption(matching: "   "))
    }

    func testModelOptionResolvesSharedShortNameByHarnessOrderAndQualifier() {
        let availability = ComposerLocalCommandAvailability(modelOptions: [
            option(harnessID: "claude", value: "default", shortName: "default", title: "Default"),
            option(harnessID: "codex", value: "default", shortName: "default", title: "Default")
        ])

        XCTAssertEqual(availability.modelOption(matching: "default")?.harnessID, "claude")
        XCTAssertEqual(availability.modelOption(matching: "codex:default")?.harnessID, "codex")
        XCTAssertEqual(availability.modelOption(matching: "CODEX:DEFAULT")?.harnessID, "codex")
    }

    func testModelOptionFallsBackToWholeStringWhenHarnessPrefixIsUnknown() {
        let availability = ComposerLocalCommandAvailability(modelOptions: [
            option(harnessID: "codex", value: "vendor:model", shortName: "vendor:model", title: "Vendor Model"),
            option(harnessID: "claude", value: "opus", shortName: "opus", title: "Opus")
        ])

        XCTAssertEqual(availability.modelOption(matching: "vendor:model")?.value, "vendor:model")
        XCTAssertNil(availability.modelOption(matching: "claude:missing"))
    }

    private func option(
        harnessID: String,
        value: String,
        shortName: String,
        title: String
    ) -> ComposerModelCommandOption {
        ComposerModelCommandOption(harnessID: harnessID, value: value, shortName: shortName, title: title)
    }
}
