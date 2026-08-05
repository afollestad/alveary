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

    func testSupportedIconOptionsIncludeRequestedSymbols() {
        let symbols = Set(ProjectSettingsActionIconOption.supported.map(\.symbolName))

        XCTAssertTrue(symbols.contains("checkmark.circle"))
        XCTAssertTrue(symbols.contains("arrow.triangle.branch"))
        XCTAssertTrue(symbols.contains("arrow.trianglehead.branch"))
        XCTAssertTrue(symbols.contains("icloud.and.arrow.up"))
        XCTAssertTrue(symbols.contains("icloud.and.arrow.down"))
        XCTAssertTrue(symbols.contains("arrow.trianglehead.2.clockwise.rotate.90.icloud"))
    }

    func testSupportedIconOptionsAreSortedByLabel() {
        let labels = ProjectSettingsActionIconOption.supported.map(\.label)

        XCTAssertEqual(labels, labels.sorted())
    }

    func testProjectConfigChangeNotificationRoundTripsItsProjectPath() {
        let notification = ProjectConfigChangeNotifier.notification(projectPath: "/tmp/project")

        XCTAssertEqual(notification.name, .projectConfigDidChange)
        XCTAssertEqual(ProjectConfigChangeNotifier.changedProjectPath(in: notification), "/tmp/project")
    }

    func testProjectConfigChangedPathIsNilWithoutPayload() {
        let bare = Notification(name: .projectConfigDidChange)

        XCTAssertNil(ProjectConfigChangeNotifier.changedProjectPath(in: bare))
    }
}
