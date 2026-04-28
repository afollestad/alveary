import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testTokenEventSchedulesContextWindowCacheUpdateWithoutBlockingPersistencePath() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(
            .tokens(
                input: 100,
                output: 20,
                cacheRead: 30,
                cacheCreation: 40,
                isError: false,
                stopReason: "end_turn",
                durationMs: 100,
                costUsd: 0.02,
                providerModelId: "claude-sonnet-4-6",
                contextWindowSize: 200_000,
                permissionDenials: []
            )
        )

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        let tokensRecord = try XCTUnwrap(persistedEvents.first { $0.type == "tokens" })
        XCTAssertEqual(tokensRecord.contextWindowSize, 200_000)
        XCTAssertEqual(tokensRecord.providerModelId, "claude-sonnet-4-6")

        try await waitUntil("context window cache update is scheduled") {
            let updates = await fixture.contextWindowCache.updates
            return updates.contains {
                $0.providerId == "claude" &&
                    $0.selectedModel == "default" &&
                    $0.reportedModelId == "claude-sonnet-4-6" &&
                    $0.contextWindowSize == 200_000
            }
        }
    }

    func testInterimUsageTokenPersistsWithoutEndingTurn() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.turnState.beginTurn()

        fixture.viewModel.handleEvent(
            .tokens(
                input: 100,
                output: 20,
                cacheRead: 30,
                cacheCreation: 40,
                isError: false,
                stopReason: ConversationEvent.interimUsageStopReason,
                durationMs: 0,
                costUsd: 0,
                permissionDenials: []
            )
        )

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        let tokensRecord = try XCTUnwrap(persistedEvents.first { $0.type == "tokens" })
        XCTAssertEqual(tokensRecord.stopReason, ConversationEvent.interimUsageStopReason)
        XCTAssertEqual(tokensRecord.tokenInput, 100)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
        XCTAssertNil(fixture.viewModel.lastTurnError)
    }
}
