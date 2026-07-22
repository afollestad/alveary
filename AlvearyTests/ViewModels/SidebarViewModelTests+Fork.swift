import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testForkThreadIntoLocalCreatesThreadCopiesTranscriptAndStartsProviderFork() async throws {
        let setup = try localForkSetup()
        let fixture = setup.fixture
        let thread = setup.thread
        let sourceConversation = try fixture.requireConversation(id: "main")
        try insertForkSourceEvents(in: fixture, conversation: sourceConversation)
        var observedBusyStatusDuringFork = false
        await fixture.agentsManager.setSpawnObserver { _ in
            observedBusyStatusDuringFork = fixture.viewModel.threadStatus(for: thread) == .busy
        }

        let forkedThread = try await fixture.viewModel.forkThreadIntoLocal(thread)

        let forkedConversation = try XCTUnwrap(mainConversation(in: fixture, thread: forkedThread))
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let spawnCall = try XCTUnwrap(spawnCalls.first)

        try assertLocalForkThread(forkedThread, conversation: forkedConversation, spawnCall: spawnCall)
        try assertCopiedForkEvents(in: fixture, conversationID: forkedConversation.id)
        XCTAssertTrue(observedBusyStatusDuringFork)
        XCTAssertEqual(fixture.viewModel.threadStatus(for: thread), .stopped)
    }

    func testForkThreadIntoWorktreeCreatesWorktreeBeforeProviderFork() async throws {
        let sourceHead = "9c9f673d2b98e8e249e189ebd3b6193bff0afce4"
        let setup = try worktreeForkSetup(providerId: .claude, sessionId: "claude-session")
        let fixture = setup.fixture
        let thread = setup.thread
        await fixture.worktreeManager.setCreateInfo(WorktreeInfo(path: "/tmp/new-worktree", branch: "alveary/forked-thread"))
        await fixture.shell.enqueue(.success(ShellResult(
            stdout: "\(sourceHead)\n",
            stderr: "",
            exitCode: 0,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )))

        let forkedThread = try await fixture.viewModel.forkThreadIntoWorktree(thread)

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let spawnCall = try XCTUnwrap(spawnCalls.first)
        let forkRequest = try XCTUnwrap(spawnCall.config.sessionFork)
        let createCalls = await fixture.worktreeManager.createCalls()
        let prepareCalls = await fixture.worktreeManager.prepareForkContextCalls()

        assertForkWorktreePreparation(createCalls: createCalls, prepareCalls: prepareCalls)
        XCTAssertTrue(forkedThread.useWorktree)
        XCTAssertFalse(forkedThread.isPinned)
        XCTAssertEqual(forkedThread.branch, "alveary/forked-thread")
        XCTAssertEqual(forkedThread.worktreePath, "/tmp/new-worktree")
        XCTAssertEqual(spawnCall.config.workingDirectory, "/tmp/new-worktree")
        XCTAssertEqual(forkRequest.sourceSessionId, "claude-session")
        XCTAssertEqual(forkRequest.sourceWorkingDirectory, "/tmp/source-worktree")
        XCTAssertEqual(forkRequest.mode, .worktree)
    }

    func testForkThreadRejectsBusySource() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main", "side"]
        )
        await fixture.agentsManager.setStatus(.busy, for: "side")

        do {
            _ = try await fixture.viewModel.forkThreadIntoLocal(thread)
            XCTFail("Expected busy source fork to fail")
        } catch let error as SidebarViewModelError {
            guard case .threadForkUnavailable(let reason) = error else {
                XCTFail("Expected fork unavailable error")
                return
            }
            XCTAssertTrue(reason.contains("finish"))
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls, [])
    }

    func testForkThreadRejectsUnresolvedApproval() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main", "side"]
        )
        let conversation = try fixture.requireConversation(id: "side")
        fixture.context.insert(ConversationEventRecord(
            id: "approval",
            conversationId: conversation.id,
            type: "tool_approval",
            toolApprovalStatus: ToolApprovalStatus.pending.rawValue,
            conversation: conversation
        ))
        try fixture.context.save()

        do {
            _ = try await fixture.viewModel.forkThreadIntoLocal(thread)
            XCTFail("Expected unresolved approval fork to fail")
        } catch let error as SidebarViewModelError {
            guard case .threadForkUnavailable(let reason) = error else {
                XCTFail("Expected fork unavailable error")
                return
            }
            XCTAssertTrue(reason.contains("pending tool use"))
        }
    }

    func testForkThreadRollsBackThreadAndWorktreeOnProviderBootstrapFailure() async throws {
        let setup = try projectForkSetup(providerId: .codex, sessionId: "codex-thread")
        let fixture = setup.fixture
        let thread = setup.thread
        await fixture.agentsManager.setSpawnError(.spawnFailed("fork failed"))
        await fixture.worktreeManager.setCreateInfo(WorktreeInfo(path: "/tmp/new-worktree", branch: "alveary/forked-thread"))

        do {
            _ = try await fixture.viewModel.forkThreadIntoWorktree(thread)
            XCTFail("Expected provider bootstrap failure")
        } catch let error as SidebarViewModelError {
            guard case .threadForkFailed = error else {
                XCTFail("Expected thread fork failure")
                return
            }
        }

        let threads = try fixture.context.fetch(FetchDescriptor<AgentThread>())
        let removeCalls = await fixture.worktreeManager.removeCalls()
        let actions = await fixture.providerSessionActions.actions

        XCTAssertEqual(threads.map(\.name), ["Thread"])
        XCTAssertEqual(removeCalls, [
            .init(projectPath: "/tmp/alveary-project", worktreePath: "/tmp/new-worktree", branch: "alveary/forked-thread")
        ])
        guard case .delete(let deleteSnapshot) = actions.last else {
            XCTFail("Expected rollback to request provider deletion")
            return
        }
        XCTAssertEqual(deleteSnapshot.providerIDs, ["codex"])
        XCTAssertEqual(deleteSnapshot.workingDirectory, URL(fileURLWithPath: "/tmp/new-worktree", isDirectory: true))
        XCTAssertEqual(deleteSnapshot.conversationIDs.count, 1)
    }

    func testForkThreadCleansUpWorktreeWhenContextPreparationFails() async throws {
        let setup = try projectForkSetup(providerId: .codex, sessionId: "codex-thread")
        let fixture = setup.fixture
        let thread = setup.thread
        await fixture.worktreeManager.setCreateInfo(WorktreeInfo(path: "/tmp/new-worktree", branch: "alveary/forked-thread"))
        await fixture.worktreeManager.setPrepareForkContextError(.prepareForkContextFailed)

        do {
            _ = try await fixture.viewModel.forkThreadIntoWorktree(thread)
            XCTFail("Expected worktree context preparation failure")
        } catch let error as SidebarMockWorktreeManager.MockError {
            XCTAssertEqual(error, .prepareForkContextFailed)
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let removeCalls = await fixture.worktreeManager.removeCalls()

        XCTAssertEqual(spawnCalls, [])
        XCTAssertEqual(removeCalls, [
            .init(projectPath: "/tmp/alveary-project", worktreePath: "/tmp/new-worktree", branch: "alveary/forked-thread")
        ])
    }
}

