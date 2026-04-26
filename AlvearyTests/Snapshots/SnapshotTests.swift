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

    func testChatInputFieldBusyQueueOnly() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Queue the follow-up diff audit after the current turn finishes."),
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
            named: "chat_input_busy_queue_only"
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

    func testComposerAutocompletePopupFiles() {
        assertMacSnapshot(
            ComposerAutocompletePopup(
                autocomplete: sampleFileAutocomplete,
                onSelect: { _ in }
            ),
            size: CGSize(width: 540, height: 280),
            named: "composer_autocomplete_files"
        )
    }

    func testComposerAutocompletePopupScrolledHighlight() {
        assertMacSnapshot(
            ComposerAutocompletePopup(
                autocomplete: sampleScrolledFileAutocomplete,
                onSelect: { _ in }
            ),
            size: CGSize(width: 540, height: 280),
            named: "composer_autocomplete_files_scrolled_highlight"
        )
    }

    func testComposerAutocompletePopupSkills() {
        assertMacSnapshot(
            ComposerAutocompletePopup(
                autocomplete: sampleSkillAutocomplete,
                onSelect: { _ in }
            ),
            size: CGSize(width: 540, height: 280),
            named: "composer_autocomplete_skills"
        )
    }

    func testComposerAutocompletePopupEmptyState() {
        assertMacSnapshot(
            ComposerAutocompletePopup(
                autocomplete: sampleEmptyAutocomplete,
                onSelect: { _ in }
            ),
            size: CGSize(width: 540, height: 120),
            named: "composer_autocomplete_empty"
        )
    }

    func testComposerAutocompletePopupLoadingState() {
        assertMacSnapshot(
            ComposerAutocompletePopup(
                autocomplete: sampleLoadingAutocomplete,
                onSelect: { _ in }
            ),
            size: CGSize(width: 540, height: 120),
            named: "composer_autocomplete_loading"
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

    func testSubAgentBlockMixedStates() {
        assertMacSnapshot(
            SubAgentBlock(agents: sampleSubAgents, initiallyExpanded: true),
            size: CGSize(width: 760, height: 300),
            named: "subagent_block_mixed"
        )
    }

    func testSubAgentBlockExpandedBashTools() {
        assertMacSnapshot(
            SubAgentBlock(agents: [sampleSubAgentWithBashTools], initiallyExpanded: true),
            size: CGSize(width: 760, height: 160),
            named: "subagent_block_expanded_bash_tools"
        )
    }

    func testTaskListBlockMixedStates() {
        assertMacSnapshot(
            TaskListBlock(tasks: sampleTasks),
            size: CGSize(width: 760, height: 240),
            named: "task_list_mixed"
        )
    }

    func testPromptBlockUnanswered() {
        assertMacSnapshot(
            PromptBlock(prompt: samplePrompt, isBusy: false) { _ in nil },
            size: CGSize(width: 760, height: 420),
            named: "prompt_block_unanswered"
        )
    }

    func testPromptBlockAnswered() {
        assertMacSnapshot(
            PromptBlock(prompt: answeredPrompt, isBusy: false) { _ in nil },
            size: CGSize(width: 760, height: 220),
            named: "prompt_block_answered"
        )
    }

    func testPromptBlockCustomResponseSelected() {
        assertMacSnapshot(
            PromptBlock(
                prompt: customResponsePrompt,
                isBusy: false,
                initialSelections: [0: [PromptEntry.PromptOption.customResponseID]],
                initialCustomResponses: [0: "Use a bespoke AppKit harness"]
            ) { _ in nil },
            size: CGSize(width: 760, height: 420),
            named: "prompt_block_custom_response_selected"
        )
    }

    func testPromptBlockPlanModeMultiQuestion() {
        assertMacSnapshot(
            PromptBlock(prompt: planModePrompt, isBusy: false) { _ in nil },
            size: CGSize(width: 1200, height: 900),
            named: "prompt_block_plan_mode_multi_question"
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
