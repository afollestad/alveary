import Foundation

@testable import Alveary

actor MockProviderSetupService: ProviderSetupService {
    struct Call: Sendable, Equatable {
        let providerId: String
        let workingDirectory: String
        let autoTrust: Bool
    }

    private var recordedCalls: [Call] = []
    private var trustedProjectPaths: Set<String> = []
    private var prepareForSpawnHook: (@Sendable () async -> Void)?
    private nonisolated let cachedTrust = MockProviderSetupTrustCache()

    nonisolated func cachedProjectTrustStatus(providerId: String, workingDirectory: String) -> Bool? {
        providerId != "claude" || cachedTrust.isTrusted(workingDirectory)
    }

    func projectTrustUpdates() async -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func prepareForSpawn(providerId: String, workingDirectory: String, autoTrust: Bool) async {
        recordedCalls.append(
            Call(
                providerId: providerId,
                workingDirectory: workingDirectory,
                autoTrust: autoTrust
            )
        )
        if autoTrust {
            setTrustedProject(workingDirectory, isTrusted: true)
        }
        let hook = prepareForSpawnHook
        prepareForSpawnHook = nil
        await hook?()
    }

    func isTrustedProject(providerId: String, workingDirectory: String) async -> Bool {
        providerId != "claude" || trustedProjectPaths.contains(CanonicalPath.normalize(workingDirectory))
    }

    func trustProject(providerId: String, workingDirectory: String) async {
        guard providerId == "claude" else {
            return
        }
        trustedProjectPaths.insert(CanonicalPath.normalize(workingDirectory))
        cachedTrust.setTrustedProject(workingDirectory, isTrusted: true)
    }

    func setTrustedProject(_ workingDirectory: String, isTrusted: Bool) {
        let normalizedPath = CanonicalPath.normalize(workingDirectory)
        if isTrusted {
            trustedProjectPaths.insert(normalizedPath)
        } else {
            trustedProjectPaths.remove(normalizedPath)
        }
        cachedTrust.setTrustedProject(workingDirectory, isTrusted: isTrusted)
    }

    func calls() -> [Call] {
        recordedCalls
    }

    func setPrepareForSpawnHook(_ hook: @escaping @Sendable () async -> Void) {
        prepareForSpawnHook = hook
    }
}
