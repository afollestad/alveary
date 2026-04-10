actor GitFileListManager: FileListManager {
    private var cache: [String: [String]] = [:]

    private let gitService: GitService

    init(gitService: GitService) {
        self.gitService = gitService
    }

    func files(for projectPath: String) async -> [String] {
        let cacheKey = CanonicalPath.normalize(projectPath)
        if let cached = cache[cacheKey] {
            return cached
        }
        return await refresh(for: cacheKey)
    }

    func invalidateCache(for projectPath: String) {
        cache.removeValue(forKey: CanonicalPath.normalize(projectPath))
    }

    func warmCache(for projectPath: String) async {
        let cacheKey = CanonicalPath.normalize(projectPath)
        guard cache[cacheKey] == nil else {
            return
        }
        _ = await refresh(for: cacheKey)
    }

    private func refresh(for cacheKey: String) async -> [String] {
        let files = (try? await gitService.listFiles(in: cacheKey)) ?? []
        cache[cacheKey] = files
        return files
    }
}
