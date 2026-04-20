import XCTest

@testable import Alveary

extension SnapshotTests {
    var samplePermissionModes: [PermissionModeOption] {
        [
            PermissionModeOption(value: "default", label: "Default permissions", description: "Prompt before restricted tool actions."),
            PermissionModeOption(value: "acceptEdits", label: "Accept edits", description: "Allow edit tools without asking."),
            PermissionModeOption(value: "auto", label: "Automatic", description: "Allow safe actions automatically.")
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
                    title: "Alveary/Views/Input/ChatInputAutocomplete.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@Alveary/Views/Input/ChatInputAutocomplete.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "Alveary/Views/Chat/ChatSupplementaryViews.swift",
                    title: "~/Development/alveary/Alveary/Views/Chat/ChatSupplementaryViews.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@Alveary/Views/Chat/ChatSupplementaryViews.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "AlvearyTests/Snapshots/SnapshotTestSupport.swift",
                    title: "AlvearyTests/Snapshots/SnapshotTestSupport.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@AlvearyTests/Snapshots/SnapshotTestSupport.swift",
                    symbolName: "doc.text"
                )
            ],
            totalMatches: 8,
            highlightedIndex: 1,
            isLoading: false
        )
    }

    var sampleScrolledFileAutocomplete: ComposerAutocompleteState {
        ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 18..<27,
            query: "chat",
            source: nil,
            suggestions: [
                ComposerAutocompleteSuggestion(
                    id: "Alveary/AppDelegate.swift",
                    title: "Alveary/AppDelegate.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@Alveary/AppDelegate.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "Alveary/Views/Chat/ChatBlocks.swift",
                    title: "Alveary/Views/Chat/ChatBlocks.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@Alveary/Views/Chat/ChatBlocks.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "Alveary/Views/Chat/ChatSupplementaryViews.swift",
                    title: "Alveary/Views/Chat/ChatSupplementaryViews.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@Alveary/Views/Chat/ChatSupplementaryViews.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "Alveary/Views/Chat/ChatView.swift",
                    title: "Alveary/Views/Chat/ChatView.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@Alveary/Views/Chat/ChatView.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "Alveary/Views/Chat/ChatView+Transcript.swift",
                    title: "Alveary/Views/Chat/ChatView+Transcript.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@Alveary/Views/Chat/ChatView+Transcript.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "Alveary/Views/Input/ChatInputField.swift",
                    title: "Alveary/Views/Input/ChatInputField.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@Alveary/Views/Input/ChatInputField.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "Alveary/Views/Input/ChatInputField+Interactions.swift",
                    title: "Alveary/Views/Input/ChatInputField+Interactions.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@Alveary/Views/Input/ChatInputField+Interactions.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "Alveary/Views/Input/ChatInputAutocomplete.swift",
                    title: "Alveary/Views/Input/ChatInputAutocomplete.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@Alveary/Views/Input/ChatInputAutocomplete.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "AlvearyTests/AppKitTextEditorCoordinatorTests.swift",
                    title: "AlvearyTests/AppKitTextEditorCoordinatorTests.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@AlvearyTests/AppKitTextEditorCoordinatorTests.swift",
                    symbolName: "doc.text"
                )
            ],
            totalMatches: 9,
            highlightedIndex: 7,
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
                    trailingText: "Personal",
                    replacementText: "/ios-accessibility",
                    symbolName: "shippingbox"
                ),
                ComposerAutocompleteSuggestion(
                    id: "skill-ios-debugging",
                    title: "ios-debugging",
                    subtitle: "Set up and troubleshoot iOS debugging without opening Xcode.",
                    trailingText: "cash-ios",
                    replacementText: "/ios-debugging",
                    symbolName: "shippingbox"
                ),
                ComposerAutocompleteSuggestion(
                    id: "skill-ios-simulator",
                    title: "ios-simulator",
                    subtitle: "Start, stop, and manage iOS simulators for testing.",
                    trailingText: "Personal",
                    replacementText: "/ios-simulator",
                    symbolName: "shippingbox"
                )
            ],
            totalMatches: 3,
            highlightedIndex: 0,
            isLoading: false
        )
    }

    var sampleEmptyAutocomplete: ComposerAutocompleteState {
        ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 0..<4,
            query: "zzzz",
            source: nil,
            suggestions: [],
            totalMatches: 0,
            highlightedIndex: 0,
            isLoading: false
        )
    }

    var sampleLoadingAutocomplete: ComposerAutocompleteState {
        ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .skill,
            replacementOffsets: 0..<4,
            query: "tes",
            source: nil,
            suggestions: [],
            totalMatches: 0,
            highlightedIndex: 0,
            isLoading: true
        )
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
                summary: "Grep `retry(`",
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
                summary: "Grep `retry(`",
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
