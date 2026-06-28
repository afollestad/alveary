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

    func testNativeQueuedMessagesNeverRenderProviderTransportText() throws {
        let message = QueuedMessage(
            text: "Visible queued feedback",
            stagedContext: nil,
            transportText: "Hidden provider-only revision guidance"
        )
        let view = AppKitChatQueuedMessagesView(frame: NSRect(x: 0, y: 0, width: 480, height: 80))
        view.configure(makeNativeQueuedMessagesConfiguration([message]))
        view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(firstDescendant(of: view) {
            ($0 as? NSTextView)?.string.contains("Visible queued feedback") == true
        })
        XCTAssertNil(firstDescendant(of: view) {
            ($0 as? NSTextView)?.string.contains("Hidden provider-only revision guidance") == true
        })
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

    func testNativeQueuedMessagesForwardMarkdownImageOpens() throws {
        let message = QueuedMessage(text: "![Queued image](images/queued.png)", stagedContext: nil)
        let baseURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let view = AppKitChatQueuedMessagesView(frame: NSRect(x: 0, y: 0, width: 480, height: 140))
        var openedSource: String?
        var openedBaseURL: URL?
        view.configure(
            AppKitChatQueuedMessagesConfiguration(
                queuedMessages: [message],
                supportsMidTurnSteering: true,
                isTurnActive: true,
                inFlightQueuedMessageID: nil,
                borderWidth: 1,
                markdownBaseURL: baseURL,
                onOpenMarkdownImage: { image, baseURL in
                    openedSource = image.source
                    openedBaseURL = baseURL
                },
                onSteer: { _ in },
                onEdit: { _ in },
                onDismiss: { _ in }
            )
        )
        view.layoutSubtreeIfNeeded()

        let imageView = try XCTUnwrap(firstDescendant(of: view) { $0 is AppKitMarkdownImageBlockView } as? AppKitMarkdownImageBlockView)
        XCTAssertTrue(imageView.performOpenForTesting())
        XCTAssertEqual(openedSource, "images/queued.png")
        XCTAssertEqual(openedBaseURL, baseURL)
    }

    func testNativeQueuedMessagesDisableSteerWhenTurnIsNotSteerable() throws {
        let message = QueuedMessage(text: "Queued follow-up", stagedContext: nil)
        let view = AppKitChatQueuedMessagesView(frame: NSRect(x: 0, y: 0, width: 480, height: 80))
        var didSteer = false
        var didEdit = false
        var didDismiss = false
        view.configure(
            AppKitChatQueuedMessagesConfiguration(
                queuedMessages: [message],
                supportsMidTurnSteering: true,
                isTurnActive: false,
                inFlightQueuedMessageID: nil,
                borderWidth: 1,
                onSteer: { _ in didSteer = true },
                onEdit: { _ in didEdit = true },
                onDismiss: { _ in didDismiss = true }
            )
        )
        view.layoutSubtreeIfNeeded()

        let steerButton = try XCTUnwrap(firstDescendant(of: view) { $0.accessibilityLabel() == "Steer queued message" })
        let editButton = try XCTUnwrap(firstDescendant(of: view) { $0.accessibilityLabel() == "Edit queued message" })
        let dismissButton = try XCTUnwrap(firstDescendant(of: view) { $0.accessibilityLabel() == "Discard queued message" })
        XCTAssertFalse(steerButton.accessibilityPerformPress())
        XCTAssertTrue(editButton.accessibilityPerformPress())
        XCTAssertTrue(dismissButton.accessibilityPerformPress())
        XCTAssertFalse(didSteer)
        XCTAssertTrue(didEdit)
        XCTAssertTrue(didDismiss)
    }

    func testNativeQueuedMessagesRenderPauseHeaderAndResumeAction() throws {
        let message = QueuedMessage(text: "Queued follow-up", stagedContext: nil)
        let view = AppKitChatQueuedMessagesView(frame: NSRect(x: 0, y: 0, width: 480, height: 120))
        var resumeCount = 0
        view.configure(
            AppKitChatQueuedMessagesConfiguration(
                queuedMessages: [message],
                supportsMidTurnSteering: true,
                isTurnActive: true,
                inFlightQueuedMessageID: nil,
                borderWidth: 1,
                pauseHeaderTitle: "Queue paused because you interrupted",
                onResume: { resumeCount += 1 },
                onSteer: { _ in },
                onEdit: { _ in },
                onDismiss: { _ in }
            )
        )
        view.layoutSubtreeIfNeeded()

        let header = try XCTUnwrap(firstDescendant(of: view) {
            ($0 as? NSTextField)?.stringValue == "Queue paused because you interrupted"
        } as? NSTextField)
        let resumeButton = try XCTUnwrap(firstDescendant(of: view) { $0.accessibilityLabel() == "Resume" })
        let rowView = try XCTUnwrap(view.subviews.first { subview in
            firstDescendant(of: subview) {
                ($0 as? NSTextView)?.string.contains("Queued follow-up") == true
            } != nil
        })
        let headerContainer = try XCTUnwrap(header.superview)
        let resumeControl = try XCTUnwrap(resumeButton as? NSButton)
        let dismissButton = try XCTUnwrap(firstDescendant(of: rowView) {
            $0.accessibilityLabel() == "Discard queued message"
        })

        XCTAssertGreaterThanOrEqual(rowView.frame.minY, headerContainer.frame.maxY)
        XCTAssertEqual(resumeControl.frame.maxX, dismissButton.frame.maxX, accuracy: 0.5)
        XCTAssertTrue(resumeButton.accessibilityPerformPress())
        XCTAssertEqual(resumeCount, 1)
        XCTAssertTrue(resumeButton.acceptsFirstResponder)
        XCTAssertTrue(resumeButton.becomeFirstResponder())

        resumeButton.keyDown(with: queuedMessageKeyEvent(characters: "\r", keyCode: 36))
        XCTAssertEqual(resumeCount, 2)

        let mouseLocation = NSPoint(x: 8, y: 8)
        resumeControl.mouseDown(with: queuedMessageMouseEvent(type: .leftMouseDown, at: mouseLocation))
        resumeControl.mouseUp(with: queuedMessageMouseEvent(type: .leftMouseUp, at: mouseLocation))
        XCTAssertEqual(resumeCount, 3)
    }

    func testNativeQueuedMessagesPauseHeaderContributesMeasuredHeightOnlyWhenPresent() throws {
        let message = QueuedMessage(text: "Queued follow-up", stagedContext: nil)
        let unpausedView = AppKitChatQueuedMessagesView(frame: NSRect(x: 0, y: 0, width: 480, height: 80))
        unpausedView.configure(makeNativeQueuedMessagesConfiguration([message]))
        let unpausedHeight = unpausedView.measuredHeight(width: 480)

        let pausedView = AppKitChatQueuedMessagesView(frame: NSRect(x: 0, y: 0, width: 480, height: 120))
        pausedView.configure(
            AppKitChatQueuedMessagesConfiguration(
                queuedMessages: [message],
                supportsMidTurnSteering: true,
                isTurnActive: true,
                inFlightQueuedMessageID: nil,
                borderWidth: 1,
                pauseHeaderTitle: "Queue paused because you interrupted",
                onSteer: { _ in },
                onEdit: { _ in },
                onDismiss: { _ in }
            )
        )

        XCTAssertNil(firstDescendant(of: unpausedView) {
            ($0 as? NSTextField)?.stringValue == "Queue paused because you interrupted"
        })
        XCTAssertEqual(pausedView.measuredHeight(width: 480), unpausedHeight + 44, accuracy: 0.5)
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
