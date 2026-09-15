import Foundation

@testable import Alveary

actor MockHarnessSetupService: HarnessSetupService {
    struct Call: Sendable, Equatable {
        let harnessId: String
        let workingDirectory: String
        let autoTrust: Bool
    }

    private var recordedCalls: [Call] = []
    private var trustedProjectPaths: Set<String> = []
    private var prepareForSpawnHook: (@Sendable () async -> Void)?
    private nonisolated let cachedTrust = MockHarnessSetupTrustCache()

    nonisolated func cachedProjectTrustStatus(harnessId: String, workingDirectory: String) -> Bool? {
        harnessId != "claude" || cachedTrust.isTrusted(workingDirectory)
    }

    func projectTrustUpdates() async -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func prepareForSpawn(harnessId: String, workingDirectory: String, autoTrust: Bool) async {
        recordedCalls.append(
            Call(
                harnessId: harnessId,
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

    func isTrustedProject(harnessId: String, workingDirectory: String) async -> Bool {
        harnessId != "claude" || trustedProjectPaths.contains(CanonicalPath.normalize(workingDirectory))
    }

    func trustProject(harnessId: String, workingDirectory: String) async {
        guard harnessId == "claude" else {
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
