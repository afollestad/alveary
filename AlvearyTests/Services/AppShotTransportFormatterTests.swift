import AgentCLIKit
import XCTest

@testable import Alveary

final class AppShotTransportFormatterTests: XCTestCase {
    func testOpenCodeAppShotUsesNativeImageAndKeepsVisibleMessageClean() throws {
        let root = URL(fileURLWithPath: "/tmp/appshot-fixture")
        let image = LocalImageAttachment(id: "image", fileURL: root.appendingPathComponent("window.png"), label: "Window", createdAt: Date())
        let appShot = AppShotAttachment(
            appName: "Preview", bundleIdentifier: "com.apple.Preview", windowTitle: "Document", screenshot: image,
            axTreeText: "Document content", focusedElementSummary: "Search field", attachmentStoreRoot: root
        )
        let message = try OutboundMessageText(visibleText: "Explain this window").resolvingAppShots([appShot], harnessID: "opencode")
        XCTAssertEqual(message.visibleText, "Explain this window")
        XCTAssertEqual(message.attachments, [image])
        XCTAssertEqual(message.consumedAppShots, [appShot])
        XCTAssertNil(message.harnessMetadata[CodexInputMetadata.isAppshot])
        let transport = try XCTUnwrap(message.transportText)
        XCTAssertTrue(transport.contains("Document content"))
        XCTAssertTrue(transport.contains("## My request for OpenCode:\nExplain this window"))
        XCTAssertFalse(transport.contains("![Appshot screenshot]"))
        XCTAssertTrue(AppShotTransportFormatter.debugPreview(userInput: "Explain", appShots: [appShot], strategy: .opencode)
            .contains("Harness mode: OpenCode localImage"))
    }
}
