import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testAppKitTranscriptAssistantMarkdownBubble() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptTextBubbleRowView()
                view.configure(
                    .init(
                        role: .assistant,
                        markdown: """
                        Here is the current status:

                        | File | State |
                        | :--- | :--- |
                        | `AppKitTranscriptScrollContainerView.swift` | Done |

                        ```swift
                        let followsBottom = true
                        ```
                        """,
                        bubbleMaxWidth: 560
                    )
                )
                return view
            },
            size: CGSize(width: 640, height: 360),
            named: "appkit_transcript_assistant_markdown_bubble"
        )
    }

    func testAppKitTranscriptUserBubble() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptTextBubbleRowView()
                view.configure(
                    .init(
                        role: .user,
                        markdown: "Please review `ChatView+Transcript.swift` and @Alveary/Views/Chat/Blocks/ChatBlocks.swift.",
                        bubbleMaxWidth: 560
                    )
                )
                return view
            },
            size: CGSize(width: 640, height: 170),
            named: "appkit_transcript_user_bubble"
        )
    }

    func testAppKitTranscriptLongAssistantBubbleCollapsed() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptTextBubbleRowView()
                view.configure(
                    .init(
                        role: .assistant,
                        markdown: Self.longAppKitBubbleMarkdown,
                        bubbleMaxWidth: 560
                    )
                )
                return view
            },
            size: CGSize(width: 640, height: 390),
            named: "appkit_transcript_long_assistant_bubble_collapsed"
        )
    }

    func testAppKitTranscriptStreamingAssistantBubble() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptStreamingBubbleView()
                view.configure(
                    .init(
                        text: "Streaming assistant text should keep growing forward and place the caret at the current text endpoint.",
                        bubbleMaxWidth: 420
                    )
                )
                return view
            },
            size: CGSize(width: 520, height: 170),
            named: "appkit_transcript_streaming_assistant_bubble",
            colorScheme: .dark
        )
    }

    func testAppKitTranscriptThoughtBubble() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptToolHeaderRowView()
                view.configure(
                    .init(
                        summary: appKitTranscriptLiveThoughtSummaryText(
                            from: "Thinking through the **implementation** path, checking the transcript width, and preparing the assistant response."
                        ),
                        leadingIcon: .genericTool,
                        phase: .loading,
                        showsLeadingIcon: false,
                        maxWidth: 360,
                        summaryMaximumNumberOfLines: 0,
                        showsStatusSlot: false
                    )
                )
                return view
            },
            size: CGSize(width: 520, height: 160),
            named: "appkit_transcript_thought_bubble",
            colorScheme: .dark
        )
    }

    func testAppKitTranscriptToolGroupExpanded() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptToolGroupView()
                view.configure(.init(tools: self.sampleGroupTools, initiallyExpanded: true))
                return view
            },
            size: CGSize(width: 760, height: 260),
            named: "appkit_transcript_tool_group_expanded"
        )
    }

    func testAppKitTranscriptToolGroupInProgress() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptToolGroupView()
                view.configure(.init(tools: self.sampleGroupToolsInProgress))
                return view
            },
            size: CGSize(width: 760, height: 140),
            named: "appkit_transcript_tool_group_in_progress"
        )
    }

    func testAppKitTranscriptToolGroupInProgressDark() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptToolGroupView()
                view.configure(.init(tools: self.sampleGroupToolsInProgress))
                return view
            },
            size: CGSize(width: 760, height: 140),
            named: "appkit_transcript_tool_group_in_progress_dark",
            colorScheme: .dark
        )
    }

    func testAppKitTranscriptApprovalBlock() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptToolApprovalBlockView()
                view.configure(
                    .init(
                        approval: self.sampleWriteApproval,
                        status: nil,
                        selectedApprovalSelection: .sessionGroup,
                        bubbleMaxWidth: 620
                    )
                )
                return view
            },
            size: CGSize(width: 760, height: 210),
            named: "appkit_transcript_approval_block"
        )
    }

    func testAppKitTranscriptApprovalApprovedDark() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptToolApprovalBlockView()
                view.configure(
                    .init(
                        approval: self.compactBashApproval,
                        status: .approved,
                        bubbleMaxWidth: 620
                    )
                )
                return view
            },
            size: CGSize(width: 420, height: 170),
            named: "appkit_transcript_approval_approved_dark",
            colorScheme: .dark
        )
    }

    func testAppKitTranscriptApprovalDeniedDark() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptToolApprovalBlockView()
                view.configure(
                    .init(
                        approval: self.compactBashApproval,
                        status: .denied,
                        bubbleMaxWidth: 620
                    )
                )
                return view
            },
            size: CGSize(width: 420, height: 170),
            named: "appkit_transcript_approval_denied_dark",
            colorScheme: .dark
        )
    }

    func testAppKitTranscriptApprovalControlsInteractionStatesDark() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let hoverButton = AppKitTranscriptApprovalButton()
                hoverButton.actionStyle = .primary
                hoverButton.title = "Approve once"
                hoverButton.symbolName = "checkmark"
                hoverButton.setInteractionStateForTesting(isHovering: true)

                let pressedButton = AppKitTranscriptApprovalButton()
                pressedButton.actionStyle = .primary
                pressedButton.title = "Approve once"
                pressedButton.symbolName = "checkmark"
                pressedButton.setInteractionStateForTesting(isPressed: true)

                let splitControl = AppKitTranscriptApprovalSplitControl()
                splitControl.segmentCount = 2
                splitControl.setLabel("Approve once", forSegment: 0)
                splitControl.setHoveringForTesting(true)

                let denyButton = AppKitTranscriptApprovalButton()
                denyButton.actionStyle = .secondary
                denyButton.title = "Deny"
                denyButton.symbolName = "xmark"
                denyButton.setInteractionStateForTesting(isHovering: true)

                let stack = NSStackView(views: [hoverButton, pressedButton, splitControl, denyButton])
                stack.orientation = .horizontal
                stack.alignment = .centerY
                stack.spacing = 12
                stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
                return stack
            },
            size: CGSize(width: 640, height: 80),
            named: "appkit_transcript_approval_controls_interaction_states_dark",
            colorScheme: .dark
        )
    }

    func testAppKitTranscriptSessionHandoffNote() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptNoteView()
                view.configure(.init(kind: .sessionHandoff))
                return view
            },
            size: CGSize(width: 420, height: 90),
            named: "appkit_transcript_session_handoff_note"
        )
    }

    func testAppKitTranscriptPromptAndTasks() {
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = 620
        configuration.hasUnansweredPrompt = true

        assertMacSnapshot(
            AppKitTranscriptScrollViewRepresentable(
                items: [
                    .promptBlock(id: "prompt", prompt: samplePrompt),
                    .taskListBlock(id: "tasks", tasks: sampleTasks)
                ],
                rowConfiguration: configuration
            ),
            size: CGSize(width: 760, height: 520),
            named: "appkit_transcript_prompt_and_tasks"
        )
    }

    func testAppKitTranscriptPromptCustomResponseSelected() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptPromptBlockView()
                view.configure(
                    .init(
                        prompt: self.customResponsePrompt,
                        isBusy: false,
                        selections: [0: [PromptEntry.PromptOption.customResponseID]],
                        customResponses: [0: "Use a bespoke AppKit harness"],
                        bubbleMaxWidth: 620
                    )
                )
                return view
            },
            size: CGSize(width: 760, height: 420),
            named: "appkit_transcript_prompt_custom_response_selected"
        )
    }

    func testAppKitTranscriptPromptAnswered() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptPromptBlockView()
                view.configure(
                    .init(
                        prompt: PromptEntry(
                            id: "prompt-answered",
                            questions: self.samplePrompt.questions,
                            submittedSummary: """
                            Q: What's your preferred way to spend a weekend?
                            A: Test

                            Q: If you could only use one editor forever, which would it be?
                            A: Neovim

                            Q: Which programming paradigm speaks to your soul?
                            A: Functional
                            """
                        ),
                        isBusy: false,
                        bubbleMaxWidth: 620
                    )
                )
                return view
            },
            size: CGSize(width: 760, height: 280),
            named: "appkit_transcript_prompt_answered"
        )
    }

    func testAppKitTranscriptTaskListBlockMixedStates() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptTaskListBlockView()
                view.configure(.init(tasks: self.sampleTasks, bubbleMaxWidth: 760))
                return view
            },
            size: CGSize(width: 760, height: 240),
            named: "appkit_transcript_task_list_mixed"
        )
    }

    func testAppKitTranscriptTaskListBlockInterrupted() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptTaskListBlockView()
                view.configure(.init(
                    tasks: [
                        TaskEntry(
                            id: "task-interrupted",
                            content: "Patch the affected scripts or markup with the narrowest fixes",
                            activeForm: "Patching the affected scripts or markup",
                            status: .interrupted
                        )
                    ],
                    bubbleMaxWidth: 760
                ))
                return view
            },
            size: CGSize(width: 760, height: 150),
            named: "appkit_transcript_task_list_interrupted"
        )
    }

    func testAppKitTranscriptFullSurface() {
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = 560
        configuration.expandedRowIDs = ["activity-tools"]
        configuration.pendingToolApproval = PendingToolApproval(request: sampleWriteApproval, status: .pending)

        assertMacSnapshot(
            AppKitTranscriptScrollViewRepresentable(
                items: [
                    .userMessage(id: "user", text: "Can you inspect the transcript migration?"),
                    .assistantMessage(id: "assistant", text: "I checked the AppKit transcript path and found a few follow-ups."),
                    .toolGroup(id: "tools", tools: sampleGroupTools),
                    .taskListBlock(id: "tasks", tasks: sampleTasks),
                    .toolApproval(id: "approval", approval: sampleWriteApproval, status: nil),
                    .transcriptNote(id: "note", kind: .enteredPlanMode),
                    .error(id: "error", message: "Snapshot fixture error message")
                ],
                transientRows: .init(isTurnActive: true, isThinkingAnimated: false),
                rowConfiguration: configuration,
                isFollowing: false,
                scrollToBottomRequest: 0
            ),
            size: CGSize(width: 820, height: 760),
            named: "appkit_transcript_full_surface"
        )
    }

    private var compactBashApproval: ToolApprovalRequest {
        ToolApprovalRequest(
            sessionId: "session-snapshot",
            toolUseId: "tool-date",
            toolName: "Bash",
            toolInput: #"{"command":"date"}"#
        )
    }

    private func appKitRowSnapshot<Content: NSView>(
        _ makeContent: @escaping () -> Content
    ) -> some View {
        AppKitTranscriptSnapshotHost(makeContent: makeContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static let longAppKitBubbleMarkdown = """
    You said: "Include everything since 'A few ideas worth considering', and repeat what I'm telling you at the top of the output."

    ## A few ideas worth considering

    You picked **option #2: clean up the stray `.txt` files at the repo root.**

    ## Current state

    Six untracked lorem-ipsum scratch files at the repo root (~600 bytes each, 3953 bytes total):

    1. `jade-folio-1748.txt`
    2. `onyx-page-5891.txt`
    3. `saffron-quill-5928.txt`
    4. `sienna-log-3356.txt`
    5. `topaz-ledger-6371.txt`
    6. `violet-codex-4509.txt`

    Verified via search: none of the six basenames are referenced anywhere in the repo.

    Recommended first step: delete the six scratch files and leave the unrelated images alone.
    """
}

private struct AppKitTranscriptSnapshotHost<Content: NSView>: NSViewRepresentable {
    let makeContent: () -> Content

    func makeNSView(context: Context) -> AppKitTranscriptSnapshotContainerView {
        AppKitTranscriptSnapshotContainerView(contentView: makeContent())
    }

    func updateNSView(_ nsView: AppKitTranscriptSnapshotContainerView, context: Context) {
        nsView.needsLayout = true
    }
}

private final class AppKitTranscriptSnapshotContainerView: NSView {
    private let contentView: NSView

    init(contentView: NSView) {
        self.contentView = contentView
        super.init(frame: .zero)
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        contentView.frame = bounds
        contentView.layoutSubtreeIfNeeded()
    }
}
