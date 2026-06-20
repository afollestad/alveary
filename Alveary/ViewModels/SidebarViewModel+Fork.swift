import AgentCLIKit
import Foundation
import SwiftData

extension SidebarViewModel {
    func forkThreadIntoLocal(_ thread: AgentThread) async throws -> AgentThread {
        try await forkThread(thread, mode: .local)
    }

    func forkThreadIntoWorktree(_ thread: AgentThread) async throws -> AgentThread {
        try await forkThread(thread, mode: .worktree)
    }

    func forkThread(_ thread: AgentThread, mode: SidebarThreadForkMode) async throws -> AgentThread {
        let source = try makeThreadForkSourceSnapshot(thread, mode: mode)
        try assertForkSourceIsSafe(source)
        beginForkActivity(source.threadID)
        defer { endForkActivity(source.threadID) }

        let sourceRecord = try await resolveForkSourceRecord(source)
        let worktree = try await createForkWorktreeIfNeeded(source)
        let target = try insertForkTarget(source: source, sourceRecord: sourceRecord, worktree: worktree)

        do {
            try await agentsManager.spawn(
                id: target.conversationID,
                config: target.spawnConfig
            )
        } catch {
            try await rollbackFailedFork(target: target, originalError: error)
            throw SidebarViewModelError.threadForkFailed(error)
        }

        guard let dbThread = modelContext.resolveThread(id: target.threadID) else {
            throw SidebarViewModelError.threadMissing
        }
        return dbThread
    }
}

private extension SidebarViewModel {
    func makeThreadForkSourceSnapshot(
        _ thread: AgentThread,
        mode: SidebarThreadForkMode
    ) throws -> ThreadForkSourceSnapshot {
        let dbThread = try requireThread(thread)
        guard let project = dbThread.project else {
            throw SidebarViewModelError.threadMissingParentProject
        }
        guard let sourceConversation = mainConversation(for: dbThread) else {
            throw SidebarViewModelError.threadForkUnavailable("Thread has no main conversation to fork")
        }

        let projectPath = project.path
        let sourceWorkingDirectory = dbThread.worktreePath ?? projectPath
        let sourceProviderID = sourceConversation.provider
            ?? sourceConversation.providerSessionProviderId
            ?? settingsService.current.defaultProvider

        return ThreadForkSourceSnapshot(
            threadID: dbThread.persistentModelID,
            projectID: project.persistentModelID,
            projectPath: projectPath,
            projectBaseRef: project.baseRef,
            projectRemoteName: project.remoteName,
            isGitRepository: project.isGitRepository,
            sourceConversationID: sourceConversation.id,
            sourceProviderID: sourceProviderID,
            sourceProviderSessionID: sourceConversation.providerSessionId,
            sourceProviderSessionProviderID: sourceConversation.providerSessionProviderId,
            sourceProviderSessionWorkingDirectory: sourceConversation.providerSessionWorkingDirectory,
            sourceWorkingDirectory: sourceWorkingDirectory,
            threadConversationIDs: conversationIDs(for: dbThread),
            threadName: dbThread.displayName(),
            permissionMode: dbThread.permissionMode,
            planModeEnabled: dbThread.planModeEnabled ?? false,
            effort: dbThread.effort,
            model: dbThread.model,
            speedMode: dbThread.normalizedSpeedMode,
            mode: mode
        )
    }

    func assertForkSourceIsSafe(_ source: ThreadForkSourceSnapshot) throws {
        guard !activeForkSourceThreadIDs.contains(source.threadID) else {
            throw SidebarViewModelError.threadForkUnavailable("Wait for the source thread fork to finish")
        }

        for conversationID in source.conversationIDs {
            let status = agentsManager.status(for: conversationID)
            guard status != .busy else {
                throw SidebarViewModelError.threadForkUnavailable("Wait for the source thread to finish before forking it")
            }
            guard status != .waitingForUser else {
                throw SidebarViewModelError.threadForkUnavailable("Resolve the source thread's pending prompt before forking it")
            }
        }

        guard !sourceHasUnresolvedApproval(source) else {
            throw SidebarViewModelError.threadForkUnavailable("Approve or deny the source thread's pending tool use before forking it")
        }
    }

