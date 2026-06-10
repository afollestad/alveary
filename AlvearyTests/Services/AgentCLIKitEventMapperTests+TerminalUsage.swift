import AgentCLIKit
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testMapsTerminalNilStopUsage() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.usage(AgentUsageEvent(
            model: nil,
            inputTokens: 0,
            outputTokens: 0,
            isTerminal: true
        ))))

        guard case let .tokens(_, _, _, _, _, stopReason, _, _, _, _, _, isTerminal)? = events.first else {
            return XCTFail("Expected token event")
        }
        XCTAssertNil(stopReason)
        XCTAssertTrue(isTerminal)
    }
}
