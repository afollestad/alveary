import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTextEditorCoordinatorTests {
    func testActiveCompletionTokenReturnsNilForStaleNSRangeAfterTextReset() {
        let token = ChatInputFieldTextSupport.activeCompletionToken(
            text: "",
            selectedRange: NSRange(location: 5, length: 0)
        )

        XCTAssertNil(token)
    }

    func testEditableSelectionOffsetsReturnNilForStaleNSRangeAfterTextReset() {
        let offsets = ChatInputFieldTextSupport.editableSelectionOffsets(
            text: "",
            selectedRange: NSRange(location: 0, length: 5)
        )

        XCTAssertNil(offsets)
    }

    func testInlineSlashCommandHintUsesNSRangeSelectionAtEndOfExactCommand() {
        let text = "/review-github-pr"
        let hint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            isInputFocused: true,
            commandHints: ["review-github-pr": "[PR URL]"]
        )

        XCTAssertEqual(hint, " [PR URL]")
    }

    func testInlineSlashCommandHintHidesForStaleNSRange() {
        let hint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: "/review-github-pr",
            selectedRange: NSRange(location: 100, length: 0),
            isInputFocused: true,
            commandHints: ["review-github-pr": "[PR URL]"]
        )

        XCTAssertNil(hint)
    }
}
