import XCTest

@testable import Alveary

extension SnapshotTests {
    func testAddProjectSheetChooser() throws {
        let fixture = try SidebarTestFixture()

        assertMacSnapshot(
            AddProjectSheet(
                viewModel: fixture.viewModel,
                settingsService: fixture.settingsService,
                onChooseFromDisk: {},
                onProjectCreated: { _ in },
                initialStep: .chooser
            ),
            size: CGSize(width: 560, height: 360),
            named: "add_project_sheet_chooser"
        )
    }

    func testAddProjectSheetCloneForm() throws {
        let fixture = try SidebarTestFixture()
        var draft = AddProjectSheet.CloneDraft()
        draft.url = "https://github.com/afollestad/alveary.git"
        draft.parentPath = "~/Documents/code"
        draft.folderName = "alveary"
        draft.branch = ""

        assertMacSnapshot(
            AddProjectSheet(
                viewModel: fixture.viewModel,
                settingsService: fixture.settingsService,
                onChooseFromDisk: {},
                onProjectCreated: { _ in },
                initialStep: .cloneForm,
                initialDraft: draft
            ),
            size: CGSize(width: 560, height: 420),
            named: "add_project_sheet_clone_form"
        )
    }

    func testAddProjectSheetCloneRunning() throws {
        let fixture = try SidebarTestFixture()
        var draft = AddProjectSheet.CloneDraft()
        draft.url = "https://github.com/afollestad/alveary.git"
        draft.parentPath = "~/Documents/code"
        draft.folderName = "alveary"

        assertMacSnapshot(
            AddProjectSheet(
                viewModel: fixture.viewModel,
                settingsService: fixture.settingsService,
                onChooseFromDisk: {},
                onProjectCreated: { _ in },
                initialStep: .cloneRunning,
                initialDraft: draft
            ),
            size: CGSize(width: 560, height: 320),
            named: "add_project_sheet_clone_running"
        )
    }

    func testAddProjectSheetCloneFailed() throws {
        let fixture = try SidebarTestFixture()
        var draft = AddProjectSheet.CloneDraft()
        draft.url = "https://github.com/afollestad/alveary.git"
        draft.parentPath = "~/Documents/code"
        draft.folderName = "alveary"

        assertMacSnapshot(
            AddProjectSheet(
                viewModel: fixture.viewModel,
                settingsService: fixture.settingsService,
                onChooseFromDisk: {},
                onProjectCreated: { _ in },
                initialStep: .cloneFailed("fatal: repository 'https://example.com/missing.git' not found"),
                initialDraft: draft
            ),
            size: CGSize(width: 560, height: 340),
            named: "add_project_sheet_clone_failed"
        )
    }
}
