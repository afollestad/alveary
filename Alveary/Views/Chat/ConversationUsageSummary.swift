import Foundation

struct ConversationUsageSummary: Equatable, Sendable {
    let contextUsedTokens: Int
    let contextWindowSize: Int
    let totalCostUsd: Double
    let hasReportedCost: Bool
    let hasReportedUsage: Bool
    let isUsingCachedContextWindow: Bool

    static let unreported = ConversationUsageSummary(
        contextUsedTokens: 0,
        contextWindowSize: 0,
        totalCostUsd: 0,
        hasReportedCost: false,
        hasReportedUsage: false,
        isUsingCachedContextWindow: false
    )

    var hasKnownContextWindowSize: Bool {
        contextWindowSize > 0
    }

    var contextUsageFraction: Double {
        guard contextWindowSize > 0 else {
            return 0
        }
        return min(max(Double(contextUsedTokens) / Double(contextWindowSize), 0), 1)
    }

    var contextUsagePercent: Int {
        Int((contextUsageFraction * 100).rounded())
    }

    static func derive(
        from events: [ConversationEventRecord],
        cachedContextWindowSize: Int?
    ) -> ConversationUsageSummary? {
        let tokenEvents = events.filter { $0.type == "tokens" }
        let currentWindowEvents: ArraySlice<ConversationEventRecord>
        if let lastInvalidationIndex = events.lastIndex(where: { $0.type == ConversationEventRecord.contextWindowInvalidatedType }) {
            currentWindowEvents = events[events.index(after: lastInvalidationIndex)...]
        } else {
            currentWindowEvents = events[...]
        }

        // Model changes only invalidate the reported max size. The latest token row
        // still describes the current provider window until a new result replaces it.
        let currentWindowTokenEvents = currentWindowEvents.filter { $0.type == "tokens" }
        let latestTokenEvent = tokenEvents.last
        let reportedContextWindowSize = currentWindowTokenEvents.reversed().compactMap { record -> Int? in
            guard let contextWindowSize = record.contextWindowSize, contextWindowSize > 0 else {
                return nil
            }
            return contextWindowSize
        }.first
        let positiveCachedContextWindowSize = cachedContextWindowSize.flatMap { $0 > 0 ? $0 : nil }
        let contextWindowSize = reportedContextWindowSize ?? positiveCachedContextWindowSize ?? 0

        guard latestTokenEvent != nil || contextWindowSize > 0 else {
            return nil
        }

        let contextUsedTokens = latestTokenEvent.map {
            $0.tokenInput + $0.tokenCacheCreation + $0.tokenCacheRead
        } ?? 0
        let totalCostUsd = tokenEvents.reduce(0) { partialResult, record in
            partialResult + record.costUsd
        }
        let hasReportedCost = tokenEvents.contains { $0.costUsdReported || $0.costUsd > 0 }

        return ConversationUsageSummary(
            contextUsedTokens: contextUsedTokens,
            contextWindowSize: contextWindowSize,
            totalCostUsd: totalCostUsd,
            hasReportedCost: hasReportedCost,
            hasReportedUsage: latestTokenEvent != nil,
            isUsingCachedContextWindow: reportedContextWindowSize == nil && positiveCachedContextWindowSize != nil
        )
    }
}
