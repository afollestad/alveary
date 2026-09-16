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

final class MockHarnessSetupTrustCache: @unchecked Sendable {
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

struct MockContextWindowCacheUpdate: Equatable {
    let harnessId: String
    let selectedModel: String
    let reportedModelId: String?
    let contextWindowSize: Int
}

actor MockContextWindowCache: ContextWindowCache {
    private(set) var updates: [MockContextWindowCacheUpdate] = []
    var sizes: [String: Int] = [:]

    func contextWindowSize(harnessId: String, model: String) async -> Int? {
        guard let key = JSONContextWindowCache.cacheKey(harnessId: harnessId, model: model) else {
            return nil
        }
        return sizes[key]
    }

    func update(
        harnessId: String,
        selectedModel: String,
        reportedModelId: String?,
        contextWindowSize: Int
    ) async {
        updates.append(MockContextWindowCacheUpdate(
            harnessId: harnessId,
            selectedModel: selectedModel,
            reportedModelId: reportedModelId,
            contextWindowSize: contextWindowSize
        ))
    }
}
