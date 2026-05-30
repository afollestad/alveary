@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    func testNativeQueuedMessagesMeasureMarkdownTextAboveContext() throws {
        let message = QueuedMessage(
            text: "Queued follow-up should remain visible.",
            stagedContext: "Context block"
        )
        let view = AppKitChatQueuedMessagesView(frame: NSRect(x: 0, y: 0, width: 480, height: 100))
        view.configure(makeNativeQueuedMessagesConfiguration([message]))
        view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(firstDescendant(of: view) {
            ($0 as? NSTextView)?.string.contains("Queued follow-up") == true
        } as? NSTextView)
        let contextField = try XCTUnwrap(firstDescendant(of: view) {
            ($0 as? NSTextField)?.stringValue == "Context attached"
        } as? NSTextField)

        XCTAssertFalse(textView.isHidden)
        XCTAssertGreaterThan(textView.frame.height, 0)
        XCTAssertGreaterThan(contextField.frame.minY, textView.frame.maxY)
    }

    func testNativeQueuedMessagesWithoutContextUseCompactCenteredRows() throws {
        let compactView = AppKitChatQueuedMessagesView(frame: NSRect(x: 0, y: 0, width: 480, height: 80))
        compactView.configure(makeNativeQueuedMessagesConfiguration([
            QueuedMessage(text: "Queued follow-up", stagedContext: nil)
        ]))
        compactView.layoutSubtreeIfNeeded()

        let compactRow = try XCTUnwrap(compactView.subviews.first)
        compactRow.layoutSubtreeIfNeeded()
        let markdownView = try XCTUnwrap(firstDescendant(of: compactRow) { $0 is AppKitMarkdownView })
        let clockView = try XCTUnwrap(firstDescendant(of: compactRow) { view in
            guard let imageView = view as? NSImageView else {
                return false
            }
            return !imageView.isHidden && imageView.image != nil
        })

        let contextView = AppKitChatQueuedMessagesView(frame: NSRect(x: 0, y: 0, width: 480, height: 100))
        contextView.configure(makeNativeQueuedMessagesConfiguration([
            QueuedMessage(text: "Queued follow-up", stagedContext: "Context block")
        ]))
        contextView.layoutSubtreeIfNeeded()
        let contextRow = try XCTUnwrap(contextView.subviews.first)

        XCTAssertEqual(compactRow.frame.height, 44)
        XCTAssertLessThan(compactRow.frame.height, contextRow.frame.height)
        XCTAssertEqual(markdownView.frame.midY, clockView.frame.midY + 2, accuracy: 0.5)
    }

    func testComposerPanelQueuedMessagesUseEditorChromeColors() throws {
        let view = NSView()
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            view.appearance = NSAppearance(named: appearanceName)
            try assertQueuedMessageColor(
                appKitQueuedMessagesFillColor(in: view),
                matches: BlockInputComposerStyle.editorFillColor,
                in: view
            )
            try assertQueuedMessageColor(
                appKitQueuedMessagesBorderColor(in: view),
                matches: BlockInputComposerStyle.editorBorderColor,
                in: view
            )
        }
    }
}

@MainActor
private func makeNativeQueuedMessagesConfiguration(_ messages: [QueuedMessage]) -> AppKitChatQueuedMessagesConfiguration {
    AppKitChatQueuedMessagesConfiguration(
        queuedMessages: messages,
        supportsMidTurnSteering: true,
        isTurnActive: true,
        inFlightQueuedMessageID: nil,
        borderWidth: 1,
        onSteer: { _ in },
        onEdit: { _ in },
        onDismiss: { _ in }
    )
}

@MainActor
private func firstDescendant(of view: NSView, matching predicate: (NSView) -> Bool) -> NSView? {
    if predicate(view) {
        return view
    }
    for subview in view.subviews {
        if let match = firstDescendant(of: subview, matching: predicate) {
            return match
        }
    }
    return nil
}

@MainActor
private func assertQueuedMessageColor(
    _ actual: NSColor,
    matches expected: NSColor,
    in view: NSView,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let actualRGB = try XCTUnwrap(actual.usingColorSpace(.deviceRGB), file: file, line: line)
    let expectedRGB = try XCTUnwrap(
        expected.resolved(for: view.appKitRenderingAppearance).usingColorSpace(.deviceRGB),
        file: file,
        line: line
    )

    XCTAssertEqual(actualRGB.redComponent, expectedRGB.redComponent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actualRGB.greenComponent, expectedRGB.greenComponent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actualRGB.blueComponent, expectedRGB.blueComponent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actualRGB.alphaComponent, expectedRGB.alphaComponent, accuracy: 0.001, file: file, line: line)
}