@MainActor
private func localForkSetup() throws -> ForkTestSetup {
    let sourceRecord = forkProviderSessionRecord(
        conversationId: "main",
        providerId: .codex,
        sessionId: "codex-thread",
        workingDirectory: "/tmp/alveary-project"
    )
    let fixture = try SidebarTestFixture(
        providerSessionActions: RecordingProviderSessionActionService(
            resolvedRecordsByConversationID: ["main": [sourceRecord]]
        )
    )
    let thread = try fixture.insertThread(
        projectName: "Alveary",
        projectPath: "/tmp/alveary-project",
        conversationIDs: ["main"],
        provider: "codex",
        providerSessionId: "codex-thread",
        providerSessionProviderId: "codex",
        providerSessionWorkingDirectory: "/tmp/alveary-project"
    )
    return ForkTestSetup(fixture: fixture, thread: thread)
}

@MainActor
private func worktreeForkSetup(
    providerId: AgentCLIKit.AgentProviderID,
    sessionId: AgentCLIKit.AgentSessionID
) throws -> ForkTestSetup {
    let setup = try projectForkSetup(
        providerId: providerId,
        sessionId: sessionId,
        sourceWorktreePath: "/tmp/source-worktree",
        threadName: "Source Thread"
    )
    setup.thread.branch = "source-branch"
    setup.thread.hasCompletedInitialSetup = true
    setup.thread.useWorktree = true
    try setup.fixture.context.save()
    return setup
}

