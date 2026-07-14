import Foundation

@testable import Alveary

actor SidebarMockWorktreeManager: WorktreeManager {
    struct CreateCall: Sendable, Equatable {
        let projectPath: String
        let threadName: String
        let baseRef: String?
        let remoteName: String?
    }

    struct PrepareForkContextCall: Sendable, Equatable {
        let sourcePath: String
        let worktreePath: String
    }

    struct DeleteBranchCall: Sendable, Equatable {
        let projectPath: String
        let branch: String
        let expectedOID: String
    }

    struct RemoveCall: Sendable, Equatable {
        let projectPath: String
        let worktreePath: String
        let branch: String?
    }

    private var recordedCreateCalls: [CreateCall] = []
    private var recordedPrepareForkContextCalls: [PrepareForkContextCall] = []
    private var recordedDeleteBranchCalls: [DeleteBranchCall] = []
    private var recordedRemoveCalls: [RemoveCall] = []
    private var recordedRemoveAllCalls: [String] = []
    private var createInfo = WorktreeInfo(path: "/tmp/worktree", branch: "alveary/thread")
    private var createError: MockError?
    private var prepareForkContextError: MockError?
    private var removeError: MockError?
    private var removeAllError: MockError?
    private var deleteBranchError: MockError?
    private var deleteBranchErrorIsRetryable = false
    private var listResult: [WorktreeInfo] = []
    private var listError: MockError?
    private var listHook: (@Sendable () -> Void)?
    private var validatesRemovalIdentities = false
    private var deleteBranchGate: SidebarMockBranchDeletionGate?

    func validateCreation(
        projectPath: String,
        baseRef: String?,
        remoteName: String?
    ) async throws {}

    func setCreateInfo(_ info: WorktreeInfo) {
        createInfo = info
    }

    func setCreateError(_ error: MockError?) {
        createError = error
    }

    func setPrepareForkContextError(_ error: MockError?) {
        prepareForkContextError = error
    }

    func setRemoveError(_ error: MockError?) {
        removeError = error
    }

    func setRemoveAllError(_ error: MockError?) {
        removeAllError = error
    }

    func setDeleteBranchError(_ error: MockError?) {
        deleteBranchError = error
        deleteBranchErrorIsRetryable = false
    }

    func setRetryableDeleteBranchError(_ error: MockError?) {
        deleteBranchError = error
        deleteBranchErrorIsRetryable = error != nil
    }

    func setDeleteBranchGate(_ gate: SidebarMockBranchDeletionGate?) {
        deleteBranchGate = gate
    }

    func setListResult(_ result: [WorktreeInfo], error: MockError? = nil) {
        listResult = result
        listError = error
    }

    func setListHook(_ hook: (@Sendable () -> Void)?) {
        listHook = hook
    }

    func setValidatesRemovalIdentities(_ validates: Bool) {
        validatesRemovalIdentities = validates
    }

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        recordedCreateCalls.append(CreateCall(projectPath: projectPath, threadName: threadName, baseRef: baseRef, remoteName: remoteName))
        if let createError {
            throw createError
        }
        return createInfo
    }

    func createFromBranch(
        projectPath: String,
        threadName: String,
        branch: String,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        WorktreeInfo(path: "/tmp/worktree", branch: branch)
    }

    func prepareForkContext(sourcePath: String, worktreePath: String) async throws {
        recordedPrepareForkContextCalls.append(PrepareForkContextCall(sourcePath: sourcePath, worktreePath: worktreePath))
        if let prepareForkContextError {
            throw prepareForkContextError
        }
    }

    func remove(projectPath: String, worktreePath: String, branch: String?) async throws {
        recordedRemoveCalls.append(
            RemoveCall(projectPath: projectPath, worktreePath: worktreePath, branch: branch)
        )
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
        if validatesRemovalIdentities {
            guard Self.directoryIdentity(at: projectPath) == expectedProjectIdentity else {
                throw MockError.removeFailed
            }
            if let currentWorktreeIdentity = Self.directoryIdentity(at: worktreePath),
               currentWorktreeIdentity != expectedWorktreeIdentity {
                throw MockError.removeFailed
            }
        }
        try await remove(projectPath: projectPath, worktreePath: worktreePath, branch: branch)
    }

    func removeAll(projectPath: String) async throws {
        recordedRemoveAllCalls.append(projectPath)
        if let removeAllError {
            throw removeAllError
        }
    }

    func deleteBranch(projectPath: String, branch: String, expectedOID: String) async throws {
        recordedDeleteBranchCalls.append(
            DeleteBranchCall(projectPath: projectPath, branch: branch, expectedOID: expectedOID)
        )
        if let deleteBranchGate {
            await deleteBranchGate.enterAndWaitForRelease()
        }
        if let deleteBranchError {
            if deleteBranchErrorIsRetryable {
                throw RetryableWorktreeBranchDeletionError(underlying: deleteBranchError)
            }
            throw deleteBranchError
        }
    }

    func deleteBranch(
        projectPath: String,
        branch: String,
        expectedOID: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws {
        try await deleteBranch(projectPath: projectPath, branch: branch, expectedOID: expectedOID)
    }

    func list(projectPath: String) async throws -> [WorktreeInfo] {
        if let listError {
            throw listError
        }
        listHook?()
        return listResult
    }

    func deleteBranchCalls() -> [DeleteBranchCall] {
        recordedDeleteBranchCalls
    }

    func createCalls() -> [CreateCall] {
        recordedCreateCalls
    }

    func prepareForkContextCalls() -> [PrepareForkContextCall] {
        recordedPrepareForkContextCalls
    }

    func removeCalls() -> [RemoveCall] {
        recordedRemoveCalls
    }

    func removeAllCalls() -> [String] {
        recordedRemoveAllCalls
    }

    private static func directoryIdentity(at path: String) -> TaskWorkspaceFileSystemIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let systemNumber = attributes[.systemNumber] as? NSNumber,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber else {
            return nil
        }
        return TaskWorkspaceFileSystemIdentity(
            systemNumber: systemNumber.uint64Value,
            fileNumber: fileNumber.uint64Value
        )
    }
}

actor SidebarMockBranchDeletionGate {
    private var entered = false
    private var released = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func enterAndWaitForRelease() async {
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        guard !released else {
            return
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !entered else {
            return
        }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

extension SidebarMockWorktreeManager {
    enum MockError: Error, Sendable, Equatable {
        case createFailed
        case prepareForkContextFailed
        case removeFailed
        case removeAllFailed
        case listFailed
        case deleteBranchFailed
    }

    func validateCreation(
        projectPath: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws {}

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws -> IdentityValidatedWorktreeInfo {
        let info = try await create(
            projectPath: projectPath,
            threadName: threadName,
            baseRef: baseRef,
            remoteName: remoteName
        )
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: info.path),
              let systemNumber = attributes[.systemNumber] as? NSNumber,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber else {
            throw MockError.createFailed
        }
        return IdentityValidatedWorktreeInfo(
            info: info,
            sourceProjectIdentity: expectedProjectIdentity,
            worktreeIdentity: TaskWorkspaceFileSystemIdentity(
                systemNumber: systemNumber.uint64Value,
                fileNumber: fileNumber.uint64Value
            )
        )
    }
}
