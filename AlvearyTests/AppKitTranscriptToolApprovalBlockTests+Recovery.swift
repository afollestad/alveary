import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolApprovalBlockTests {
    func testFactoryDisablesApprovalActionsDuringTranscriptRecovery() throws {
        let factory = AppKitTranscriptRowFactory()
        let request = ToolApprovalRequest(sessionId: "session", toolUseId: "tool", toolName: "Bash", toolInput: #"{"command":"date"}"#)
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.isRestoringToolApproval = true
        let rows = factory.approvalRows(id: "approval", approvals: [request], persistedStatus: .pending, configuration: configuration)
        let block = try XCTUnwrap(rows.first?.view as? AppKitTranscriptToolApprovalBlockView)
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.layoutSubtreeIfNeeded()
        let denyButton = try XCTUnwrap(approvalRecoveryDescendants(in: block, of: NSButton.self).first { $0.title == "Deny" })
        let approveControl = try XCTUnwrap(approvalRecoveryDescendants(in: block, of: NSSegmentedControl.self).first)
        XCTAssertFalse(denyButton.isEnabled)
        XCTAssertFalse(approveControl.isEnabled)

        configuration.isRestoringToolApproval = false
        _ = factory.approvalRows(id: "approval", approvals: [request], persistedStatus: .pending, configuration: configuration)
        XCTAssertTrue(denyButton.isEnabled)
        XCTAssertTrue(approveControl.isEnabled)
    }

}

@MainActor
private func approvalRecoveryDescendants<View: NSView>(in root: NSView, of type: View.Type) -> [View] {
    root.subviews.flatMap { child in
        (child as? View).map { [$0] } ?? []
    } + root.subviews.flatMap { approvalRecoveryDescendants(in: $0, of: type) }
}
