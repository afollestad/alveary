import XCTest

@testable import Alveary

final class ExitPlanModeDenialPolicyTests: XCTestCase {
    func testDeniedResponseTextIsStable() {
        XCTAssertEqual(
            ExitPlanModeDenialPolicy.deniedResponseText,
            "The host chose to stay in plan mode."
        )
    }

    func testRevisionTransportGuidanceIsClaudeOnly() {
        XCTAssertTrue(ExitPlanModeDenialPolicy.requiresRevisionTransportGuidance(providerId: "claude"))
        XCTAssertFalse(ExitPlanModeDenialPolicy.requiresRevisionTransportGuidance(providerId: "codex"))
        XCTAssertFalse(ExitPlanModeDenialPolicy.requiresRevisionTransportGuidance(providerId: nil))
    }

    func testRevisionTransportTextWrapsVisibleFeedback() {
        let expectedGuidance = "The user rejected the plan and Alveary is still in plan mode. " +
            "Treat the following as plan-revision feedback only. " +
            "Do not make file or tool changes yet. " +
            "Revise the plan, then request ExitPlanMode again when ready."

        XCTAssertEqual(
            ExitPlanModeDenialPolicy.revisionTransportText(visibleText: "Revise the plan."),
            """
            \(expectedGuidance)

            User feedback:
            Revise the plan.
            """
        )
    }
}
