import XCTest

@testable import Alveary

extension SnapshotTests {
    var samplePermissionModes: [PermissionModeOption] {
        [
            PermissionModeOption(value: "default", label: "Default", description: "Ask before file edits and restricted tool actions."),
            PermissionModeOption(
                value: "acceptEdits",
                label: "Accept edits",
                description: "Automatically allow file edits, but ask for other sensitive actions."
            ),
            PermissionModeOption(value: "auto", label: "Automatic", description: "Automatically approve most actions with safety checks.")
        ]
    }

    var sampleGroupTools: [ToolEntry] {
        [
            ToolEntry(
                id: "read-auth",
                name: "Read",
                summary: "Read `auth.swift`",
                input: "{\"file_path\":\"Sources/auth.swift\",\"offset\":1,\"limit\":40}",
                output: "1\timport Foundation\n2\tstruct AuthManager {}",
                stderr: nil,
                isComplete: true,
                isInterrupted: false,
                isImage: false,
                noOutputExpected: false,
                isError: false
            ),
            ToolEntry(
                id: "read-session",
                name: "Read",
                summary: "Read `session.swift`",
                input: "{\"file_path\":\"Sources/session.swift\"}",
                output: "1\timport Foundation",
                stderr: nil,
                isComplete: true,
                isInterrupted: false,
                isImage: false,
                noOutputExpected: false,
                isError: false
            ),
            ToolEntry(
                id: "grep-retry",
                name: "Grep",
                summary: "Searching for pattern `retry(`",
                input: "{\"pattern\":\"retry(\"}",
                output: "Sources/session.swift: retry(after:)",
                stderr: nil,
                isComplete: true,
                isInterrupted: false,
                isImage: false,
                noOutputExpected: false,
                isError: false
            )
        ]
    }

    var sampleGroupToolsInProgress: [ToolEntry] {
        [
            ToolEntry(
                id: "read-auth-pending",
                name: "Read",
                summary: "Read `auth.swift`",
                input: "{\"file_path\":\"Sources/auth.swift\"}",
                output: nil,
                stderr: nil,
                isComplete: true,
                isInterrupted: false,
                isImage: false,
                noOutputExpected: false,
                isError: false
            ),
            ToolEntry(
                id: "grep-retry-pending",
                name: "Grep",
                summary: "Searching for pattern `retry(`",
                input: "{\"pattern\":\"retry(\"}",
                output: nil,
                stderr: nil,
                isComplete: false,
                isInterrupted: false,
                isImage: false,
                noOutputExpected: false,
                isError: false
            )
        ]
    }

    var sampleGroupToolsWithError: [ToolEntry] {
        [
            ToolEntry(
                id: "read-missing",
                name: "Read",
                summary: "Read `missing.swift`",
                input: "{\"file_path\":\"Sources/missing.swift\"}",
                output: "File does not exist",
                stderr: nil,
                isComplete: true,
                isInterrupted: false,
                isImage: false,
                noOutputExpected: false,
                isError: true
            ),
            ToolEntry(
                id: "read-session-ok",
                name: "Read",
                summary: "Read `session.swift`",
                input: "{\"file_path\":\"Sources/session.swift\"}",
                output: "1\timport Foundation",
                stderr: nil,
                isComplete: true,
                isInterrupted: false,
                isImage: false,
                noOutputExpected: false,
                isError: false
            )
        ]
    }

