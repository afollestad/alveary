import AgentCLIKit
import XCTest

@testable import Alveary

final class AgentCLIKitHostToolEventMapperTests: XCTestCase {
    func testHostToolServerFailureDiagnosticDoesNotBecomeTerminalConversationError() {
        let envelope = AgentCLIKit.AgentEventEnvelope(
            generation: 1,
            index: 0,
            providerId: .claude,
            conversationId: "conversation",
            providerSessionId: nil,
            source: .runtime,
            event: .diagnostic(AgentDiagnosticEvent(
                code: .hostToolServerUnavailable,
                severity: .error,
                message: "Host tool listener stopped unexpectedly.",
                metadata: ["replacement_required": .bool(true)]
            )),
            createdAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(envelope.isHostToolServerUnavailableDiagnostic)
        XCTAssertTrue(AgentCLIKitEventMapper().conversationEvents(from: envelope).isEmpty)
    }
}
