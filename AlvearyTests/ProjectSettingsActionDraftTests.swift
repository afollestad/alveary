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

    @MainActor
    func testOwnConfigSaveEchoPreservesIncompleteActionsAndEditedRowIdentity() async throws {
        let original = AlvearyProjectConfig(actions: [.init(name: "Build", command: "swift build")])
        var editor = ProjectSettingsEditorState(config: original)
        editor.actions[0].name = "Build app"
        editor.actions.append(ProjectSettingsActionDraft(name: "Test", command: ""))
        let drafts = editor.actions
        let saved = editor.prepareConfigForSave()
        XCTAssertEqual(saved.actions?.map(\.name), ["Build app"], "Incomplete actions must remain local drafts")
        let store = ProjectConfigStore(write: { _, _ in })
        store.store(original, forProjectPath: "/tmp/project-settings-echo")

        try await store.write(saved, forProjectPath: "/tmp/project-settings-echo")
        let echo = try XCTUnwrap(store.cached(forProjectPath: "/tmp/project-settings-echo"))
        editor.applyLoadedConfig(echo)
        editor.applyLoadedConfig(echo)

        XCTAssertEqual(editor.actions, drafts, "Notification and completion echoes must preserve unfinished rows and stable IDs")
        XCTAssertEqual(editor.actions.last?.name, "Test")
        XCTAssertEqual(editor.actions.last?.command, "")
    }

    func testConfigReconciliationStillAppliesDifferentExternalChanges() {
        var editor = ProjectSettingsEditorState(config: .empty)
        editor.actions.append(ProjectSettingsActionDraft(name: "Local", command: ""))
        _ = editor.prepareConfigForSave()
        let external = AlvearyProjectConfig(
            setupScript: "setup", actions: [.init(name: "Test", command: "swift test")]
        )

        editor.applyLoadedConfig(external)

        XCTAssertEqual(editor.setupScript, "setup")
        XCTAssertEqual(editor.actions.map(\.name), ["Test"])
        XCTAssertEqual(editor.actions.map(\.command), ["swift test"])
        XCTAssertEqual(editor.prepareConfigForSave(), external)
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
