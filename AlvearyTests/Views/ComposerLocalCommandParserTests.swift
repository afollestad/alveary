import XCTest

@testable import Alveary

final class ComposerLocalCommandParserTests: XCTestCase {
    func testParsesPlanWithoutArgument() {
        let command = ComposerLocalCommandParser.parse(
            "/plan",
            availability: ComposerLocalCommandAvailability(supportsPlanMode: true)
        )

        XCTAssertEqual(command, ComposerLocalCommand(kind: .plan, argument: ""))
    }

    func testParsesPlanWithMultilineArgument() {
        let command = ComposerLocalCommandParser.parse(
            "/plan\nFix the tests.\nKeep it scoped.",
            availability: ComposerLocalCommandAvailability(supportsPlanMode: true)
        )

        XCTAssertEqual(command, ComposerLocalCommand(kind: .plan, argument: "Fix the tests.\nKeep it scoped."))
    }

    func testParsesHandoffWithArgument() {
        let command = ComposerLocalCommandParser.parse(
            "/handoff Focus on release notes.",
            availability: ComposerLocalCommandAvailability(supportsSessionHandoff: true)
        )

        XCTAssertEqual(command, ComposerLocalCommand(kind: .handoff, argument: "Focus on release notes."))
    }

    func testParsesFastWithArgument() {
        let command = ComposerLocalCommandParser.parse(
            "/fast Fix the tests.",
            availability: ComposerLocalCommandAvailability(supportsSpeedMode: true)
        )

        XCTAssertEqual(command, ComposerLocalCommand(kind: .fast, argument: "Fix the tests."))
    }

    func testIgnoresLeadingWhitespaceAndUnknownCommands() {
        let availability = ComposerLocalCommandAvailability(supportsPlanMode: true, supportsSessionHandoff: true)

        XCTAssertNil(ComposerLocalCommandParser.parse(" /plan Fix it", availability: availability))
        XCTAssertNil(ComposerLocalCommandParser.parse("/unknown Fix it", availability: availability))
    }

    func testInactiveCommandsAreNotIntercepted() {
        XCTAssertNil(ComposerLocalCommandParser.parse("/plan Fix it", availability: ComposerLocalCommandAvailability()))
        XCTAssertNil(ComposerLocalCommandParser.parse("/fast Fix it", availability: ComposerLocalCommandAvailability()))
        XCTAssertNil(ComposerLocalCommandParser.parse("/handoff Focus", availability: ComposerLocalCommandAvailability()))
    }
}
