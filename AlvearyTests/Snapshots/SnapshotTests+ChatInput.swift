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

    func testChatInputFieldContextWindowProgress() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Investigate the flaky login flow and summarize what changed."),
                mode: .idle,
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("sonnet"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                usageSummary: ConversationUsageSummary(
                    contextUsedTokens: 186_000,
                    contextWindowSize: 200_000,
                    totalCostUsd: 1.42,
                    hasReportedUsage: true,
                    isUsingCachedContextWindow: false
                ),
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 900, height: 240),
            named: "chat_input_context_window_progress"
        )
    }

    func testChatInputFieldContextWindowCachedEmptyProgress() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Investigate the flaky login flow and summarize what changed."),
                mode: .idle,
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("sonnet"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                usageSummary: ConversationUsageSummary(
                    contextUsedTokens: 0,
                    contextWindowSize: 200_000,
                    totalCostUsd: 0,
                    hasReportedUsage: false,
                    isUsingCachedContextWindow: true
                ),
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 900, height: 240),
            named: "chat_input_context_window_cached_empty"
        )
    }

    func testChatInputFieldBusyStopConfirm() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Focus on the failing Settings screen snapshots next."),
                mode: .busy(canStop: true),
                onSubmit: {},
                onSteer: {},
                onStop: {},
                isStopConfirmationArmed: .constant(true),
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
            named: "chat_input_busy_stop_confirm"
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

    func testChatInputFieldSessionHandoffProgress() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant(""),
                mode: .progressOnly(.sessionHandoff),
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("sonnet"),
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
            named: "chat_input_session_handoff_progress"
        )
    }

    func testChatInputFieldHandoffSteeringSubmit() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Focus the handoff on the remaining snapshot and integration checks."),
                mode: .idle,
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("sonnet"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: false,
                isHandoffSteeringPromptActive: true,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_handoff_steering_submit"
        )
    }

    func testChatInputFieldHandoffSteeringSubmitCountdown() {
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
                supportsMidTurnSteering: false,
                isHandoffSteeringPromptActive: true,
                handoffSteeringCountdown: 10,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_handoff_steering_submit_countdown"
        )
    }

    func testChatInputFieldGeneratedHandoffSendCountdown() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("""
                Primary goal:
                - Continue the session handoff implementation and validation.

                Current state:
                - Generated handoff context is staged for review.
                - The composer should expand to fit this handoff result.
                - The submit countdown remains visible while the user can edit.
                """),
                mode: .idle,
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("sonnet"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: false,
                isHandoffOutputPromptActive: true,
                sendCountdown: 10,
                workingDirectory: "/tmp/alveary",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_generated_handoff_send_countdown"
        )
    }

    func testInlineBannerErrorWithRetryAction() {
        assertMacSnapshot(
            InlineBanner(
                message: "Session handoff failed: the hidden handoff prompt returned no context.",
                severity: .error,
                autoDismissAfter: nil,
                actionTitle: "Retry",
                onAction: {}
            )
            .padding(20),
            size: CGSize(width: 760, height: 110),
            named: "inline_banner_error_retry"
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

    func testAppTextEditorCodeBlock() {
        assertMacSnapshot(
            AppTextEditor(
                text: .constant("Test\n```\nlet value = 1\nprint(value)"),
                minHeight: 120,
                idealHeight: 120,
                maxHeight: 160,
                placeholder: "Ask anything, @ to add files, / for skills",
                cornerRadius: 18,
                horizontalPadding: 10,
                verticalPadding: 10,
                sizesToContent: true,
                textChips: ChatInputFieldTextSupport.composerTextChips(in:),
                codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
                inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
                inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
                inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges }
            ),
            size: CGSize(width: 360, height: 170),
            named: "app_text_editor_code_block",
            colorScheme: .dark
        )
    }

    func testAppTextEditorLeadingCodeBlock() {
        assertMacSnapshot(
            AppTextEditor(
                text: .constant("```\nTest"),
                minHeight: 96,
                idealHeight: 96,
                maxHeight: 144,
                placeholder: "Ask anything, @ to add files, / for skills",
                cornerRadius: 18,
                horizontalPadding: 10,
                verticalPadding: 10,
                sizesToContent: true,
                textChips: ChatInputFieldTextSupport.composerTextChips(in:),
                codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
                inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
                inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
                inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges }
            ),
            size: CGSize(width: 360, height: 140),
            named: "app_text_editor_leading_code_block",
            colorScheme: .dark
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
