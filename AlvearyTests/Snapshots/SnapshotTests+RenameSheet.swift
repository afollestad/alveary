import XCTest

@testable import Alveary

extension SnapshotTests {
    func testRenameSheetThread() {
        let draft = StubRenameDraft(
            currentDisplayName: "Refactor Chat Input",
            title: "Refactor Chat Input"
        )

        assertMacSnapshot(
            RenameSheet(
                draft: draft,
                heading: "Rename Thread",
                placeholder: "Thread name",
                closeLabel: "Close rename thread",
                onSave: { _ in true }
            ),
            size: CGSize(width: 480, height: 200),
            named: "rename_sheet_thread"
        )
    }

    func testRenameSheetConversation() {
        let draft = StubRenameDraft(
            currentDisplayName: "Main",
            title: "Main"
        )

        assertMacSnapshot(
            RenameSheet(
                draft: draft,
                heading: "Rename Conversation",
                placeholder: "Conversation name",
                closeLabel: "Close rename conversation",
                onSave: { _ in true }
            ),
            size: CGSize(width: 480, height: 200),
            named: "rename_sheet_conversation"
        )
    }
}

private struct StubRenameDraft: RenameDraft {
    let id = UUID()
    let currentDisplayName: String
    var title: String

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
