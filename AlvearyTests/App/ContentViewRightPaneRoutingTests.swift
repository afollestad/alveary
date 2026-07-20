import XCTest

@testable import Alveary

final class ContentViewRightPaneRoutingTests: XCTestCase {
    func testMatchingContextualPaneTakesPrecedenceOverRequestedDiffViewer() {
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .skills,
                skillsTarget: .newSkill,
                mcpTarget: nil,
                scheduledTarget: nil,
                isDiffViewerRequested: true
            ),
            .skills(.newSkill)
        )
    }

    func testInactiveScreenTargetDoesNotMaskRequestedDiffViewer() {
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .mcp,
                skillsTarget: .details("cached"),
                mcpTarget: nil,
                scheduledTarget: nil,
                isDiffViewerRequested: true
            ),
            .diff
        )
    }

    func testNoRequestAndNoMatchingContextualTargetProducesNoPane() {
        XCTAssertNil(
            RightPaneDestination.resolve(
                selection: .scheduled,
                skillsTarget: nil,
                mcpTarget: nil,
                scheduledTarget: nil,
                isDiffViewerRequested: false
            )
        )
    }

    func testEachDestinationUsesItsScreenWidthDomain() {
        XCTAssertEqual(RightPaneDestination.diff.widthDomain, .diff)
        XCTAssertEqual(RightPaneDestination.skills(.newSkill).widthDomain, .skills)
        XCTAssertEqual(RightPaneDestination.mcp(.addCustom).widthDomain, .mcp)
        XCTAssertEqual(RightPaneDestination.scheduled(.create).widthDomain, .scheduled)
    }

    func testDiffViewerCommandIntentUsesRenderedDestination() {
        XCTAssertEqual(DiffViewerCommandIntent.resolve(destination: .diff), .hideDiff)
        XCTAssertEqual(DiffViewerCommandIntent.resolve(destination: nil), .showDiff)
        XCTAssertEqual(
            DiffViewerCommandIntent.resolve(destination: .skills(.newSkill)),
            .deactivateContextAndShowDiff(.skills)
        )
        XCTAssertEqual(
            DiffViewerCommandIntent.resolve(destination: .mcp(.addCustom)),
            .deactivateContextAndShowDiff(.mcp)
        )
        XCTAssertEqual(
            DiffViewerCommandIntent.resolve(destination: .scheduled(.create)),
            .deactivateContextAndShowDiff(.scheduled)
        )
    }
}
