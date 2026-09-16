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
        cachedContextWindowSize: Int?,
        accounting: ContextTokenAccounting = .additiveCacheRead,
        harnessID: String? = nil
    ) -> ConversationUsageSummary? {
        let tokenEvents = events.filter { $0.type == ConversationEventRecord.tokensType }
        let currentWindowEvents: ArraySlice<ConversationEventRecord>
        if let lastInvalidationIndex = events.lastIndex(where: { $0.type == ConversationEventRecord.contextWindowInvalidatedType }) {
            currentWindowEvents = events[events.index(after: lastInvalidationIndex)...]
        } else {
            currentWindowEvents = events[...]
        }

        // Model changes only invalidate the reported max size. The latest token row
        // still describes the current harness window until a new result replaces it.
        let currentWindowTokenEvents = currentWindowEvents.filter { $0.type == ConversationEventRecord.tokensType }
        // OpenCode's count-free terminal rows are durable completion evidence for approval
        // restoration and scheduling, but do not replace the last measured context window.
        let latestTokenEvent = tokenEvents.last { record in
            harnessID != "opencode" || !isOpenCodeTurnBoundary(record)
        }
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
            accounting.contextUsedTokens(
                input: $0.tokenInput,
                cacheRead: $0.tokenCacheRead,
                cacheCreation: $0.tokenCacheCreation
            )
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

    private static func isOpenCodeTurnBoundary(_ record: ConversationEventRecord) -> Bool {
        (record.stopReason == "end_turn" || record.stopReason == "error") &&
            record.contextWindowSize == nil && record.harnessModelId == nil &&
            record.tokenInput == 0 && record.tokenOutput == 0 && record.tokenCacheRead == 0 && record.tokenCacheCreation == 0
    }
}
