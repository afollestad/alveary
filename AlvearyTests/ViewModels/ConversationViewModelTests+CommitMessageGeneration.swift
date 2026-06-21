import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testGenerateCommitMessageSendsHiddenPromptAndReturnsTrimmedOutput() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let task = Task { try await fixture.viewModel.generateCommitMessage("Generate commit") }

        try await waitUntil("hidden commit prompt sent") {
            await fixture.agentsManager.sentMessages() == ["Generate commit"]
        }

        let sendVisibilities = await fixture.agentsManager.sendVisibilities()
        XCTAssertEqual(sendVisibilities, [.hidden])

        fixture.viewModel.handleEvent(.messageChunk(text: "  Add modal\n\n", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.messageChunk(
            text: "Co-authored-by: Codex <noreply@openai.com>\n  ",
            parentToolUseId: nil
        ))
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))

        let message = try await task.value

        XCTAssertEqual(message, "Add modal\n\nCo-authored-by: Codex <noreply@openai.com>")
        XCTAssertFalse(fixture.viewModel.state.isGeneratingCommitMessage)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
    }

    func testGenerateCommitMessageInitializesFreshThreadWithoutVisibleTranscriptRows() async throws {
        let recorder = RecordingThreadActivityRecorder()
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            threadActivityRecorder: recorder
        )
        let task = Task { try await fixture.viewModel.generateCommitMessage("Generate commit") }

        try await waitUntil("hidden commit prompt sent") {
            await fixture.agentsManager.sentMessages() == ["Generate commit"]
        }

        let refreshedThread = try fixture.dbThread()
        XCTAssertTrue(refreshedThread.hasCompletedInitialSetup)
        XCTAssertNil(refreshedThread.worktreePath)
        XCTAssertNil(refreshedThread.branch)
        XCTAssertTrue(recorder.visibleOutboundConversationIDs.isEmpty)

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertEqual(spawnCalls.first?.config.workingDirectory, fixture.project.path)
        XCTAssertNil(spawnCalls.first?.config.initialPrompt)

        let sendVisibilities = await fixture.agentsManager.sendVisibilities()
        XCTAssertEqual(sendVisibilities, [.hidden])

        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Add modal", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))

        let message = try await task.value
        XCTAssertEqual(message, "Add modal")
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
    }

    func testGenerateCommitMessageFreshWorktreeUsesThreadNameForSetup() async throws {
        let worktreeInfo = WorktreeInfo(path: "/tmp/alveary-worktree", branch: "alveary/commit-thread")
        let fixture = try ConversationViewModelTestFixture(
            threadName: "Commit Thread",
            useWorktree: true,
            hasCompletedInitialSetup: false,
            worktreeInfo: worktreeInfo
        )
        let task = Task { try await fixture.viewModel.generateCommitMessage("Generate commit") }

        try await waitUntil("hidden commit prompt sent") {
            await fixture.agentsManager.sentMessages() == ["Generate commit"]
        }

        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertEqual(createCalls.count, 1)
        XCTAssertEqual(createCalls.first?.projectPath, fixture.project.path)
        XCTAssertEqual(createCalls.first?.threadName, "Commit Thread")
        XCTAssertEqual(createCalls.first?.remoteName, fixture.project.remoteName)

        let refreshedThread = try fixture.dbThread()
        XCTAssertEqual(refreshedThread.worktreePath, worktreeInfo.path)
        XCTAssertEqual(refreshedThread.branch, worktreeInfo.branch)
        XCTAssertTrue(refreshedThread.hasCompletedInitialSetup)

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertEqual(spawnCalls.first?.config.workingDirectory, worktreeInfo.path)
        XCTAssertNil(spawnCalls.first?.config.initialPrompt)

        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Add modal", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))

        _ = try await task.value
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
    }

    func testGenerateCommitMessageEmptyResponseFails() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let task = Task { try await fixture.viewModel.generateCommitMessage("Generate commit") }

        try await waitUntil("hidden commit prompt sent") {
            await fixture.agentsManager.sentMessages() == ["Generate commit"]
        }

        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))

        do {
            _ = try await task.value
            XCTFail("Expected empty commit message generation to fail")
        } catch CommitMessageGenerationError.emptyResponse {
            XCTAssertFalse(fixture.viewModel.state.isGeneratingCommitMessage)
        }
    }

    func testGenerateCommitMessageApprovalRequestFails() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let task = Task { try await fixture.viewModel.generateCommitMessage("Generate commit") }

        try await waitUntil("hidden commit prompt sent") {
            await fixture.agentsManager.sentMessages() == ["Generate commit"]
        }

        fixture.viewModel.handleEvent(.toolApprovalRequested(ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{}"
        )))

        do {
            _ = try await task.value
            XCTFail("Expected approval request to fail commit message generation")
        } catch CommitMessageGenerationError.approvalRequested {
            XCTAssertFalse(fixture.viewModel.state.isGeneratingCommitMessage)
        }
    }

    func testGenerateCommitMessageRuntimeErrorFails() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let task = Task { try await fixture.viewModel.generateCommitMessage("Generate commit") }

        try await waitUntil("hidden commit prompt sent") {
            await fixture.agentsManager.sentMessages() == ["Generate commit"]
        }

        fixture.viewModel.handleEvent(.error(message: "Runtime failed"))

        do {
            _ = try await task.value
            XCTFail("Expected runtime error to fail commit message generation")
        } catch CommitMessageGenerationError.failed(let message) {
            XCTAssertEqual(message, "Runtime failed")
            XCTAssertFalse(fixture.viewModel.state.isGeneratingCommitMessage)
        }
    }

    func testGenerateCommitMessageDoesNotPersistVisibleTranscriptRows() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let task = Task { try await fixture.viewModel.generateCommitMessage("Generate commit") }

        try await waitUntil("hidden commit prompt sent") {
            await fixture.agentsManager.sentMessages() == ["Generate commit"]
        }

        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Add modal", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))

        _ = try await task.value

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(fixture.viewModel.state.grouper.items.isEmpty)
        XCTAssertNil(fixture.viewModel.streamingText)
    }

    func testGenerateCommitMessageDropsLateTerminalEventsAfterCompletion() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let task = Task { try await fixture.viewModel.generateCommitMessage("Generate commit") }

        try await waitUntil("hidden commit prompt sent") {
            await fixture.agentsManager.sentMessages() == ["Generate commit"]
        }

        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Add modal", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))

        _ = try await task.value

        fixture.viewModel.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            cacheCreation: 0,
            isError: false,
            stopReason: "stop",
            durationMs: 1,
            costUsd: nil,
            contextWindowSize: nil,
            permissionDenials: [],
            isTerminal: true
        ))

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(fixture.viewModel.state.grouper.items.isEmpty)
    }
}
