import XCTest

@testable import Alveary

final class ProjectSettingsActionDraftTests: XCTestCase {
    func testInitNormalizesLegacyRunIcon() {
        let action = AlvearyProjectConfig.ProjectAction(icon: "play.square", name: "Run", command: "npm start")

        let draft = ProjectSettingsActionDraft(action: action)

        XCTAssertEqual(draft.displayedIconName, "play")
        XCTAssertEqual(draft.resolvedAction?.icon, "play")
    }

    func testResolvedActionReturnsNilForIncompleteDraft() {
        let draft = ProjectSettingsActionDraft(icon: "terminal", name: "  ", command: "echo hi")

        XCTAssertNil(draft.resolvedAction)
    }
}
