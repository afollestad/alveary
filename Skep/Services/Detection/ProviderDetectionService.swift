protocol ProviderDetectionService: Actor {
    func resolvedPath(for providerId: String) -> String?
    func status(for providerId: String) -> ProviderStatus
    func checkAllProviders() async
    func checkProvider(_ providerId: String) async
}

enum ProviderStatus: Sendable, Equatable {
    case unchecked
    case connected(path: String, version: String)
    case missing
    case needsKey
    case error(String)
}
