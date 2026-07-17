import Foundation

@testable import Alveary

actor PausingThreadDetailProjectTrustService: ProviderSetupService {
    private let pausedProjectPath: String
    private var didPauseStatus = false
    private var statusPauseContinuation: CheckedContinuation<Void, Never>?
    private var statusPauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var trustedProjectPaths = Set<String>()

    init(pausedProjectPath: String) {
        self.pausedProjectPath = CanonicalPath.normalize(pausedProjectPath)
    }

    nonisolated func cachedProjectTrustStatus(providerId _: String, workingDirectory _: String) -> Bool? {
        nil
    }

    func projectTrustUpdates() async -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func prepareForSpawn(providerId _: String, workingDirectory _: String, autoTrust _: Bool) async {}

    func isTrustedProject(providerId _: String, workingDirectory: String) async -> Bool {
        let projectPath = CanonicalPath.normalize(workingDirectory)
        if projectPath == pausedProjectPath, !didPauseStatus {
            didPauseStatus = true
            statusPauseWaiters.forEach { $0.resume() }
            statusPauseWaiters.removeAll()
            await withCheckedContinuation { statusPauseContinuation = $0 }
        }
        return trustedProjectPaths.contains(projectPath)
    }

    func trustProject(providerId _: String, workingDirectory: String) async {
        trustedProjectPaths.insert(CanonicalPath.normalize(workingDirectory))
    }

    func waitUntilStatusPaused() async {
        guard !didPauseStatus else {
            return
        }
        await withCheckedContinuation { statusPauseWaiters.append($0) }
    }

    func resumePausedStatus() {
        statusPauseContinuation?.resume()
        statusPauseContinuation = nil
    }

    func recordedTrustedProjectPaths() -> Set<String> {
        trustedProjectPaths
    }
}

enum ThreadDetailProjectTrustError: LocalizedError {
    case cleanupFailed

    var errorDescription: String? {
        "Cleanup failed"
    }
}

final class ThreadDetailVoiceModelModalSink: VoiceInputComposerSink {
    var isModelPreparationModalPresented: Bool { true }

    func forceVoiceInputCommitSynchronously() {}
}
