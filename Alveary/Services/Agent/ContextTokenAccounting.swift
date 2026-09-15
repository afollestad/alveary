import Foundation

enum ContextTokenAccounting: Equatable, Sendable {
    case additiveCacheRead
    case cachedInputIncluded

    init(harnessID: String?) {
        let normalizedHarnessID = harnessID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = normalizedHarnessID == "codex" ? .cachedInputIncluded : .additiveCacheRead
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
