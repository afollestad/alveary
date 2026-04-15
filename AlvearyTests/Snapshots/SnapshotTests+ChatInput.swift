import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testChatInputFieldBusyEmptyPlaceholder() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant(""),
                mode: .busy(canStop: true),
                onSubmit: {},
                onSteer: {},
                onStop: {},
                selectedModel: .constant("sonnet"),
                selectedEffort: .constant("high"),
                selectedPermissionMode: .constant("acceptEdits"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_busy_empty_placeholder"
        )
    }

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
                supportedEffortLevels: ["low", "medium", "high"],
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

    func testChatInputFieldBusyStopHint() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Focus on the failing Settings screen snapshots next."),
                mode: .busy(canStop: true),
                onSubmit: {},
                onSteer: {},
                onStop: {},
                showsStopShortcutHint: true,
                selectedModel: .constant("sonnet"),
                selectedEffort: .constant("high"),
                selectedPermissionMode: .constant("acceptEdits"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_busy_stop_hint"
        )
    }
}
