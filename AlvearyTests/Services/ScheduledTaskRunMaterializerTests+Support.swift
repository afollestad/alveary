import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
struct ScheduledTaskRunMaterializerFixture {
    let root: URL
    let privateWorkspacesRoot: URL
    let workspaceOwnershipService: DefaultTaskWorkspaceOwnershipService
    let worktreeManager = ScheduledMaterializerWorktreeManager()
    let failureNotifications = MaterializerFailureNotifications()
    let context: ModelContext

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledTaskRunMaterializerTests-\(UUID().uuidString)", isDirectory: true)
        privateWorkspacesRoot = root.appendingPathComponent("Private", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        workspaceOwnershipService = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: privateWorkspacesRoot,
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("WorktreeRecords", isDirectory: true)
        )
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    func makeMaterializer(
        now: Date = Date(timeIntervalSince1970: 1_800_000_100),
        saveChanges: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        provenancePersistenceAttempts: Int = 3,
        ownershipService: (any TaskWorkspaceOwnershipService)? = nil
    ) -> DefaultScheduledTaskRunMaterializer {
        DefaultScheduledTaskRunMaterializer(
            modelContext: context,
            worktreeManager: worktreeManager,
            workspaceOwnershipService: ownershipService ?? workspaceOwnershipService,
            locale: Locale(identifier: "en_US_POSIX"),
            now: { now },
            saveChanges: saveChanges,
            failureNotification: { message, conversationID in
                failureNotifications.messages.append(message)
                failureNotifications.conversationIDs.append(conversationID)
            },
            provenancePersistenceAttempts: provenancePersistenceAttempts
        )
    }

    func insertRun(
        id: String,
        occurrenceID: String,
        occurrenceAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        workspaceKind: ScheduledTaskWorkspaceKind = .privateWorkspace,
        workspaceStrategy: ScheduledTaskWorkspaceStrategy = .worktree,
        projectPath: String? = nil,
        projectBaseRef: String? = nil,
        projectRemoteName: String? = nil,
        grantedRoots: [String] = []
    ) throws -> ScheduledTaskRun {
        let canonicalProjectPath = projectPath.map(CanonicalPath.normalize)
        let canonicalGrantedRoots = ScheduledTask.normalizedUniquePaths(grantedRoots)
        let workspaceIdentities = try ScheduledTaskWorkspaceIdentitySnapshot(
            workspaceKind: workspaceKind,
            projectPath: canonicalProjectPath,
            grantedRootPaths: canonicalGrantedRoots,
            identityAtPath: workspaceOwnershipService.directoryIdentity(at:)
        )
        let run = ScheduledTaskRun(
            id: id,
            occurrenceID: occurrenceID,
            triggerID: "trigger-\(id)",
            definitionID: "definition",
            definitionRevision: 1,
            occurrenceAt: occurrenceAt,
            triggerKind: .scheduled,
            titleSnapshot: "Review changes",
            promptSnapshot: "Review the scheduled changes.",
            timeZoneIdentifierSnapshot: "America/Chicago",
            providerIDSnapshot: "codex",
            modelSnapshot: "gpt-5",
            effortSnapshot: "high",
            permissionModeSnapshot: "acceptEdits",
            workspaceKindSnapshot: workspaceKind,
            workspaceStrategySnapshot: workspaceStrategy,
            projectPathSnapshot: canonicalProjectPath,
            projectBaseRefSnapshot: projectBaseRef,
            projectRemoteNameSnapshot: projectRemoteName,
            grantedRootsSnapshot: canonicalGrantedRoots,
            workspaceIdentitySnapshot: workspaceIdentities
        )
        context.insert(run)
        try context.save()
        return run
    }

