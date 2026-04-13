import XCTest

@testable import Alveary

extension SnapshotTests {
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
