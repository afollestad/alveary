import Foundation

struct BlockInputComposerLocation: Equatable, Sendable {
    var projectPath: String?
    var worktreePath: String?
    var workspaceRoots: [String] = []

    var effectiveProjectDirectory: String? {
        normalizedNonEmptyPath(worktreePath) ?? normalizedNonEmptyPath(projectPath)
    }

    var fileBaseURL: URL? {
        baseURL
    }

    var imageBaseURL: URL? {
        baseURL
    }

    init(projectPath: String?, worktreePath: String? = nil) {
        self.projectPath = projectPath
        self.worktreePath = worktreePath
    }

    init(effectiveProjectDirectory: String?, workspaceRoots: [String] = []) {
        self.init(projectPath: effectiveProjectDirectory)
        self.workspaceRoots = workspaceRoots
    }

    var effectiveWorkspaceRoots: [String] {
        var seen = Set<String>()
        return ((effectiveProjectDirectory.map { [$0] } ?? []) + workspaceRoots).filter { seen.insert($0).inserted }
    }

    private var baseURL: URL? {
        effectiveProjectDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func normalizedNonEmptyPath(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
