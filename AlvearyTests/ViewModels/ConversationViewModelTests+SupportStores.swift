import Foundation

@testable import Alveary

final class MockAgentsManagerStatusStore: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [String: ActivitySignal] = [:]

    func set(_ status: ActivitySignal, for conversationId: String) {
        lock.withLock {
            statuses[conversationId] = status
        }
    }

    func status(for conversationId: String) -> ActivitySignal {
        lock.withLock {
            statuses[conversationId] ?? .neutral
        }
    }

    func snapshot() -> [String: ActivitySignal] {
        lock.withLock {
            statuses
        }
    }
}

final class MockProviderSetupTrustCache: @unchecked Sendable {
    private let lock = NSLock()
    private var trustedProjectPaths: Set<String> = []

    func isTrusted(_ workingDirectory: String) -> Bool {
        lock.withLock {
            trustedProjectPaths.contains(CanonicalPath.normalize(workingDirectory))
        }
    }

    func setTrustedProject(_ workingDirectory: String, isTrusted: Bool) {
        let normalizedPath = CanonicalPath.normalize(workingDirectory)
        lock.withLock {
            if isTrusted {
                trustedProjectPaths.insert(normalizedPath)
            } else {
                trustedProjectPaths.remove(normalizedPath)
            }
        }
    }
}
