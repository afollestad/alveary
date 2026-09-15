protocol HarnessSetupService: Actor {
    nonisolated func cachedProjectTrustStatus(harnessId: String, workingDirectory: String) -> Bool?
    func projectTrustUpdates() async -> AsyncStream<Void>
    func prepareForSpawn(harnessId: String, workingDirectory: String, autoTrust: Bool) async
    func isTrustedProject(harnessId: String, workingDirectory: String) async -> Bool
    func trustProject(harnessId: String, workingDirectory: String) async
}
