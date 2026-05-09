@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    func testComposerBodyPrimesCodeBlockHeightBeforeDeferredMeasurement() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))

        body.configure(makeComposerBodyConfiguration(text: "Test\n```\nTest"))

        XCTAssertGreaterThan(body.measuredEditorHeight, AppKitChatComposerBodyView.editorBaseHeight)
        XCTAssertEqual(body.resolvedEditorHeight, body.measuredEditorHeight, accuracy: 0.5)
    }

    func testComposerBodyLineBreakInsideCodeBlockRefreshesHeightSynchronously() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "```\n"
        var changedText: String?
        body.configure(makeComposerBodyConfiguration(text: text, onTextChange: {
            changedText = $0
        }))
        body.layoutSubtreeIfNeeded()
        let initialMeasuredHeight = body.measuredEditorHeight
        body.selectedRange = NSRange(location: (text as NSString).length, length: 0)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .return, modifiers: .shift)), .handled)

        XCTAssertEqual(changedText, "```\n\n")
        XCTAssertGreaterThan(body.measuredEditorHeight, initialMeasuredHeight)
        XCTAssertEqual(body.resolvedEditorHeight, body.measuredEditorHeight, accuracy: 0.5)
    }
}
