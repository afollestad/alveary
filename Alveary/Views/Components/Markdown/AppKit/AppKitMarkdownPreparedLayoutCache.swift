import Foundation

@MainActor
/// Small bounded cache for prepared markdown layout data. It intentionally
/// stores measurements, not views, so long transcripts do not retain AppKit
/// subtrees before viewport hydration is introduced.
final class AppKitMarkdownPreparedLayoutCache {
    private let countLimit: Int
    private let costLimit: Int
    private var storage: [AppKitMarkdownPreparedLayoutKey: CacheEntry] = [:]
    private var order: [AppKitMarkdownPreparedLayoutKey] = []
    private var totalCost = 0

    init(countLimit: Int = 600, costLimit: Int = 4_000_000) {
        self.countLimit = countLimit
        self.costLimit = costLimit
    }

    func measurement(for key: AppKitMarkdownPreparedLayoutKey) -> AppKitMarkdownLayoutMeasurement? {
        guard let entry = storage[key] else {
            return nil
        }
        markRecentlyUsed(key)
        return entry.measurement
    }

    func insert(
        _ measurement: AppKitMarkdownLayoutMeasurement,
        for key: AppKitMarkdownPreparedLayoutKey,
        cost: Int
    ) {
        if let existing = storage.removeValue(forKey: key) {
            totalCost -= existing.cost
            order.removeAll { $0 == key }
        }
        let normalizedCost = max(cost, 1)
        storage[key] = CacheEntry(measurement: measurement, cost: normalizedCost)
        order.append(key)
        totalCost += normalizedCost
        evictIfNeeded()
    }

#if DEBUG
    var countForTesting: Int {
        storage.count
    }
#endif

    private func markRecentlyUsed(_ key: AppKitMarkdownPreparedLayoutKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func evictIfNeeded() {
        while storage.count > countLimit || totalCost > costLimit {
            guard let oldestKey = order.first,
                  let removed = storage.removeValue(forKey: oldestKey) else {
                break
            }
            order.removeFirst()
            totalCost -= removed.cost
        }
    }
}

private struct CacheEntry {
    let measurement: AppKitMarkdownLayoutMeasurement
    let cost: Int
}
