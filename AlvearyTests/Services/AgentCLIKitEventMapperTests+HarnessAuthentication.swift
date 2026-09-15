import AgentCLIKit
import XCTest

@testable import Alveary

/// Covers the credential-expired diagnostic, which is the only mapping that fans one harness event
/// out into two conversation events.
extension AgentCLIKitEventMapperTests {
    func testMapsHarnessAuthenticationDiagnosticToBannerAndErrorRow() {
        let message = "Failed to authenticate: OAuth session expired and could not be refreshed"

        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .diagnostic(AgentDiagnosticEvent(
                code: .harnessAuthenticationRequired,
                severity: .error,
                message: message
            ))
        ))

        // Banner first: the state has to be set before the transcript row lands.
        XCTAssertEqual(events, [
            .harnessAuthenticationRequired(message: message),
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
