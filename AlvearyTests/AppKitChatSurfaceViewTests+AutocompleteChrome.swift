@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    func testNativeAutocompletePopupRowScrollWheelScrollsPopupWindow() throws {
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: 0, width: 320, height: 292))
        let suggestions = Self.fileSuggestions(count: 8)
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "file",
                suggestions: suggestions,
                highlightedIndex: 0,
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        popup.layoutSubtreeIfNeeded()

        let lastVisibleRow = try XCTUnwrap(popup.hitTest(NSPoint(x: 60, y: 260)) as? AppKitComposerAutocompleteRowView)
        lastVisibleRow.scrollWheel(with: Self.scrollEvent(deltaY: -12))

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 1", "File 2", "File 3", "File 4", "File 5", "File 6"])
        XCTAssertTrue(popup.isScrollbarVisibleForTesting)

        let rowGapHitView = try XCTUnwrap(popup.hitTest(NSPoint(x: 60, y: 51)))
        XCTAssertFalse(rowGapHitView is AppKitComposerAutocompleteRowView)
        rowGapHitView.scrollWheel(with: Self.scrollEvent(deltaY: -12))

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 2", "File 3", "File 4", "File 5", "File 6", "File 7"])
    }

    func testSurfaceConsumesMouseMovedInsideFloatingAutocompletePopupChrome() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = AutocompleteFixedHeightView(height: 80)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -102, width: 300, height: 102))
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "chat",
                suggestions: [],
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { _ in XCTFail("Popup chrome hover should not highlight a row") }
        )
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        popup.layoutSubtreeIfNeeded()

        let popupChromePoint = popup.convert(NSPoint(x: 150, y: 8), to: surface)
        let routed = surface.routeMouseMovedToComposerAutocomplete(
            at: popupChromePoint,
            event: Self.mouseEvent(type: .mouseMoved, location: popupChromePoint)
        )

        XCTAssertTrue(routed)
    }

    func testNativeAutocompletePopupRowUsesVisibleAutocompleteSnapshotAfterBodyStateDismisses() throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(autocompleteChromeBodyConfiguration(text: "Review @"))
        let suggestions = [
            ComposerAutocompleteSuggestion(
                id: "first",
                title: "First.swift",
                subtitle: nil,
                trailingText: nil,
                replacementText: "@First.swift",
                symbolName: "doc.text"
            ),
            ComposerAutocompleteSuggestion(
                id: "second",
                title: "Second.swift",
                subtitle: nil,
                trailingText: nil,
                replacementText: "@Second.swift",
                symbolName: "doc.text"
            )
        ]
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 7..<8,
            query: "",
            suggestions: suggestions,
            highlightedIndex: 1,
            isLoading: false
        )
        body.configureAutocompletePopup()
        body.autocompletePopupView.frame = NSRect(x: 0, y: 0, width: 320, height: 102)
        body.autocompletePopupView.layoutSubtreeIfNeeded()

        let secondRow = try XCTUnwrap(body.autocompletePopupView.hitTest(NSPoint(x: 60, y: 74)) as? AppKitComposerAutocompleteRowView)
        body.activeAutocomplete = nil
        secondRow.mouseDown(with: Self.mouseEvent(type: .leftMouseDown))

        XCTAssertEqual(body.editorView.textViewForTesting.string, "Review @Second.swift ")
        XCTAssertNil(body.activeAutocomplete)
    }

    func testNativeAutocompletePopupMouseInsertsDotClaudeSkillPath() throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(autocompleteChromeBodyConfiguration(text: "@"))
        let suggestion = ComposerAutocompleteSuggestion(
            id: ".claude/skills/ai-rules-generated-watermark-portfolio-images",
            title: ".claude/skills/ai-rules-generated-watermark-portfolio-images",
            subtitle: nil,
            trailingText: nil,
            replacementText: "@.claude/skills/ai-rules-generated-watermark-portfolio-images",
            symbolName: "doc.text"
        )
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 0..<1,
            query: "",
            suggestions: [
                ComposerAutocompleteSuggestion(
                    id: ".alveary.json",
                    title: ".alveary.json",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@.alveary.json",
                    symbolName: "doc.text"
                ),
                suggestion
            ],
            highlightedIndex: 1,
            isLoading: false
        )
        body.configureAutocompletePopup()
        body.autocompletePopupView.frame = NSRect(x: 0, y: 0, width: 320, height: 102)
        body.autocompletePopupView.layoutSubtreeIfNeeded()

        let secondRow = try XCTUnwrap(body.autocompletePopupView.hitTest(NSPoint(x: 60, y: 74)) as? AppKitComposerAutocompleteRowView)
        secondRow.mouseDown(with: Self.mouseEvent(type: .leftMouseDown))

        XCTAssertEqual(body.editorView.textViewForTesting.string, "@.claude/skills/ai-rules-generated-watermark-portfolio-images ")
    }

    func testSurfaceHoistedAutocompleteMouseInsertsDotClaudeSkillPath() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        let window = AutocompleteChromeMouseLocationWindow(contentRect: surface.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = surface
        let content = AutocompleteFixedHeightView(height: 100)
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(autocompleteChromeBodyConfiguration(text: "@"))
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 0..<1,
            query: "",
            suggestions: dotfileAutocompleteSuggestions(),
            highlightedIndex: 1,
            isLoading: false
        )
        body.configureAutocompletePopup()
        surface.configure(contentView: content, composerView: body)
        surface.layoutSubtreeIfNeeded()
        body.autocompletePopupView.layoutSubtreeIfNeeded()

        let secondRowSurfacePoint = body.autocompletePopupView.convert(NSPoint(x: 60, y: 74), to: surface)
        window.testMouseLocationOutsideOfEventStream = surface.convert(secondRowSurfacePoint, to: nil)
        let event = AutocompleteChromeMouseDownEvent(window: window, location: window.testMouseLocationOutsideOfEventStream)
        let monitorResult = surface.dismissComposerAutocompleteIfClickOutside(event)

        XCTAssertNil(monitorResult)
        XCTAssertEqual(body.editorView.textViewForTesting.string, "@.claude/skills/ai-rules-generated-watermark-portfolio-images ")
        XCTAssertTrue(window.firstResponder === body.editorView.textViewForTesting)
    }

    func testSurfaceHoistedAutocompleteMouseUsesEventPointWhenLiveMouseLocationIsStale() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        let window = AutocompleteChromeMouseLocationWindow(contentRect: surface.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = surface
        let content = AutocompleteFixedHeightView(height: 100)
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(autocompleteChromeBodyConfiguration(text: "@"))
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 0..<1,
            query: "",
            suggestions: dotfileAutocompleteSuggestions(),
            highlightedIndex: 1,
            isLoading: false
        )
        body.configureAutocompletePopup()
        surface.configure(contentView: content, composerView: body)
        surface.layoutSubtreeIfNeeded()
        body.autocompletePopupView.layoutSubtreeIfNeeded()

        let secondRowSurfacePoint = body.autocompletePopupView.convert(NSPoint(x: 60, y: 74), to: surface)
        let staleLiveWindowPoint = surface.convert(NSPoint(x: 160, y: 20), to: nil)
        let eventWindowPoint = surface.convert(secondRowSurfacePoint, to: nil)
        window.testMouseLocationOutsideOfEventStream = staleLiveWindowPoint
        let event = AutocompleteChromeMouseDownEvent(window: window, location: eventWindowPoint)

        let monitorResult = surface.dismissComposerAutocompleteIfClickOutside(event)

        XCTAssertNil(monitorResult)
        XCTAssertEqual(body.editorView.textViewForTesting.string, "@.claude/skills/ai-rules-generated-watermark-portfolio-images ")
        XCTAssertTrue(window.firstResponder === body.editorView.textViewForTesting)
    }

    func testSurfaceHoistedAutocompleteUpdatesCaptureFrameAfterPopupGrows() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        let window = AutocompleteChromeMouseLocationWindow(contentRect: surface.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = surface
        let content = AutocompleteFixedHeightView(height: 100)
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(autocompleteChromeBodyConfiguration(text: "@"))
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 0..<1,
            query: "",
            suggestions: [],
            isLoading: true
        )
        body.configureAutocompletePopup()
        surface.configure(contentView: content, composerView: body)
        surface.layoutSubtreeIfNeeded()

        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 0..<1,
            query: "",
            suggestions: dotfileAutocompleteSuggestions(),
            highlightedIndex: 1,
            isLoading: false
        )
        body.configureAutocompletePopup()
        body.autocompletePopupView.layoutSubtreeIfNeeded()

        let secondRowSurfacePoint = body.autocompletePopupView.convert(NSPoint(x: 60, y: 74), to: surface)
        window.testMouseLocationOutsideOfEventStream = surface.convert(secondRowSurfacePoint, to: nil)
        let event = AutocompleteChromeMouseDownEvent(window: window, location: window.testMouseLocationOutsideOfEventStream)
        let captureView = try XCTUnwrap(surface.hitTest(secondRowSurfacePoint) as? AutocompleteSurfaceEventCaptureView)
        let monitorResult = surface.dismissComposerAutocompleteIfClickOutside(event)

        XCTAssertTrue(captureView.frame.contains(secondRowSurfacePoint))
        XCTAssertNil(monitorResult)
        XCTAssertEqual(body.editorView.textViewForTesting.string, "@.claude/skills/ai-rules-generated-watermark-portfolio-images ")
        XCTAssertTrue(window.firstResponder === body.editorView.textViewForTesting)
    }

    func testSurfaceHoistedAutocompleteUsesIntrinsicHeightWhenPopupFrameIsStale() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        let content = AutocompleteFixedHeightView(height: 100)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -236, width: 320, height: 48))
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "",
                suggestions: dotfileAutocompleteSuggestions(),
                highlightedIndex: 1,
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        let secondRowSurfacePoint = popup.convert(NSPoint(x: 60, y: 74), to: surface)
        let captureView = try XCTUnwrap(surface.hitTest(secondRowSurfacePoint) as? AutocompleteSurfaceEventCaptureView)

        XCTAssertTrue(captureView.frame.contains(secondRowSurfacePoint))
    }
}

