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

    func testChatInputFieldIdleWithWorktreeSessionLabel() {
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
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                sessionLocationLabel: "Worktree (feature-abc123)",
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 900, height: 240),
            named: "chat_input_idle_worktree_session_label"
        )
    }

    func testChatInputFieldIdleWithLocalSessionLabel() {
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
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                sessionLocationLabel: "Local",
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 900, height: 240),
            named: "chat_input_idle_local_session_label"
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

    func testChatInputFieldWaitingForQuestionResponse() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant(""),
                mode: .progressOnly(.toolApproval(.askUserQuestion)),
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("sonnet"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("plan"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: false,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_waiting_for_question_response"
        )
    }

    func testChatInputFieldProjectTrustBlocked() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant(""),
                mode: .idle,
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("sonnet"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: true,
                isProjectTrustBlocked: true,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_project_trust_blocked"
        )
    }

    func testChatInputFieldCodeBlocks() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Please tighten this up:\n```swift\nlet values = [1, 2, 3]\nprint(values)\n```"),
                mode: .idle,
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("default"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: true,
                queuedMessages: [
                    QueuedMessage(
                        text: "Queue this too:\n```bash\nnpm test\n```",
                        stagedContext: nil
                    )
                ],
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 900, height: 320),
            named: "chat_input_code_blocks"
        )
    }

    func testChatInputFieldInlineCode() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Please review `Sources/App.swift` next."),
                mode: .idle,
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("default"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: true,
                queuedMessages: [
                    QueuedMessage(
                        text: "Then check `Package.swift` too.",
                        stagedContext: nil
                    )
                ],
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 900, height: 280),
            named: "chat_input_inline_code"
        )
    }
}
