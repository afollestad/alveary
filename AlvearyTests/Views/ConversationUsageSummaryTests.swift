import XCTest

@testable import Alveary

final class ConversationUsageSummaryTests: XCTestCase {
    func testLatestTokenRecordDrivesCurrentUsageAndReportedMaxWins() throws {
        let events = [
            tokenRecord(
                input: 100,
                output: 50,
                cacheRead: 20,
                cacheCreation: 30,
                costUsd: 0.01,
                contextWindowSize: 200_000
            ),
            tokenRecord(
                input: 200,
                output: 75,
                cacheRead: 40,
                cacheCreation: 60,
                costUsd: 0.02,
                contextWindowSize: 1_000_000
            )
        ]

        let summary = ConversationUsageSummary.derive(from: events, cachedContextWindowSize: 200_000)

        XCTAssertEqual(summary?.contextUsedTokens, 300)
        XCTAssertEqual(summary?.contextWindowSize, 1_000_000)
        XCTAssertEqual(try XCTUnwrap(summary?.totalCostUsd), 0.03, accuracy: 0.000_001)
        XCTAssertEqual(summary?.hasReportedCost, true)
        XCTAssertEqual(summary?.hasReportedUsage, true)
        XCTAssertEqual(summary?.isUsingCachedContextWindow, false)
    }

    func testCachedMaxSeedsConversationBeforeFirstTokenRecord() {
        let summary = ConversationUsageSummary.derive(from: [], cachedContextWindowSize: 200_000)

        XCTAssertEqual(summary?.contextUsedTokens, 0)
        XCTAssertEqual(summary?.contextWindowSize, 200_000)
        XCTAssertEqual(summary?.totalCostUsd, 0)
        XCTAssertEqual(summary?.hasReportedCost, false)
        XCTAssertEqual(summary?.hasReportedUsage, false)
        XCTAssertEqual(summary?.isUsingCachedContextWindow, true)
    }

    func testOtherEventTypesAreExcludedFromSpendAndUsage() throws {
        let events = [
            ConversationEventRecord(conversationId: "conversation-1", type: "message", role: "assistant", content: "Hi"),
            tokenRecord(input: 10, output: 20, cacheRead: 30, cacheCreation: 40, costUsd: 0.01)
        ]

        let summary = ConversationUsageSummary.derive(from: events, cachedContextWindowSize: 200_000)

        XCTAssertEqual(summary?.contextUsedTokens, 80)
        XCTAssertEqual(try XCTUnwrap(summary?.totalCostUsd), 0.01, accuracy: 0.000_001)
        XCTAssertEqual(summary?.hasReportedCost, true)
    }

    func testCodexAccountingTreatsLegacyCacheReadRowsAsCachedInputSubset() throws {
        let events = [
            tokenRecord(
                input: 62_419,
                output: 4_000,
                cacheRead: 61_312,
                cacheCreation: 0,
                costUsd: 0.01,
                contextWindowSize: 121_600
            )
        ]

        let summary = try XCTUnwrap(ConversationUsageSummary.derive(
            from: events,
            cachedContextWindowSize: nil,
            accounting: ContextTokenAccounting(providerID: "codex")
        ))

        XCTAssertEqual(summary.contextUsedTokens, 62_419)
        XCTAssertEqual(summary.contextWindowSize, 121_600)
        XCTAssertEqual(summary.contextUsagePercent, 51)
    }

    func testContextWindowInvalidationKeepsPriorUsageButDropsPriorReportedMax() throws {
        let events = [
            tokenRecord(
                input: 100,
                output: 50,
                cacheRead: 20,
                cacheCreation: 30,
                costUsd: 0.01,
                contextWindowSize: 200_000
            ),
            ConversationEventRecord(
                conversationId: "conversation-1",
                type: ConversationEventRecord.contextWindowInvalidatedType
            )
        ]

        let summary = ConversationUsageSummary.derive(from: events, cachedContextWindowSize: 1_000_000)

        XCTAssertEqual(summary?.contextUsedTokens, 150)
        XCTAssertEqual(summary?.contextWindowSize, 1_000_000)
        XCTAssertEqual(try XCTUnwrap(summary?.totalCostUsd), 0.01, accuracy: 0.000_001)
        XCTAssertEqual(summary?.hasReportedCost, true)
        XCTAssertEqual(summary?.hasReportedUsage, true)
        XCTAssertEqual(summary?.isUsingCachedContextWindow, true)
    }

    func testContextWindowInvalidationKeepsPriorUsageWhenNoCurrentMaxExists() throws {
        let events = [
            tokenRecord(
                input: 100,
                output: 50,
                cacheRead: 20,
                cacheCreation: 30,
                costUsd: 0.01,
                contextWindowSize: 200_000
            ),
            ConversationEventRecord(
                conversationId: "conversation-1",
                type: ConversationEventRecord.contextWindowInvalidatedType
            )
        ]

        let summary = try XCTUnwrap(ConversationUsageSummary.derive(from: events, cachedContextWindowSize: nil))

        XCTAssertEqual(summary.contextUsedTokens, 150)
        XCTAssertEqual(summary.contextWindowSize, 0)
        XCTAssertEqual(summary.contextUsageFraction, 0)
        XCTAssertEqual(summary.contextUsagePercent, 0)
        XCTAssertEqual(summary.totalCostUsd, 0.01, accuracy: 0.000_001)
        XCTAssertEqual(summary.hasReportedCost, true)
        XCTAssertEqual(summary.hasReportedUsage, true)
        XCTAssertEqual(summary.hasKnownContextWindowSize, false)
        XCTAssertEqual(summary.isUsingCachedContextWindow, false)
    }