    func createDirectory(named name: String) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func gregorianDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date? {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

actor ScheduledMaterializerWorktreeManager: WorktreeManager {
    struct CreateCall: Equatable {
        let projectPath: String
        let threadName: String
        let baseRef: String?
        let remoteName: String?
    }

    struct RemoveCall: Equatable {
        let projectPath: String
        let worktreePath: String
        let branch: String?
    }

    struct DeleteBranchCall: Equatable {
        let projectPath: String
        let branch: String
        let expectedOID: String
    }

    var createResult = WorktreeInfo(
        path: "/tmp/scheduled-worktree",
        branch: "alveary/scheduled",
        headOID: "scheduled-head"
    )
    var createError: Error?
    private var removeError: Error?
    private var deleteBranchError: Error?
    var createHook: (@Sendable () -> Void)?
    private var deleteBranchHook: (@MainActor @Sendable () -> Void)?
    var provenanceRecordHook: (@MainActor @Sendable (FailedWorktreeCreationCleanup) -> Void)?
    var cancelAfterCreate = false
    var recordedCreateCalls: [CreateCall] = []
    var recordedExpectedProjectIdentities: [TaskWorkspaceFileSystemIdentity] = []
    private var listResult: [WorktreeInfo]?
    private var listHook: (@Sendable () -> Void)?
    private var recordedRemoveCalls: [RemoveCall] = []
    private var recordedRemoveProjectIdentities: [TaskWorkspaceFileSystemIdentity] = []
    private var recordedRemoveWorktreeIdentities: [TaskWorkspaceFileSystemIdentity?] = []
    private var recordedDeleteBranchCalls: [DeleteBranchCall] = []

    func validateCreation(
        projectPath: String,
        baseRef: String?,
        remoteName: String?
    ) async throws {}

    func validateCreation(
        projectPath: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws {}

    func setCreateResult(_ result: WorktreeInfo) {
        createResult = WorktreeInfo(
            path: result.path,
            branch: result.branch,
            headOID: result.headOID ?? "scheduled-head"
        )
    }

    func setCreateError(_ error: Error) {
        createError = error
    }

    func setRemoveError(_ error: Error) {
        removeError = error
    }

    func setDeleteBranchError(_ error: Error?) {
        deleteBranchError = error
    }

    func setRetryableDeleteBranchError(_ error: Error?) {
        deleteBranchError = error.map(RetryableWorktreeBranchDeletionError.init(underlying:))
    }

    func setDeleteBranchHook(_ hook: (@MainActor @Sendable () -> Void)?) {
        deleteBranchHook = hook
    }

    func setListResult(_ result: [WorktreeInfo]) {
        listResult = result
    }

    func setListHook(_ hook: (@Sendable () -> Void)?) {
        listHook = hook
    }

    func setCreateHook(_ hook: @escaping @Sendable () -> Void) {
        createHook = hook
    }

    func setProvenanceRecordHook(
        _ hook: (@MainActor @Sendable (FailedWorktreeCreationCleanup) -> Void)?
    ) {
        provenanceRecordHook = hook
    }

    func setCancelAfterCreate(_ shouldCancel: Bool) {
        cancelAfterCreate = shouldCancel
    }

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        recordedCreateCalls.append(.init(
            projectPath: projectPath,
            threadName: threadName,
            baseRef: baseRef,
            remoteName: remoteName
        ))
        if let createError {
            throw createError
        }
        createHook?()
        if cancelAfterCreate {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        }
        return createResult
    }

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws -> IdentityValidatedWorktreeInfo {
        try await create(
            projectPath: projectPath,
            threadName: threadName,
            baseRef: baseRef,
            remoteName: remoteName,
            provenanceContext: WorktreeCreationProvenanceContext(
                expectedProjectIdentity: expectedProjectIdentity,
                recorder: { _ in }
            )
        )
    }

    func createFromBranch(
        projectPath: String,
        threadName: String,
        branch: String,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        createResult
    }

    func remove(projectPath: String, worktreePath: String, branch: String?) async throws {
        recordedRemoveCalls.append(.init(
            projectPath: projectPath,
            worktreePath: worktreePath,
            branch: branch
        ))
        if let removeError {
            throw removeError
        }
    }

    func remove(
        projectPath: String,
        worktreePath: String,
        branch: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws {
        guard (try? Self.directoryIdentity(at: projectPath)) == expectedProjectIdentity else {
            throw WorktreeSourceValidationError.sourceProjectChanged(projectPath)
        }
        if let currentWorktreeIdentity = try? Self.directoryIdentity(at: worktreePath),
           currentWorktreeIdentity != expectedWorktreeIdentity {
            throw WorktreeSourceValidationError.ownedWorktreeChanged(worktreePath)
        }
        recordedRemoveProjectIdentities.append(expectedProjectIdentity)
        recordedRemoveWorktreeIdentities.append(expectedWorktreeIdentity)
        try await remove(
            projectPath: projectPath,
            worktreePath: worktreePath,
            branch: branch
        )
    }

    func prepareForkContext(sourcePath: String, worktreePath: String) async throws {}
    func removeAll(projectPath: String) async throws {}
    func deleteBranch(projectPath: String, branch: String, expectedOID: String) async throws {
        recordedDeleteBranchCalls.append(
            .init(projectPath: projectPath, branch: branch, expectedOID: expectedOID)
        )
        await deleteBranchHook?()
        if let deleteBranchError {
            throw deleteBranchError
        }
    }
    func deleteBranch(
        projectPath: String,
        branch: String,
        expectedOID: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws {
        guard (try? Self.directoryIdentity(at: projectPath)) == expectedProjectIdentity else {
            throw WorktreeSourceValidationError.sourceProjectChanged(projectPath)
        }
        try await deleteBranch(projectPath: projectPath, branch: branch, expectedOID: expectedOID)
    }
    func list(projectPath: String) async throws -> [WorktreeInfo] {
        listHook?()
        return listResult ?? [createResult]
    }

    func createCalls() -> [CreateCall] {
        recordedCreateCalls
    }

    func expectedProjectIdentities() -> [TaskWorkspaceFileSystemIdentity] {
        recordedExpectedProjectIdentities
    }

    func removeCalls() -> [RemoveCall] {
        recordedRemoveCalls
    }

    func removeProjectIdentities() -> [TaskWorkspaceFileSystemIdentity] {
        recordedRemoveProjectIdentities
    }

    func removeWorktreeIdentities() -> [TaskWorkspaceFileSystemIdentity?] {
        recordedRemoveWorktreeIdentities
    }

    func deleteBranchCalls() -> [DeleteBranchCall] {
        recordedDeleteBranchCalls
    }

    static func directoryIdentity(at path: String) throws -> TaskWorkspaceFileSystemIdentity {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard let systemNumber = attributes[.systemNumber] as? NSNumber,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber else {
            throw TaskWorkspaceOwnershipError.workspaceIdentityMismatch(path)
        }
        return TaskWorkspaceFileSystemIdentity(
            systemNumber: systemNumber.uint64Value,
            fileNumber: fileNumber.uint64Value
        )
    }
}

@MainActor
final class MaterializerFailureNotifications {
    var messages: [String?] = []
    var conversationIDs: [String] = []
}

enum ScheduledMaterializerTestError: LocalizedError {
    case cleanupFailed
    case saveFailed
    case worktreeCreateFailed

    var errorDescription: String? {
        switch self {
        case .cleanupFailed:
            return "The test workspace cleanup failed."
        case .saveFailed:
            return "The test save failed."
        case .worktreeCreateFailed:
            return "The test worktree creation failed."
        }
    }
}
