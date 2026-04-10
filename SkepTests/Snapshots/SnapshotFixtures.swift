import XCTest

@testable import Skep

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
                    id: "Skep/Views/Input/ChatInputAutocomplete.swift",
                    title: "ChatInputAutocomplete.swift",
                    subtitle: "Skep/Views/Input",
                    replacementText: "@Skep/Views/Input/ChatInputAutocomplete.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "Skep/Views/Chat/ChatSupplementaryViews.swift",
                    title: "ChatSupplementaryViews.swift",
                    subtitle: "Skep/Views/Chat",
                    replacementText: "@Skep/Views/Chat/ChatSupplementaryViews.swift",
                    symbolName: "doc.text"
                ),
                ComposerAutocompleteSuggestion(
                    id: "SkepTests/Snapshots/SnapshotTestSupport.swift",
                    title: "SnapshotTestSupport.swift",
                    subtitle: "SkepTests/Snapshots",
                    replacementText: "@SkepTests/Snapshots/SnapshotTestSupport.swift",
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
                isInterrupted: false,
                isImage: false,
                noOutputExpected: false,
                isError: false
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

actor SnapshotSkillsService: SkillsService {
    func loadInstalled() async throws -> [Skill] {
        [
            Skill(
                id: "skill-ios-accessibility",
                name: "ios-accessibility",
                description: "Audit SwiftUI screens for VoiceOver and Dynamic Type issues.",
                version: "1.4.0",
                source: .local,
                isInstalled: true,
                syncedAgentIDs: ["claude"],
                owner: "squareup",
                repo: "agents",
                sourceUrl: "https://example.com/ios-accessibility",
                installs: nil
            )
        ]
    }

    func loadCatalog() async throws -> [Skill] {
        [
            Skill(
                id: "skill-walkthrough",
                name: "walkthrough",
                description: "Explain architecture and visualize code paths for a feature area.",
                version: "2.0.1",
                source: .catalog,
                isInstalled: false,
                syncedAgentIDs: [],
                owner: "squareup",
                repo: "agents",
                sourceUrl: "https://example.com/walkthrough",
                installs: 1_284
            )
        ]
    }

    func searchSkillsSh(query: String) async throws -> [Skill] {
        [
            Skill(
                id: "skill-ui-snapshots",
                name: "ui-snapshots",
                description: "Generate snapshot tests for macOS SwiftUI screens.",
                version: "0.9.0",
                source: .skillsSh,
                isInstalled: false,
                syncedAgentIDs: [],
                owner: "community",
                repo: "skills",
                sourceUrl: "https://example.com/ui-snapshots",
                installs: 312
            )
        ]
    }

    func fetchSkillMd(skill: Skill) async throws -> String {
        "# \(skill.name)\n\n\(skill.description)"
    }

    func install(_ skill: Skill) async throws {}

    func uninstall(_ skill: Skill) async throws {}

    func create(name: String, description: String, instructions: String) async throws {}

    func refreshCatalog() async throws -> [Skill] {
        try await loadCatalog()
    }
}

@MainActor
final class SnapshotMCPService: MCPService {
    func loadAll() async throws -> [MCPServer] {
        [
            MCPServer(
                name: "context7",
                transport: .http,
                command: nil,
                args: nil,
                url: "https://mcp.context7.com/mcp",
                headers: ["Authorization": "Bearer ***"],
                env: nil,
                providers: ["claude"]
            )
        ]
    }

    func loadRecommended() async throws -> [RecommendedMCPServer] {
        [
            RecommendedMCPServer(
                template: MCPServer(
                    name: "playwright",
                    transport: .stdio,
                    command: "npx",
                    args: ["-y", "@anthropic/mcp-playwright"],
                    url: nil,
                    headers: nil,
                    env: ["PLAYWRIGHT_BROWSERS_PATH": "0"],
                    providers: []
                ),
                description: "Browser automation for UI validation and screenshot capture.",
                headerPrompts: ["PLAYWRIGHT_TOKEN"]
            )
        ]
    }

    func addServer(_ server: MCPServer, for agents: [String]) async throws {}

    func removeServer(_ server: MCPServer) async throws {}

    func availableAgents() async -> [MCPAgentAvailability] {
        [
            MCPAgentAvailability(agentId: "claude", name: "Claude Code", supportedTransports: [.stdio, .http]),
            MCPAgentAvailability(agentId: "amp", name: "Amp", supportedTransports: [.http])
        ]
    }
}

@MainActor
struct SnapshotDiffViewerFixture {
    let directory = "/tmp/skep-snapshot-project"
    let gitService: SnapshotMockGitService
    let gitHubService: SnapshotMockGitHubService
    let fileListManager: SnapshotMockFileListManager
    let agentsManager: SnapshotMockAgentsManager
    let viewModel: DiffViewerViewModel

    init(
        gitService: SnapshotMockGitService,
        gitHubService: SnapshotMockGitHubService = SnapshotMockGitHubService(),
        fileListManager: SnapshotMockFileListManager = SnapshotMockFileListManager(),
        agentsManager: SnapshotMockAgentsManager = SnapshotMockAgentsManager()
    ) {
        self.gitService = gitService
        self.gitHubService = gitHubService
        self.fileListManager = fileListManager
        self.agentsManager = agentsManager
        viewModel = DiffViewerViewModel(
            gitService: gitService,
            gitHubService: gitHubService,
            fileListManager: fileListManager,
            agentsManager: agentsManager,
            fsEventDebounceDuration: .seconds(10),
            idlePollInterval: .seconds(10)
        )
    }
}

actor SnapshotMockGitService: GitService {
    private var statusResults: [[FileStatus]]
    private var diffResults: [String]

    init(statusResults: [[FileStatus]], diffResults: [String]) {
        self.statusResults = statusResults
        self.diffResults = diffResults
    }

    func status(in directory: String) async throws -> [FileStatus] {
        if statusResults.isEmpty {
            return []
        }
        return statusResults.removeFirst()
    }

    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String {
        if diffResults.isEmpty {
            return ""
        }
        return diffResults.removeFirst()
    }

    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String {
        ""
    }

    func stage(paths: [String], in directory: String) async throws {}

    func unstage(paths: [String], in directory: String) async throws {}

    func discard(paths: [String], in directory: String) async throws {}

    func log(in directory: String, limit: Int) async throws -> [CommitInfo] {
        []
    }

    func currentBranch(in directory: String) async throws -> String {
        "feature/chat-input"
    }

    func listFiles(in directory: String) async throws -> [String] {
        []
    }

    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int {
        0
    }
}

@MainActor
final class SnapshotMockGitHubService: GitHubService, @unchecked Sendable {
    func listPRs(in directory: String) async throws -> [PRInfo] {
        []
    }

    func checkRunStatus(prNumber: Int, in directory: String) async throws -> CIStatus {
        .none
    }

    func checkoutPRBranch(prNumber: Int, branchName: String, in directory: String) async throws {}
}

actor SnapshotMockFileListManager: FileListManager {
    func files(for projectPath: String) async -> [String] {
        []
    }

    func invalidateCache(for projectPath: String) {}

    func warmCache(for projectPath: String) async {}
}

actor SnapshotMockAgentsManager: AgentsManager {
    nonisolated func status(for conversationId: String) -> ActivitySignal {
        .neutral
    }

    nonisolated var allStatuses: [String: ActivitySignal] {
        [:]
    }

    nonisolated func beginShutdown() {}

    nonisolated var allProcessesSnapshot: [Process] {
        []
    }

    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws {}

    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription? {
        nil
    }

    func sendMessage(_ message: String, conversationId: String) async throws {}

    func cancelTurn(conversationId: String) {}

    func destroyRuntime(conversationId: String) async throws {}

    func kill(conversationId: String) {}

    func killAll() {}

    func isRunning(conversationId: String) -> Bool {
        false
    }

    func hasTrackedProcess(conversationId: String) -> Bool {
        false
    }

    func hasInflightLifecycle(conversationId: String) -> Bool {
        false
    }

    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws {}

    func markPersisted(conversationId: String, generation: UUID, upTo index: Int) {}
}
