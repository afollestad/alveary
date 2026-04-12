protocol FileListManager: Actor {
    func files(for projectPath: String) async -> [String]
    func invalidateCache(for projectPath: String)
    func warmCache(for projectPath: String) async
}
