import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testMapsCachedInputTokensWithoutPersistingCacheRead() {
        let envelope = AgentCLIKit.AgentEventEnvelope(
            generation: 1,
            index: 0,
            providerId: .codex,
            conversationId: "conversation",
            providerSessionId: nil,
            source: .stdout,
            event: AgentCLIKit.AgentEvent.usage(AgentUsageEvent(
                model: "gpt-5-codex",
                inputTokens: 62_419,
                outputTokens: 2,
                cachedInputTokens: 61_312,
                cacheCreationInputTokens: 3,
                durationMs: 50,
                costUSD: 0.01,
                contextWindow: 121_600,
                stopReason: "end_turn"
            )),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope)

        XCTAssertEqual(events, [
            .tokens(
                input: 62_419,
                output: 2,
                cacheRead: 0,
                cacheCreation: 3,
                isError: false,
                stopReason: "end_turn",
                durationMs: 50,
                costUsd: 0.01,
                providerModelId: "gpt-5-codex",
                contextWindowSize: 121_600,
                permissionDenials: [],
                isTerminal: true
            )
        ])
    }
}