    func sourceHasUnresolvedApproval(_ source: ThreadForkSourceSnapshot) -> Bool {
        let descriptor = FetchDescriptor<ConversationEventRecord>(
            predicate: #Predicate { record in
                record.type == "tool_approval"
            }
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        let sourceConversationIDs = Set(source.conversationIDs)
        return records.contains { record in
            guard sourceConversationIDs.contains(record.conversationId) else {
                return false
            }
            guard let status = record.toolApprovalStatus.flatMap(ToolApprovalStatus.init(rawValue:)) else {
                return true
            }
            switch status {
            case .pending, .approving, .denying, .approvingForSessionExact, .approvingForSessionGroup:
                return true
            case .approved, .approvedForSessionExact, .approvedForSessionGroup, .denied, .superseded:
                return false
            }
        }
    }

    func resolveForkSourceRecord(
        _ source: ThreadForkSourceSnapshot
    ) async throws -> AgentCLIKit.AgentSessionRecord {
        let resolution = await providerSessionActionService.resolveSessions(matching: source.providerSessionActionSnapshot)
        if let matchingRecord = resolution.records.first(where: { $0.conversationId.rawValue == source.sourceConversationID }) {
            return matchingRecord
        }
        if let firstRecord = resolution.records.first {
            return firstRecord
        }
        throw SidebarViewModelError.threadForkUnavailable("Thread has no provider session binding to fork")
    }

    func createForkWorktreeIfNeeded(_ source: ThreadForkSourceSnapshot) async throws -> ForkCreatedWorktree? {
        guard source.mode == .worktree else {
            return nil
        }
        guard source.isGitRepository else {
            throw SidebarViewModelError.threadForkUnavailable("Fork into worktree requires a Git-backed project")
        }

        let worktreeBase = await forkWorktreeBase(source)
        let info = try await worktreeManager.create(
            projectPath: source.projectPath,
            threadName: source.threadName,
            baseRef: worktreeBase.baseRef,
            remoteName: worktreeBase.remoteName
        )

        do {
            try await worktreeManager.prepareForkContext(
                sourcePath: source.sourceWorkingDirectory,
                worktreePath: info.path
            )
        } catch {
            try? await worktreeManager.remove(
                projectPath: source.projectPath,
                worktreePath: info.path,
                branch: info.branch
            )
            throw error
        }

        let expectedStatus = await gitStatusSnapshot(in: info.path)
        return ForkCreatedWorktree(info: info, expectedStatus: expectedStatus)
    }

    func forkWorktreeBase(_ source: ThreadForkSourceSnapshot) async -> ForkWorktreeBase {
        let result = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["rev-parse", "--verify", "HEAD"],
            in: source.sourceWorkingDirectory
        )
        guard result?.succeeded == true else {
            return ForkWorktreeBase(baseRef: source.projectBaseRef, remoteName: source.projectRemoteName)
        }

