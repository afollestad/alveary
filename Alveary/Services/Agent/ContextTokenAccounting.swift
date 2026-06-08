import Foundation

enum ContextTokenAccounting: Equatable, Sendable {
    case additiveCacheRead
    case cachedInputIncluded

    init(providerID: String?) {
        let normalizedProviderID = providerID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = normalizedProviderID == "codex" ? .cachedInputIncluded : .additiveCacheRead
    }

    func contextUsedTokens(input: Int, cacheRead: Int, cacheCreation: Int) -> Int {
        switch self {
        case .additiveCacheRead:
            input + cacheRead + cacheCreation
        case .cachedInputIncluded:
            input + cacheCreation
        }
    }
}