private func autocompleteChromeBodyConfiguration(text: String) -> AppKitChatComposerBodyConfiguration {
    AppKitChatComposerBodyConfiguration(
        text: text,
        mode: .idle,
        defaultEnterBehavior: .queue,
        isStopConfirmationArmed: false,
        supportsMidTurnSteering: true,
        isProjectTrustBlocked: false,
        isHandoffSteeringPromptActive: false,
        isHandoffOutputPromptActive: false,
        handoffSteeringCountdown: nil,
        sendCountdown: nil,
        hasQueuedMessages: false,
        hasTopContent: false,
        workingDirectory: "/tmp/alveary",
        requestFirstResponder: nil,
        colorScheme: .dark,
        loadFileCompletions: { [] },
        loadSkillCompletions: { [] },
        onTextChange: { _ in },
        onSubmit: {},
        onSteer: {},
        onStop: {},
        onStopConfirmationChange: { _ in },
        onFocusRequestConsumed: { _ in }
    )
}

private func dotfileAutocompleteSuggestions() -> [ComposerAutocompleteSuggestion] {
    [
        ComposerAutocompleteSuggestion(
            id: ".alveary.json",
            title: ".alveary.json",
            subtitle: nil,
            trailingText: nil,
            replacementText: "@.alveary.json",
            symbolName: "doc.text"
        ),
        ComposerAutocompleteSuggestion(
            id: ".claude/skills/ai-rules-generated-watermark-portfolio-images",
            title: ".claude/skills/ai-rules-generated-watermark-portfolio-images",
            subtitle: nil,
            trailingText: nil,
            replacementText: "@.claude/skills/ai-rules-generated-watermark-portfolio-images",
            symbolName: "doc.text"
        )
    ]
}

private final class AutocompleteChromeMouseLocationWindow: NSWindow {
    var testMouseLocationOutsideOfEventStream: NSPoint = .zero

    override var mouseLocationOutsideOfEventStream: NSPoint {
        testMouseLocationOutsideOfEventStream
    }
}

private final class AutocompleteChromeMouseDownEvent: NSEvent {
    private weak var eventWindow: NSWindow?
    private let eventLocation: NSPoint

    init(window: NSWindow, location: NSPoint) {
        eventWindow = window
        eventLocation = location
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var type: NSEvent.EventType {
        .leftMouseDown
    }

    override var window: NSWindow? {
        eventWindow
    }

    override var locationInWindow: NSPoint {
        eventLocation
    }
}