        let sourceHead = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sourceHead.isEmpty else {
            return ForkWorktreeBase(baseRef: source.projectBaseRef, remoteName: source.projectRemoteName)
        }
        return ForkWorktreeBase(baseRef: sourceHead, remoteName: nil)
    }

    func beginForkActivity(_ threadID: PersistentIdentifier) {
        activeForkSourceThreadIDs.insert(threadID)
        statusVersion += 1
    }

    func endForkActivity(_ threadID: PersistentIdentifier) {
        activeForkSourceThreadIDs.remove(threadID)
        statusVersion += 1
    }

    func insertForkTarget(
        source: ThreadForkSourceSnapshot,
        sourceRecord: AgentCLIKit.AgentSessionRecord,
        worktree: ForkCreatedWorktree?
    ) throws -> ThreadForkTargetSnapshot {
        guard let dbProject = modelContext.resolveProject(id: source.projectID) else {
            throw SidebarViewModelError.projectMissing
        }

        let thread = makeForkThread(source: source, worktree: worktree, project: dbProject)
        let conversation = makeForkConversation(source: source, sourceRecord: sourceRecord, thread: thread)

        thread.conversations = [conversation]
        modelContext.insert(thread)
        modelContext.insert(conversation)
        try copyForkTranscript(
            fromConversationID: source.sourceConversationID,
            to: conversation
        )
        try modelContext.save()

        let config = makeForkSpawnConfig(source: source, sourceRecord: sourceRecord, worktree: worktree)
        return ThreadForkTargetSnapshot(
            threadID: thread.persistentModelID,
            conversationID: conversation.id,
            projectPath: source.projectPath,
            worktree: worktree,
            spawnConfig: config
        )
    }

    func makeForkThread(
        source: ThreadForkSourceSnapshot,
        worktree: ForkCreatedWorktree?,
        project: Project
    ) -> AgentThread {
        AgentThread(
            name: source.threadName,
            hasCustomName: false,
            branch: worktree?.info.branch,
            worktreePath: worktree?.info.path,
            hasCompletedInitialSetup: true,
            permissionMode: source.permissionMode,
            planModeEnabled: source.planModeEnabled,
            effort: source.effort,
            model: source.model,
            speedMode: source.speedMode.rawValue,
            useWorktree: worktree != nil,
            modifiedAt: Date(),
            project: project
        )
    }

    func makeForkConversation(
        source: ThreadForkSourceSnapshot,
        sourceRecord: AgentCLIKit.AgentSessionRecord,
        thread: AgentThread
    ) -> Conversation {
        Conversation(
            title: Conversation.persistedTitle(
                from: source.threadName,
                fallbackName: AgentThread.untitledName,
                hasCustomTitle: false
            ),
            provider: sourceRecord.providerId.rawValue,
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
    }

    func makeForkSpawnConfig(
        source: ThreadForkSourceSnapshot,
        sourceRecord: AgentCLIKit.AgentSessionRecord,
        worktree: ForkCreatedWorktree?
    ) -> AgentSpawnConfig {
        AgentSpawnConfig(
            providerId: sourceRecord.providerId.rawValue,
            workingDirectory: worktree?.info.path ?? source.projectPath,
            permissionMode: source.permissionMode,
            planModeEnabled: source.planModeEnabled,
            model: source.model,
            effort: source.effort,
            speedMode: source.speedMode,
            sessionFork: AgentSessionForkRequest(
                sourceSessionId: sourceRecord.providerSessionId.rawValue,
                sourceWorkingDirectory: sourceRecord.workingDirectory?.path ?? source.sourceWorkingDirectory,
                mode: source.mode.sessionForkMode
            ),
            initialPrompt: nil
        )
    }

    func copyForkTranscript(
        fromConversationID sourceConversationID: String,
        to targetConversation: Conversation
    ) throws {
        let descriptor = FetchDescriptor<ConversationEventRecord>(
            predicate: #Predicate { record in
                record.conversationId == sourceConversationID
            }
        )
        let sourceRecords = try modelContext.fetch(descriptor).sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id < rhs.id
            }
            return lhs.timestamp < rhs.timestamp
        }

        let baseDate = Date()
        var copiedVisibleIndex = 0
        for record in sourceRecords where shouldCopyForkTranscriptRecord(record) {
            let copiedRecord = forkCopy(of: record, to: targetConversation)
            copiedRecord.timestamp = baseDate.addingTimeInterval(Double(copiedVisibleIndex) * 0.001)
            copiedVisibleIndex += 1
            modelContext.insert(copiedRecord)
        }

        let note = ConversationEventRecord(
            id: "session-forked-\(targetConversation.id)",
            conversationId: targetConversation.id,
            type: "stop",
            content: ConversationSessionFork.displayMessage,
            timestamp: baseDate.addingTimeInterval(Double(copiedVisibleIndex) * 0.001),
            conversation: targetConversation
        )
        modelContext.insert(note)
    }

    func shouldCopyForkTranscriptRecord(_ record: ConversationEventRecord) -> Bool {
        switch record.type {
        case "session_init", ConversationEventRecord.contextWindowInvalidatedType:
            return false
        case "stop" where ConversationSessionFork.isDisplayMessage(record.content):
            return false
        default:
            return true
        }
    }

    func forkCopy(
        of record: ConversationEventRecord,
        to targetConversation: Conversation
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: "fork-\(targetConversation.id)-\(record.id)",
            conversationId: targetConversation.id,
            type: record.type,
            role: record.role,
            content: record.content,
            toolId: record.toolId,
            toolName: record.toolName,
            toolInput: record.toolInput,
            toolApprovalStatus: record.type == "tool_approval"
                ? ToolApprovalStatus.superseded.rawValue
                : record.toolApprovalStatus,
            toolOutput: record.toolOutput,
            toolOutputStderr: record.toolOutputStderr,
            toolOutputInterrupted: record.toolOutputInterrupted,
            toolOutputIsImage: record.toolOutputIsImage,
            toolOutputNoOutputExpected: record.toolOutputNoOutputExpected,
            parentToolUseId: record.parentToolUseId,
            callerAgent: record.callerAgent,
            isError: record.isError,
            tokenInput: record.tokenInput,
            tokenOutput: record.tokenOutput,
            tokenCacheRead: record.tokenCacheRead,
            tokenCacheCreation: record.tokenCacheCreation,
            durationMs: record.durationMs,
            costUsd: 0,
            costUsdReported: false,
            providerModelId: record.providerModelId,
            contextWindowSize: record.contextWindowSize,
            notificationType: record.notificationType,
            stopReason: record.stopReason,
            conversation: targetConversation
        )
    }

    func rollbackFailedFork(
        target: ThreadForkTargetSnapshot,
        originalError: Error
    ) async throws {
        do {
            let resolution = await providerSessionActionService.resolveSessions(matching: target.providerSessionActionSnapshot)
            let diagnostics = await providerSessionActionService.deleteSessions(ProviderSessionActionResolution(
                snapshot: resolution.snapshot,
                records: resolution.records,
                missingBindings: []
            ))
            presentProviderSessionActionDiagnostics(diagnostics)

            if let dbThread = modelContext.resolveThread(id: target.threadID) {
                modelContext.delete(dbThread)
                try modelContext.save()
            }

            try await removeForkWorktreeIfUnclaimed(target.worktree, projectPath: target.projectPath)
        } catch {
            throw SidebarViewModelError.threadForkRollbackFailed(original: originalError, cleanup: error)
        }
    }

    func removeForkWorktreeIfUnclaimed(
        _ worktree: ForkCreatedWorktree?,
        projectPath: String
    ) async throws {
        guard let worktree else {
            return
        }
        guard let expectedStatus = worktree.expectedStatus,
              await gitStatusSnapshot(in: worktree.info.path) == expectedStatus else {
            return
        }

        try await worktreeManager.remove(
            projectPath: projectPath,
            worktreePath: worktree.info.path,
            branch: worktree.info.branch
        )
    }

    func gitStatusSnapshot(in directory: String) async -> String? {
        let result = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["status", "--porcelain=v1", "--untracked-files=all"],
            in: directory
        )
        guard result?.succeeded == true else {
            return nil
        }
        return result?.stdout
    }

    func conversationIDs(for thread: AgentThread) -> [String] {
        let threadID = thread.persistentModelID
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.id)
    }

    func mainConversation(for thread: AgentThread) -> Conversation? {
        let threadID = thread.persistentModelID
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        let conversations = (try? modelContext.fetch(descriptor)) ?? []
        return conversations.first(where: \.isMain) ?? conversations.sorted { lhs, rhs in
            lhs.displayOrder < rhs.displayOrder
        }.first
    }
}
