protocol ProviderSetupService: Actor {
    func prepareForSpawn(providerId: String, workingDirectory: String, autoTrust: Bool) async
}
