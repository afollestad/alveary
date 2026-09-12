import Foundation

/// The source and grants chosen when a thread or schedule is created. Project membership is only a default;
/// running sessions, recovery and cleanup must use this snapshot after a project changes.
struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    var primarySource: SourceFolderSnapshot?
    var grants: [SourceFolderSnapshot]
    var rootsExplicitlyManaged: Bool

    init(primarySource: SourceFolderSnapshot?, grants: [SourceFolderSnapshot] = [], rootsExplicitlyManaged: Bool = true) {
        self.primarySource = primarySource
        var seen = Set<String>()
        self.grants = grants.filter { seen.insert($0.path).inserted }
        self.rootsExplicitlyManaged = rootsExplicitlyManaged
    }

    /// Source pickers need unique options even when a worktree separately grants its original checkout.
    var sourceFolders: [SourceFolderSnapshot] {
        var seen = Set<String>()
        return ((primarySource.map { [$0] } ?? []) + grants).filter { seen.insert($0.path).inserted }
    }

    func additionalWorkspaceRoots(workingDirectory: String) -> [String] {
        let extra = grants.map(\.path).filter { $0 != workingDirectory }
        return rootsExplicitlyManaged ? [workingDirectory] + extra : extra
    }

    var encoded: String {
        // All members are JSON primitives; a coding failure is a programming error, never permission to drop roots.
        do {
            let data = try JSONEncoder().encode(self)
            guard let json = String(data: data, encoding: .utf8) else { preconditionFailure("Workspace JSON must be UTF-8") }
            return json
        } catch { preconditionFailure("Failed to encode a workspace snapshot: \(error)") }
    }

    static func decode(_ json: String?) -> Self? {
        guard let json else { return nil }
        return try? JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }
}

/// Complete, immutable target for operations on a selected folder. Primary source folders map to the
/// thread's worktree; additional folders always retain their local directory.
struct WorkspaceFolderTarget: Equatable, Hashable, Sendable, Identifiable {
    let directory: String
    let source: SourceFolderSnapshot
    let isPrimary: Bool

    // A worktree and its separately granted source checkout can share source.path.
    var id: String { (isPrimary ? "primary:" : "grant:") + source.path }
    var repository: String? { source.githubRepository ?? source.gitRemote.flatMap(Project.parseGitHubRepository) }
    var remoteName: String? { source.remoteName }
    var baseRef: String? { source.baseRef }

    func requireDirectory() throws -> URL {
        var isDirectory: ObjCBool = false
        guard directory.hasPrefix("/"),
              FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceFolderError.missingDirectory(directory)
        }
        return URL(fileURLWithPath: directory, isDirectory: true)
    }
}

enum WorkspaceFolderError: LocalizedError {
    case missingDirectory(String)
    case invalidSnapshot
    case staleSelection

    var errorDescription: String? {
        switch self {
        case .missingDirectory(let path): "The source folder is unavailable: \(path)"
        case .staleSelection: "The selected folder changed. Try the action again."
        case .invalidSnapshot: "The saved workspace could not be read. Restore its configuration before continuing."
        }
    }
}

extension Notification.Name {
    static let workspaceConfigurationChanged = Notification.Name("workspaceConfigurationChanged")
}
