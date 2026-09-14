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

    func testEditingEitherPlaceholderFieldCreatesOneNewRowWithoutReplacingEditors() throws {
        let firstEdits = [
            ProjectSettingsActionDraft(name: "Build", command: ""),
            ProjectSettingsActionDraft(name: "", command: "swift build")
        ]

        for firstEdit in firstEdits {
            var editor = ProjectSettingsEditorState(config: .empty)
            let editedRowID = try XCTUnwrap(editor.actions.first?.id)
            editor.actions[0].name = firstEdit.name
            editor.actions[0].command = firstEdit.command

            editor.ensureTrailingBlankActionRow()

            XCTAssertEqual(editor.actions.count, 2)
            XCTAssertEqual(editor.actions.first?.id, editedRowID)
            XCTAssertEqual(editor.actions.last?.name, "")
            XCTAssertEqual(editor.actions.last?.command, "")
            XCTAssertNil(editor.prepareConfigForSave().actions, "Neither an incomplete action nor its placeholder belongs on disk")
            let rowIDs = editor.actions.map(\.id)

            editor.actions[0].name = "Build app"
            editor.ensureTrailingBlankActionRow()
            editor.actions[0].command = "swift build"
            editor.ensureTrailingBlankActionRow()

            XCTAssertEqual(editor.actions.map(\.id), rowIDs, "Continuing an edit must keep focus and must not accumulate blank rows")
            let savedActions = editor.prepareConfigForSave().actions
            XCTAssertEqual(savedActions?.map(\.name), ["Build app"])
            XCTAssertEqual(savedActions?.map(\.command), ["swift build"])
        }
    }

    func testIconAndWhitespaceEditsLeaveOnePlaceholderAndNoSavedAction() throws {
        var editor = ProjectSettingsEditorState(config: .empty)
        let placeholderID = try XCTUnwrap(editor.actions.first?.id)
        editor.actions[0].icon = "hammer"
        editor.actions[0].name = "  "
        editor.actions[0].command = "\n "

        editor.ensureTrailingBlankActionRow()
        let saved = editor.prepareConfigForSave()
        editor.applyLoadedConfig(saved)

        XCTAssertEqual(editor.actions.map(\.id), [placeholderID])
        XCTAssertEqual(editor.actions.first?.icon, "hammer", "A save echo must not discard the selected icon for the next action")
        XCTAssertNil(saved.actions)
    }

    func testRemovingLastConfiguredActionKeepsTheAvailablePlaceholder() throws {
        let original = AlvearyProjectConfig(actions: [.init(name: "Build", command: "swift build")])
        var editor = ProjectSettingsEditorState(config: original)
        let placeholderID = try XCTUnwrap(editor.actions.last?.id)

        editor.actions.remove(at: 0)
        editor.ensureTrailingBlankActionRow()

        XCTAssertEqual(editor.actions.map(\.id), [placeholderID])
        XCTAssertEqual(editor.actions.first?.name, "")
        XCTAssertEqual(editor.actions.first?.command, "")
        XCTAssertNil(editor.prepareConfigForSave().actions)
    }

    @MainActor
    func testOwnConfigSaveEchoPreservesIncompleteActionsAndEditedRowIdentity() async throws {
        let original = AlvearyProjectConfig(actions: [.init(name: "Build", command: "swift build")])
        var editor = ProjectSettingsEditorState(config: original)
        editor.actions[0].name = "Build app"
        editor.actions[1].name = "Test"
        editor.ensureTrailingBlankActionRow()
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
        XCTAssertEqual(editor.actions.map(\.name), ["Build app", "Test", ""])
        XCTAssertEqual(editor.actions.map(\.command), ["swift build", "", ""])
    }

    func testConfigReconciliationStillAppliesDifferentExternalChanges() {
        var editor = ProjectSettingsEditorState(config: .empty)
        editor.actions[0].name = "Local"
        editor.ensureTrailingBlankActionRow()
        _ = editor.prepareConfigForSave()
        let external = AlvearyProjectConfig(
            setupScript: "setup", actions: [.init(name: "Test", command: "swift test")]
        )

        editor.applyLoadedConfig(external)

        XCTAssertEqual(editor.setupScript, "setup")
        XCTAssertEqual(editor.actions.map(\.name), ["Test", ""])
        XCTAssertEqual(editor.actions.map(\.command), ["swift test", ""])
        XCTAssertEqual(editor.prepareConfigForSave(), external)

        editor.applyLoadedConfig(.empty)

        XCTAssertEqual(editor.actions.map(\.name), [""])
        XCTAssertEqual(editor.actions.map(\.command), [""])
        XCTAssertNil(editor.prepareConfigForSave().actions)
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