    var sampleStandaloneEditTool: ToolEntry {
        ToolEntry(
            id: "edit-auth",
            name: "Edit",
            summary: "Edit `auth.swift`",
            input: "{\"file_path\":\"Sources/auth.swift\",\"old_string\":\"old\",\"new_string\":\"new\"}",
            output: nil,
            stderr: nil,
            isComplete: false,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
    }

    var sampleStandaloneSkillTool: ToolEntry {
        ToolEntry(
            id: "skill-watermark",
            name: "Skill",
            summary: "Invoking skill `ai-rules-generated-watermark-portfolio-images`",
            input: "{\"skill\":\"ai-rules-generated-watermark-portfolio-images\"}",
            output: "Launching skill: ai-rules-generated-watermark-portfolio-images",
            stderr: nil,
            isComplete: true,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
    }

    var sampleStandaloneBashErrorTool: ToolEntry {
        ToolEntry(
            id: "sleep-10",
            name: "Bash",
            summary: "Executing `sleep 10`",
            input: "{\"command\":\"sleep 10\",\"description\":\"Sleep for 10 seconds\"}",
            output: "<tool_use_error>Blocked: standalone sleep 10. Run blocking commands in the background with run_in_background",
            stderr: nil,
            isComplete: true,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: true
        )
    }

    var sampleStandaloneBashPwdTool: ToolEntry {
        ToolEntry(
            id: "pwd",
            name: "Bash",
            summary: "Executing `pwd`",
            input: "{\"command\":\"pwd\",\"description\":\"Print current directory\"}",
            output: "/Users/afollestad/Development/alveary",
            stderr: nil,
            isComplete: true,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
    }

    var sampleStandaloneBashDateTool: ToolEntry {
        ToolEntry(
            id: "date",
            name: "Bash",
            summary: "Executing `date`",
            input: "{\"command\":\"date\",\"description\":\"Print current date\"}",
            output: "Fri Apr 24 18:41:48 CDT 2026",
            stderr: nil,
            isComplete: true,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
    }

    var sampleTasks: [TaskEntry] {
        [
            TaskEntry(id: "task-progress", content: "Refresh snapshots", activeForm: "Refreshing snapshots", status: .inProgress),
            TaskEntry(id: "task-pending", content: "Run focused UI tests", activeForm: nil, status: .pending),
            TaskEntry(id: "task-complete", content: "Fix autocomplete warning", activeForm: nil, status: .completed)
        ]
    }

    var samplePrompt: PromptEntry {
        PromptEntry(
            id: "prompt-framework",
            questions: [
                PromptEntry.PromptQuestion(
                    question: "Which framework should we use for the new snapshots?",
                    header: "Framework",
                    options: [
                        .init(label: "SnapshotTesting", description: "Point-Free's cross-platform snapshot library."),
                        .init(label: "Custom Harness", description: "Roll our own image-based assertions."),
                        .init(label: "Skip Snapshots", description: "Rely only on unit coverage for UI logic.")
                    ],
                    multiSelect: false
                )
            ],
            submittedSummary: nil
        )
    }

    var answeredPrompt: PromptEntry {
        PromptEntry(
            id: "prompt-framework-answered",
            questions: samplePrompt.questions,
            submittedSummary: "Q: Which framework should we use for the new snapshots?\nA: SnapshotTesting"
        )
    }

    var customResponsePrompt: PromptEntry {
        PromptEntry(
            id: "prompt-custom-response",
            questions: [
                PromptEntry.PromptQuestion(
                    question: "Which framework should we use for the new snapshots?",
                    header: "Framework",
                    options: [
                        .init(label: "SnapshotTesting", description: "Point-Free's cross-platform snapshot library."),
                        .init(label: "Custom Harness", description: "Roll our own image-based assertions."),
                        .init(label: "Skip Snapshots", description: "Rely only on unit coverage for UI logic.")
                    ],
                    multiSelect: false
                )
            ],
            submittedSummary: nil
        )
    }

    var planModePrompt: PromptEntry {
        PromptEntry(
            id: "prompt-plan-mode",
            questions: [
                PromptEntry.PromptQuestion(
                    question: "Where should a new contact section go?",
                    header: "Placement",
                    options: [
                        .init(label: "Bottom of page", description: "After the photo gallery."),
                        .init(label: "Between intro and experience", description: "Higher on the page.")
                    ],
                    multiSelect: false
                ),
                PromptEntry.PromptQuestion(
                    question: "How should contact be surfaced?",
                    header: "Contact UI",
                    options: [
                        .init(label: "Email link", description: "Simple mailto link."),
                        .init(label: "Social icons", description: "Row of social icon links.")
                    ],
                    multiSelect: false
                ),
                PromptEntry.PromptQuestion(
                    question: "Which button style?",
                    header: "Style",
                    options: [
                        .init(label: "Existing button pattern", description: "Match scroll-to-* buttons."),
                        .init(label: "Spectre card", description: "Use a card component.")
                    ],
                    multiSelect: false
                )
            ],
            submittedSummary: nil
        )
    }
}
