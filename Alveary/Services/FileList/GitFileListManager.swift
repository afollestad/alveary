import Foundation

actor GitFileListManager: FileListManager {
    private var cache: [String: [String]] = [:]
    private var revisions: [String: UInt64] = [:]
    private let gitService: GitService

    init(gitService: GitService) {
        self.gitService = gitService
    }

    func files(for projectPath: String) async -> [String] {
        let key = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        if let cached = cache[key] { return cached }
        return await refresh(for: key)
    }

    func invalidateCache(for projectPath: String) {
        let key = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let knownRoots = Set(cache.keys).union(revisions.keys).union([key])
        for root in knownRoots where Self.overlaps(root, key) {
            revisions[root, default: 0] &+= 1
            cache[root] = nil
        }
    }

    func warmCache(for projectPath: String) async {
        _ = await files(for: projectPath)
    }

    private func refresh(for key: String) async -> [String] {
        let revision = revisions[key, default: 0]
        revisions[key] = revision
        do {
            let files: [String]
            do {
                files = try await gitService.listFiles(in: key)
            } catch GitError.notARepository {
                let enumeration = Task.detached(priority: .utility) { try Self.enumerateFiles(in: key) }
                files = try await withTaskCancellationHandler {
                    try await enumeration.value
                } onCancel: { enumeration.cancel() }
            }
            guard !Task.isCancelled, revision == revisions[key, default: 0] else { return [] }
            cache[key] = files
            return files
        } catch {
            return []
        }
    }

    private nonisolated static func overlaps(_ first: String, _ second: String) -> Bool {
        first == second || first == "/" || second == "/" || first.hasPrefix(second + "/") || second.hasPrefix(first + "/")
    }

    /// Ordinary folders have no Git index. Do not descend into symlink directories or Git's own storage.
    private nonisolated static func enumerateFiles(in path: String) throws -> [String] {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard (try root.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw WorkspaceFolderError.missingDirectory(path)
        }
        // The path enumerator returns relative names; URL enumeration can silently rewrite /var
        // to /private/var, making a file fall outside the literal root the composer is filtering.
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return [] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        var files: [String] = []
        for case let relativePath as String in enumerator {
            try Task.checkCancellation()
            let url = root.appendingPathComponent(relativePath)
            if url.lastPathComponent == ".git" { enumerator.skipDescendants(); continue }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants() }
            if values.isRegularFile == true || (values.isSymbolicLink == true && values.isDirectory != true) {
                files.append(relativePath)
            }
        }
        return files.sorted()
    }
}
