import Foundation

@testable import Alveary

@MainActor
final class WorktreeCreationProvenanceLog {
    var records: [FailedWorktreeCreationCleanup] = []
}

@MainActor
final class WorktreeParentReplacement {
    let root: URL
    private(set) var outsideTarget: URL?
    private var didReplace = false

    init(root: URL) {
        self.root = root
    }

    func replaceParent(for cleanup: FailedWorktreeCreationCleanup) throws {
        guard !didReplace else {
            return
        }
        didReplace = true
        let target = URL(fileURLWithPath: cleanup.worktreePath, isDirectory: true)
        let parent = target.deletingLastPathComponent()
        let movedParent = root.appendingPathComponent("MovedWorktreeNamespace", isDirectory: true)
        let outsideParent = root.appendingPathComponent("OutsideWorktreeRoot", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideParent, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: parent, to: movedParent)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: outsideParent)
        outsideTarget = outsideParent.appendingPathComponent(target.lastPathComponent, isDirectory: true)
    }
}

final class WorktreeParentSwapDirectoryCreator: @unchecked Sendable {
    private let lock = NSLock()
    private var createdOutsideTarget = false
    var didCreateOutsideTarget: Bool {
        lock.withLock { createdOutsideTarget }
    }

    func create(atPath path: String) throws {
        let target = URL(fileURLWithPath: path, isDirectory: true)
        let parent = target.deletingLastPathComponent()
        let worktreesBase = parent.deletingLastPathComponent()
        let movedParent = worktreesBase.appendingPathComponent("MovedWorktreeNamespace", isDirectory: true)
        let outsideParent = worktreesBase.appendingPathComponent("OutsideWorktreeNamespace", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideParent, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: parent, to: movedParent)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: outsideParent)
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        lock.withLock { createdOutsideTarget = true }
    }
}

enum WorktreeCreationIdentityTestError: Error {
    case expectedRollbackError
    case missingCreatedWorktree
}
