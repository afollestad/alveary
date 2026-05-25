import Foundation

struct BlockInputComposerLocation: Equatable {
    var projectPath: String?
    var worktreePath: String?

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

    init(effectiveProjectDirectory: String?) {
        self.init(projectPath: effectiveProjectDirectory)
    }

    private var baseURL: URL? {
        effectiveProjectDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func normalizedNonEmptyPath(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return CanonicalPath.normalize(path)
    }
}