@MainActor
func projectForkSetup(
    providerId: AgentCLIKit.AgentProviderID,
    sessionId: AgentCLIKit.AgentSessionID,
    sourceWorktreePath: String? = nil,
    threadName: String = "Thread"
) throws -> ForkTestSetup {
    let workingDirectory = sourceWorktreePath ?? "/tmp/alveary-project"
    let sourceRecord = forkProviderSessionRecord(
        conversationId: "main",
        providerId: providerId,
        sessionId: sessionId,
        workingDirectory: workingDirectory
    )
    let fixture = try SidebarTestFixture(
        providerSessionActions: RecordingProviderSessionActionService(
            resolvedRecordsByConversationID: ["main": [sourceRecord]]
        )
    )
    let project = Project(path: "/tmp/alveary-project", name: "Alveary", remoteName: "origin", baseRef: "main")
    let thread = AgentThread(name: threadName, worktreePath: sourceWorktreePath, project: project)
    thread.conversations = [
        Conversation(
            id: "main",
            title: threadName,
            provider: providerId.rawValue,
            providerSessionId: sessionId.rawValue,
            providerSessionProviderId: providerId.rawValue,
            providerSessionWorkingDirectory: workingDirectory,
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
    ]
    project.threads = [thread]
    fixture.context.insert(project)
    try fixture.context.save()
    return ForkTestSetup(fixture: fixture, thread: thread)
}

private func assertLocalForkThread(
    _ forkedThread: AgentThread,
    conversation: Conversation,
    spawnCall: SidebarMockAgentsManager.SpawnCall
) throws {
    let forkRequest = try XCTUnwrap(spawnCall.config.sessionFork)
    XCTAssertEqual(forkedThread.name, "Thread")
    XCTAssertFalse(forkedThread.hasCustomName)
    XCTAssertFalse(forkedThread.useWorktree)
    XCTAssertFalse(forkedThread.isPinned)
    XCTAssertTrue(forkedThread.hasCompletedInitialSetup)
    XCTAssertFalse(forkedThread.isForkBootstrapPending)
    XCTAssertEqual(conversation.title, "Thread")
    XCTAssertEqual(conversation.provider, "codex")
    XCTAssertEqual(spawnCall.id, conversation.id)
    XCTAssertEqual(spawnCall.config.workingDirectory, "/tmp/alveary-project")
    XCTAssertEqual(spawnCall.config.initialPrompt, nil)
    XCTAssertEqual(spawnCall.config.reasoningSummaryMode, .concise)
    XCTAssertEqual(
        spawnCall.config.hostTools.map(\.name),
        [ScheduledTaskHostToolCatalog.listToolName, ScheduledTaskHostToolCatalog.proposeToolName]
    )
    XCTAssertEqual(forkRequest.sourceSessionId, "codex-thread")
    XCTAssertEqual(forkRequest.sourceWorkingDirectory, "/tmp/alveary-project")
    XCTAssertEqual(forkRequest.mode, .local)
}

@MainActor
private func assertCopiedForkEvents(in fixture: SidebarTestFixture, conversationID: String) throws {
    let copiedEvents = try events(in: fixture, conversationID: conversationID)
    XCTAssertEqual(copiedEvents.map(\.type), [
        "message",
        "tokens",
        "tool_approval",
        ConversationEventRecord.taskListType,
        "stop"
    ])
    XCTAssertEqual(copiedEvents.last?.content, ConversationSessionFork.displayMessage)
    XCTAssertFalse(copiedEvents.contains { $0.type == "session_init" })
    XCTAssertFalse(copiedEvents.contains { $0.type == ConversationEventRecord.contextWindowInvalidatedType })
    XCTAssertEqual(copiedEvents.filter { ConversationSessionFork.isDisplayMessage($0.content) }.count, 1)
    XCTAssertEqual(copiedEvents.first(where: { $0.type == "tool_approval" })?.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
    XCTAssertEqual(copiedEvents.first(where: { $0.type == "tokens" })?.costUsd, 0)
    XCTAssertEqual(copiedEvents.first(where: { $0.type == "tokens" })?.costUsdReported, false)
    XCTAssertEqual(
        copiedEvents.first(where: { $0.type == "message" })?.persistedFileAttachments,
        [forkSourceFileAttachment()]
    )
}

private func assertForkWorktreePreparation(
    createCalls: [SidebarMockWorktreeManager.CreateCall],
    prepareCalls: [SidebarMockWorktreeManager.PrepareForkContextCall]
) {
    XCTAssertEqual(createCalls, [
        .init(
            projectPath: "/tmp/alveary-project",
            threadName: "Source Thread",
            baseRef: "9c9f673d2b98e8e249e189ebd3b6193bff0afce4",
            remoteName: nil
        )
    ])
    XCTAssertEqual(prepareCalls, [
        .init(sourcePath: "/tmp/source-worktree", worktreePath: "/tmp/new-worktree")
    ])
}

@MainActor
private func insertForkSourceEvents(in fixture: SidebarTestFixture, conversation: Conversation) throws {
    let events = [
        forkSourceEvent(id: "init", type: "session_init", conversation: conversation),
        forkSourceMessage(conversation: conversation),
        forkSourceTokens(conversation: conversation),
        forkSourceApproval(conversation: conversation),
        forkSourceEvent(id: "context-window", type: ConversationEventRecord.contextWindowInvalidatedType, conversation: conversation),
        forkSourceEvent(id: "old-fork-note", type: "stop", content: ConversationSessionFork.displayMessage, conversation: conversation),
        forkSourceEvent(id: "task-list", type: ConversationEventRecord.taskListType, content: "[]", conversation: conversation)
    ]
    for (index, event) in events.enumerated() {
        event.timestamp = Date(timeIntervalSince1970: Double(index))
        fixture.context.insert(event)
    }
    try fixture.context.save()
}

private func forkSourceEvent(
    id: String,
    type: String,
    content: String? = nil,
    conversation: Conversation
) -> ConversationEventRecord {
    ConversationEventRecord(id: id, conversationId: conversation.id, type: type, content: content, conversation: conversation)
}

private func forkSourceMessage(conversation: Conversation) -> ConversationEventRecord {
    let record = ConversationEventRecord(
        id: "message",
        conversationId: conversation.id,
        type: "message",
        role: "user",
        content: "Keep this context",
        conversation: conversation
    )
    record.setPersistedTranscriptAttachments(images: [], appShots: [], files: [forkSourceFileAttachment()])
    return record
}

private func forkSourceFileAttachment() -> LocalFileAttachment {
    LocalFileAttachment(
        id: "fork-source-file",
        fileURL: URL(fileURLWithPath: "/tmp/fork-source-file.pdf"),
        label: "fork-source-file.pdf",
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

private func forkSourceTokens(conversation: Conversation) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "tokens",
        conversationId: conversation.id,
        type: "tokens",
        tokenInput: 10,
        tokenOutput: 2,
        costUsd: 0.42,
        costUsdReported: true,
        conversation: conversation
    )
}

private func forkSourceApproval(conversation: Conversation) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "approval",
        conversationId: conversation.id,
        type: "tool_approval",
        toolApprovalStatus: ToolApprovalStatus.approved.rawValue,
        conversation: conversation
    )
}

