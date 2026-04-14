import XCTest

@testable import Alveary

extension SnapshotTests {
    var samplePermissionModes: [PermissionModeOption] {
        [
            PermissionModeOption(value: "default", label: "Ask", description: "Prompt before tool actions."),
            PermissionModeOption(value: "acceptEdits", label: "Auto-Edit", description: "Allow edit tools without asking."),
            PermissionModeOption(value: "auto", label: "Auto", description: "Allow safe actions automatically.")
        ]
    }

    var sampleFileAutocomplete: ComposerAutocompleteState {
        ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 22..<31,
            query: "aut",
            source: nil,
            suggestions: [
                ComposerAutocompleteSuggestion(
                    id: "Alveary/Views/Input/ChatInputAutocomplete.swift",
                    title: "ChatInputAutocomplete.swift",
                    subtitle: "Alveary/Views/Input",
                    replacementText: "@Alveary/Views/Input/ChatInputAutocomplete.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "Alveary/Views/Chat/ChatSupplementaryViews.swift",
                    title: "ChatSupplementaryViews.swift",
                    subtitle: "Alveary/Views/Chat",
                    replacementText: "@Alveary/Views/Chat/ChatSupplementaryViews.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "AlvearyTests/Snapshots/SnapshotTestSupport.swift",
                    title: "SnapshotTestSupport.swift",
                    subtitle: "AlvearyTests/Snapshots",
                    replacementText: "@AlvearyTests/Snapshots/SnapshotTestSupport.swift",
                    symbolName: "doc.text"
                )
            ],
            totalMatches: 8,
            highlightedIndex: 1,
            isLoading: false
        )
    }

    var sampleSkillAutocomplete: ComposerAutocompleteState {
        ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .skill,
            replacementOffsets: 0..<4,
            query: "ios",
            source: nil,
            suggestions: [
                ComposerAutocompleteSuggestion(
                    id: "skill-ios-accessibility",
                    title: "ios-accessibility",
                    subtitle: "Audit SwiftUI screens for VoiceOver and Dynamic Type issues.",
                    replacementText: "/ios-accessibility",
                    symbolName: "sparkles"
                ),
                ComposerAutocompleteSuggestion(
                    id: "skill-ios-debugging",
                    title: "ios-debugging",
                    subtitle: "Set up and troubleshoot iOS debugging without opening Xcode.",
                    replacementText: "/ios-debugging",
                    symbolName: "sparkles"
                ),
                ComposerAutocompleteSuggestion(
                    id: "skill-ios-simulator",
                    title: "ios-simulator",
                    subtitle: "Start, stop, and manage iOS simulators for testing.",
                    replacementText: "/ios-simulator",
                    symbolName: "sparkles"
                )
            ],
            totalMatches: 3,
            highlightedIndex: 0,
            isLoading: false
        )
    }

    var sampleTools: [ToolEntry] {
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
        ]
    }

    var sampleErrorTools: [ToolEntry] {
        [
            ToolEntry(
                id: "sleep-10",
                name: "Bash",
                summary: "`sleep 10`",
                input: "{\"command\":\"sleep 10\",\"description\":\"Sleep for 10 seconds\"}",
                output: "<tool_use_error>Blocked: standalone sleep 10. Run blocking commands in the background with run_in_background",
                stderr: nil,
                isComplete: true,
                isInterrupted: false,
                isImage: false,
                noOutputExpected: false,
                isError: true
            )
        ]
    }

    var sampleSubAgents: [SubAgentEntry] {
        [
            SubAgentEntry(
                id: "agent-search",
                agentType: "search",
                description: "Search for the stale permission banner logic",
                statusDescription: "Scanning the current chat stack",
                lastToolName: "Read",
                tools: [],
                result: nil,
                isComplete: false,
                toolUseCount: 3,
                totalTokens: 8_200,
                durationMs: 1_400
            ),
            SubAgentEntry(
                id: "agent-tests",
                agentType: "validation",
                description: "Review the existing snapshot coverage",
                statusDescription: nil,
                lastToolName: nil,
                tools: [],
                result: "PromptBlock and MCP screen states still need coverage.",
                isComplete: true,
                toolUseCount: 5,
                totalTokens: 12_400,
                durationMs: 2_300
            )
        ]
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
            submittedSummary: "Which framework should we use for the new snapshots?: SnapshotTesting"
        )
    }
}
