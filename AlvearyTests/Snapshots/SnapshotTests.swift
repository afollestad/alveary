import XCTest
import SwiftUI

@testable import Alveary

@MainActor
final class SnapshotTests: XCTestCase {
    func testChatInputFieldIdle() {
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
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_idle"
        )
    }

    func testChatInputFieldBusySteering() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Focus on the failing Settings screen snapshots next."),
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
            named: "chat_input_busy_steering"
        )
    }

    func testChatInputFieldProgressOnly() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Review the updated MCP cards once the session comes back."),
                mode: .progressOnly(.initialSetup),
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("default"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: false,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_progress_only"
        )
    }

    func testChatInputFieldCancellingInitialSetup() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Review the updated MCP cards once the session comes back."),
                mode: .progressOnly(.cancellingInitialSetup),
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("default"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: false,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_cancelling_initial_setup"
        )
    }

    func testChatInputFieldBusyProgressOnly() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Follow up on the diff audit after the current turn finishes."),
                mode: .busy(canStop: false),
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("default"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_busy_progress_only"
        )
    }

    func testChatInputFieldComposerChips() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("/ios-accessibility inspect @Alveary/Views/Input/ChatInputField.swift next"),
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
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_composer_chips"
        )
    }

    func testAppTextEditorInlineHint() {
        let text = "/review-github-pr "
        let selection = TextSelection(insertionPoint: text.endIndex)

        assertMacSnapshot(
            AppTextEditor(
                text: .constant(text),
                selection: .constant(selection),
                minHeight: 68,
                idealHeight: 68,
                maxHeight: 144,
                placeholder: "Ask anything, @ to add files, / for skills",
                cornerRadius: 18,
                horizontalPadding: 10,
                verticalPadding: 10,
                sizesToContent: true,
                textChips: ChatInputFieldTextSupport.composerTextChips(in:),
                inlineHint: AppTextEditorInlineHint(text: "[PR URL]")
            ),
            size: CGSize(width: 760, height: 120),
            named: "app_text_editor_inline_hint"
        )
    }

    func testChatInputKeymapSheet() {
        assertMacSnapshot(
            ChatInputKeymapSheet(supportsMidTurnSteering: true),
            size: CGSize(width: 520, height: 320),
            named: "chat_input_keymap_sheet"
        )
    }

    func testQueuedMessageBubbleWithContextAndRetry() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant(""),
                mode: .busy(canStop: true),
                onSubmit: {},
                onSteer: {},
                onStop: {},
                selectedModel: .constant("default"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: true,
                queuedMessages: [
                    QueuedMessage(
                        text: "After the current turn, also validate the diff refresh logic against renamed files.",
                        stagedContext: "Context block"
                    ),
                    QueuedMessage(text: "Follow with the snapshot cleanup once the diff finishes loading.", stagedContext: nil),
                    QueuedMessage(text: "Confirm the retry badge renders on transcript failures.", stagedContext: nil)
                ],
                isTurnActive: true,
                inFlightQueuedMessageID: nil,
                onSteerQueuedMessage: { _ in },
                onEditQueuedMessage: { _ in },
                onDismissQueuedMessage: { _ in },
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 360),
            named: "queued_message_with_context"
        )
    }

    func testSkillsScreenPopulated() async {
        let viewModel = SkillsViewModel(skillsService: SnapshotSkillsService())
        await viewModel.load()

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_populated"
        )
    }

    func testMCPScreenPopulated() async {
        let viewModel = MCPViewModel(mcpService: SnapshotMCPService())
        await viewModel.load()

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "mcp_screen_populated"
        )
    }

}
