import AgentCLIKit
import XCTest

@testable import Alveary

/// Covers the credential-expired diagnostic, which is the only mapping that fans one provider event
/// out into two conversation events.
extension AgentCLIKitEventMapperTests {
    func testMapsProviderAuthenticationDiagnosticToBannerAndErrorRow() {
        let message = "Failed to authenticate: OAuth session expired and could not be refreshed"

        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .diagnostic(AgentDiagnosticEvent(
                code: .providerAuthenticationRequired,
                severity: .error,
                message: message
            ))
        ))

        // Banner first: the state has to be set before the transcript row lands.
        XCTAssertEqual(events, [
            .providerAuthenticationRequired(message: message),
            .error(message: message)
        ])
    }

    func testMapsUncodedErrorDiagnosticToErrorRowOnly() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .diagnostic(AgentDiagnosticEvent(severity: .error, message: "Model refused the request"))
        ))

        XCTAssertEqual(events, [.error(message: "Model refused the request")])
    }
}
