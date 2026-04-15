import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testChatInputFieldIdleWithWorktreePicker() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Investigate the flaky login flow and summarize what changed."),
                mode: .idle,
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("default"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                selectedUseWorktree: .constant(true),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["auto", "low", "medium", "high"],
                showWorktreePicker: true,
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 900, height: 240),
            named: "chat_input_idle_worktree_picker"
        )
    }
}
