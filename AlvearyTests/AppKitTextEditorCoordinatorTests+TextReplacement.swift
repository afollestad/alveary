import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTextEditorCoordinatorTests {
    func testReplacingTextClampsStaleOffsetsBeforeCheckingLeadingSpace() {
        let (newText, insertionOffset) = ChatInputFieldTextSupport.replacingText(
            in: "hello",
            offsets: 999..<999,
            with: "@file",
            appendTrailingSpace: true,
            ensureLeadingSpace: true
        )

        XCTAssertEqual(newText, "hello @file ")
        XCTAssertEqual(insertionOffset, 12)
    }
}
