import XCTest

@testable import Alveary

@MainActor
extension ProjectSettingsViewTests {
    func testProjectSettingsRestoreConfirmationMessageExplainsRestoreBehavior() {
        let thread = AgentThread(
            name: "Rehydrate archived auth thread",
            worktreePath: "/tmp/alveary-worktree",
            archivedAt: Date()
        )

        let message = projectSettingsRestoreConfirmationMessage(for: thread)

        XCTAssertTrue(message.contains("puts it back in the project list"))
        XCTAssertTrue(message.contains("Local transcript and worktree metadata stay in Alveary"))
        XCTAssertTrue(message.contains("fresh provider session"))
        XCTAssertTrue(message.contains("attaches a restore summary to your next message"))
    }

    func testProjectSettingsDeleteConfirmationMessageMatchesNormalDeleteBehavior() {
        let thread = AgentThread(
            name: "Delete archived auth thread",
            worktreePath: "/tmp/alveary-worktree",
            archivedAt: Date()
        )

        let message = threadDeleteConfirmationMessage(for: thread)

        XCTAssertEqual(
            message,
            "This permanently deletes \"Delete archived auth thread\" and removes its worktree and branch if present."
        )
    }
}