    func testTokenRecordAfterContextWindowInvalidationDrivesUsageAndReportedMax() throws {
        let events = [
            tokenRecord(
                input: 100,
                output: 50,
                cacheRead: 20,
                cacheCreation: 30,
                costUsd: 0.01,
                contextWindowSize: 200_000
            ),
            ConversationEventRecord(
                conversationId: "conversation-1",
                type: ConversationEventRecord.contextWindowInvalidatedType
            ),
            tokenRecord(
                input: 200,
                output: 75,
                cacheRead: 40,
                cacheCreation: 60,
                costUsd: 0.02,
                contextWindowSize: 1_000_000
            )
        ]

        let summary = ConversationUsageSummary.derive(from: events, cachedContextWindowSize: 200_000)

        XCTAssertEqual(summary?.contextUsedTokens, 300)
        XCTAssertEqual(summary?.contextWindowSize, 1_000_000)
        XCTAssertEqual(try XCTUnwrap(summary?.totalCostUsd), 0.03, accuracy: 0.000_001)
        XCTAssertEqual(summary?.hasReportedCost, true)
        XCTAssertEqual(summary?.hasReportedUsage, true)
        XCTAssertEqual(summary?.isUsingCachedContextWindow, false)
    }

    func testNonPositiveReportedMaxFallsBackToPositiveCachedMax() throws {
        let events = [
            tokenRecord(
                input: 10,
                output: 20,
                cacheRead: 30,
                cacheCreation: 40,
                costUsd: 0.01,
                contextWindowSize: 0
            )
        ]

        let summary = try XCTUnwrap(ConversationUsageSummary.derive(from: events, cachedContextWindowSize: 200_000))

        XCTAssertEqual(summary.contextUsedTokens, 80)
        XCTAssertEqual(summary.contextWindowSize, 200_000)
        XCTAssertEqual(summary.hasKnownContextWindowSize, true)
        XCTAssertEqual(summary.isUsingCachedContextWindow, true)
    }

    func testNonPositiveReportedAndCachedMaxKeepUsageWithoutKnownContextWindow() throws {
        let events = [
            tokenRecord(
                input: 10,
                output: 20,
                cacheRead: 30,
                cacheCreation: 40,
                costUsd: 0.01,
                contextWindowSize: 0
            )
        ]

        let summary = try XCTUnwrap(ConversationUsageSummary.derive(from: events, cachedContextWindowSize: 0))

        XCTAssertEqual(summary.contextUsedTokens, 80)
        XCTAssertEqual(summary.contextWindowSize, 0)
        XCTAssertEqual(summary.hasReportedUsage, true)
        XCTAssertEqual(summary.hasKnownContextWindowSize, false)
        XCTAssertEqual(summary.isUsingCachedContextWindow, false)
    }

    func testReportedZeroCostStillCountsAsReportedCost() {
        let events = [
            tokenRecord(input: 10, output: 20, cacheRead: 30, cacheCreation: 40, costUsd: 0, costUsdReported: true)
        ]

        let summary = ConversationUsageSummary.derive(from: events, cachedContextWindowSize: 200_000)

        XCTAssertEqual(summary?.totalCostUsd, 0)
        XCTAssertEqual(summary?.hasReportedCost, true)
    }

    func testMissingCostDoesNotCountAsReportedCost() {
        let events = [
            tokenRecord(input: 10, output: 20, cacheRead: 30, cacheCreation: 40, costUsd: 0, costUsdReported: false)
        ]

        let summary = ConversationUsageSummary.derive(from: events, cachedContextWindowSize: 200_000)

        XCTAssertEqual(summary?.totalCostUsd, 0)
        XCTAssertEqual(summary?.hasReportedCost, false)
    }

    func testReturnsNilWhenNoReportedOrCachedContextWindowSizeExists() {
        XCTAssertNil(ConversationUsageSummary.derive(from: [], cachedContextWindowSize: nil))
    }

    func testReturnsNilWhenOnlyNonPositiveCachedContextWindowSizeExists() {
        XCTAssertNil(ConversationUsageSummary.derive(from: [], cachedContextWindowSize: 0))
    }

    func testUnreportedPlaceholderHasNoKnownContextWindowSize() {
        let summary = ConversationUsageSummary.unreported

        XCTAssertEqual(summary.contextUsedTokens, 0)
        XCTAssertEqual(summary.contextWindowSize, 0)
        XCTAssertEqual(summary.contextUsageFraction, 0)
        XCTAssertEqual(summary.contextUsagePercent, 0)
        XCTAssertFalse(summary.hasReportedUsage)
        XCTAssertFalse(summary.hasKnownContextWindowSize)
    }

    private func tokenRecord(
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheCreation: Int,
        costUsd: Double,
        costUsdReported: Bool = false,
        contextWindowSize: Int? = nil
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            conversationId: "conversation-1",
            type: "tokens",
            tokenInput: input,
            tokenOutput: output,
            tokenCacheRead: cacheRead,
            tokenCacheCreation: cacheCreation,
            costUsd: costUsd,
            costUsdReported: costUsdReported,
            contextWindowSize: contextWindowSize
        )
    }
}
