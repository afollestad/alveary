import XCTest

@testable import Alveary

extension SnapshotTests {
    var sampleSubAgents: [SubAgentEntry] {
        [
            SubAgentEntry(
                id: "agent-search",
                agentType: "search",
                description: "Summarize hook server",
                statusDescription: "Scanning the current chat stack",
                lastToolName: "Read",
                tools: [
                    ToolEntry(
                        id: "agent-hook-read",
                        name: "Read",
                        summary: "Reading `DefaultClaudeHookServer.swift`",
                        input: "{\"file_path\":\"Alveary/Services/Agent/Claude/Hooks/DefaultClaudeHookServer.swift\"}",
                        output: "final class DefaultClaudeHookServer { ... }",
                        stderr: nil,
                        isComplete: true,
                        isInterrupted: false,
                        isImage: false,
                        noOutputExpected: false,
                        isError: false
                    )
                ],
                result: nil,
                isComplete: true,
                toolUseCount: 3,
                totalTokens: 8_200,
                durationMs: 1_400
            ),
            SubAgentEntry(
                id: "agent-tests",
                agentType: "validation",
                description: "Summarize transcript view",
                statusDescription: nil,
                lastToolName: nil,
                tools: [
                    ToolEntry(
                        id: "agent-transcript-grep",
                        name: "Grep",
                        summary: "Searching for pattern `SubAgentBlock`",
                        input: "{\"pattern\":\"SubAgentBlock\",\"path\":\"Alveary/Views/Chat\"}",
                        output: nil,
                        stderr: nil,
                        isComplete: false,
                        isInterrupted: false,
                        isImage: false,
                        noOutputExpected: false,
                        isError: false
                    )
                ],
                result: nil,
                isComplete: false,
                toolUseCount: 5,
                totalTokens: 12_400,
                durationMs: 2_300
            )
        ]
    }

    var sampleSubAgentWithBashTools: SubAgentEntry {
        SubAgentEntry(
            id: "agent-count-swift",
            agentType: "explorer",
            description: "Count swift files",
            statusDescription: nil,
            lastToolName: nil,
            tools: [
                ToolEntry(
                    id: "agent-find-count",
                    name: "Bash",
                    summary: "Executing `find ~/Development/project -name \"*.swift\" -type f | wc -l`",
                    input: "{\"command\":\"find ~/Development/project -name \\\"*.swift\\\" -type f | wc -l\"}",
                    output: nil,
                    stderr: nil,
                    isComplete: false,
                    isInterrupted: false,
                    isImage: false,
                    noOutputExpected: false,
                    isError: false
                )
            ],
            result: nil,
            isComplete: false,
            toolUseCount: 2,
            totalTokens: 2_400,
            durationMs: 900
        )
    }
}