@MainActor
private func mainConversation(in fixture: SidebarTestFixture, thread: AgentThread) throws -> Conversation? {
    let threadID = thread.persistentModelID
    let descriptor = FetchDescriptor<Conversation>(
        predicate: #Predicate { conversation in
            conversation.thread?.persistentModelID == threadID && conversation.isMain
        }
    )
    return try fixture.context.fetch(descriptor).first
}

@MainActor
private func events(in fixture: SidebarTestFixture, conversationID: String) throws -> [ConversationEventRecord] {
    let descriptor = FetchDescriptor<ConversationEventRecord>(
        predicate: #Predicate { record in
            record.conversationId == conversationID
        }
    )
    return try fixture.context.fetch(descriptor).sorted { lhs, rhs in
        if lhs.timestamp == rhs.timestamp {
            return lhs.id < rhs.id
        }
        return lhs.timestamp < rhs.timestamp
    }
}

private func forkProviderSessionRecord(
    conversationId: AgentCLIKit.AgentConversationID,
    providerId: AgentCLIKit.AgentProviderID,
    sessionId: AgentCLIKit.AgentSessionID,
    workingDirectory: String
) -> AgentCLIKit.AgentSessionRecord {
    AgentCLIKit.AgentSessionRecord(
        conversationId: conversationId,
        providerId: providerId,
        providerSessionId: sessionId,
        workingDirectory: URL(fileURLWithPath: workingDirectory, isDirectory: true),
        generation: 0,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

struct ForkTestSetup {
    let fixture: SidebarTestFixture
    let thread: AgentThread
}
