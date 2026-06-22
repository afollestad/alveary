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

    func testGoalIsReservedEvenWhenUnavailable() {
        let noSupport = ComposerLocalCommandAvailability()
        let supported = ComposerLocalCommandAvailability(supportsGoalMode: true)

        XCTAssertEqual(
            ComposerLocalCommandParser.parse("/goal", availability: noSupport),
            ComposerLocalCommand(kind: .goal, argument: "")
        )
        XCTAssertEqual(
            ComposerLocalCommandParser.parse("/goal Ship this", availability: supported),
            ComposerLocalCommand(kind: .goal, argument: "Ship this")
        )
        XCTAssertEqual(
            ComposerLocalCommandParser.parse("/goal clear", availability: noSupport),
            ComposerLocalCommand(kind: .goal, argument: "clear")
        )
        XCTAssertEqual(
            ComposerLocalCommandParser.parse("/goal clear the logs", availability: supported),
            ComposerLocalCommand(kind: .goal, argument: "clear the logs")
        )
    }

    func testIgnoresLeadingWhitespaceAndUnknownCommands() {
        let availability = ComposerLocalCommandAvailability(supportsPlanMode: true, supportsSessionHandoff: true)

        XCTAssertNil(ComposerLocalCommandParser.parse(" /plan Fix it", availability: availability))
        XCTAssertNil(ComposerLocalCommandParser.parse("/unknown Fix it", availability: availability))
    }

    func testInactiveCommandsAreNotIntercepted() {
        XCTAssertNotNil(ComposerLocalCommandParser.parse("/goal Fix it", availability: ComposerLocalCommandAvailability()))
        XCTAssertNil(ComposerLocalCommandParser.parse("/plan Fix it", availability: ComposerLocalCommandAvailability()))
        XCTAssertNil(ComposerLocalCommandParser.parse("/fast Fix it", availability: ComposerLocalCommandAvailability()))
        XCTAssertNil(ComposerLocalCommandParser.parse("/handoff Focus", availability: ComposerLocalCommandAvailability()))
    }

    func testCompactIsNotInterceptedAsLocalCommand() {
        let availability = ComposerLocalCommandAvailability(
            supportsPlanMode: true,
            supportsSpeedMode: true,
            supportsSessionHandoff: true
        )

        XCTAssertNil(ComposerLocalCommandParser.parse("/compact", availability: availability))
        XCTAssertNil(ComposerLocalCommandParser.parse("/compact focus on recent work", availability: availability))
    }
}
