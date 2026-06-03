protocol ProviderSetupService: Actor {
    nonisolated func cachedProjectTrustStatus(providerId: String, workingDirectory: String) -> Bool?
    func projectTrustUpdates() async -> AsyncStream<Void>
    func prepareForSpawn(providerId: String, workingDirectory: String, autoTrust: Bool) async
    func isTrustedProject(providerId: String, workingDirectory: String) async -> Bool
    func trustProject(providerId: String, workingDirectory: String) async
}
