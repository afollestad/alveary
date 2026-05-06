@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    func testScrollRoutingConsumesLowerHalfEventsInsideSurfaceAutocompletePopup() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        let window = NSWindow(contentRect: surface.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = surface
        let content = AutocompleteFixedHeightView(height: 100)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -292, width: 320, height: 292))
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "file",
                suggestions: Self.fileSuggestions(count: 8),
                highlightedIndex: 0,
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        content.layoutSubtreeIfNeeded()
        popup.layoutSubtreeIfNeeded()

        let surfacePoint = popup.convert(NSPoint(x: 160, y: 260), to: surface)
        let windowPoint = surface.convert(surfacePoint, to: nil)
        let event = Self.scrollEvent(deltaY: -12)
        surface.mouseMoved(with: Self.mouseEvent(type: .mouseMoved, location: windowPoint))

        XCTAssertNil(surface.consumeScrollWheelEventIfInsideComposerAutocomplete(event, windowPoint: windowPoint))
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 1", "File 2", "File 3", "File 4", "File 5", "File 6"])
    }

    func testScrollRoutingLeavesTranscriptEventsOutsideSurfaceAutocompletePopup() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 420))
        let window = NSWindow(contentRect: surface.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = surface
        let content = AutocompleteFixedHeightView(height: 300)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -102, width: 320, height: 102))
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "file",
                suggestions: Self.fileSuggestions(count: 8),
                highlightedIndex: 0,
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        content.layoutSubtreeIfNeeded()
        popup.layoutSubtreeIfNeeded()

        let event = Self.scrollEvent(deltaY: -12)
        let windowPoint = surface.convert(NSPoint(x: 160, y: 40), to: nil)
        surface.mouseMoved(with: Self.mouseEvent(type: .mouseMoved, location: windowPoint))

        XCTAssertTrue(surface.consumeScrollWheelEventIfInsideComposerAutocomplete(event, windowPoint: windowPoint) === event)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 0", "File 1", "File 2", "File 3", "File 4", "File 5"])
    }

    func testScrollRoutingIgnoresStaleTrackedMouseLocationWhenEventPointFallsOutsideAutocompletePopup() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        let window = NSWindow(contentRect: surface.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = surface
        let content = AutocompleteFixedHeightView(height: 100)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -292, width: 320, height: 292))
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "file",
                suggestions: Self.fileSuggestions(count: 8),
                highlightedIndex: 0,
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        popup.layoutSubtreeIfNeeded()

        let popupSurfacePoint = popup.convert(NSPoint(x: 160, y: 260), to: surface)
        let popupWindowPoint = surface.convert(popupSurfacePoint, to: nil)
        surface.mouseMoved(with: Self.mouseEvent(type: .mouseMoved, location: popupWindowPoint))

        let transcriptWindowPoint = surface.convert(NSPoint(x: 160, y: 24), to: nil)
        let event = Self.scrollEvent(deltaY: -12)

        XCTAssertTrue(surface.consumeScrollWheelEventIfInsideComposerAutocomplete(event, windowPoint: transcriptWindowPoint) === event)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 0", "File 1", "File 2", "File 3", "File 4", "File 5"])
    }

    func testScrollRoutingUsesLiveMouseLocationSoTranscriptCanScrollAfterPointerLeavesAutocompletePopup() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 420))
        let window = AutocompleteMouseLocationWindow(contentRect: surface.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = surface
        let content = AutocompleteFixedHeightView(height: 300)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -292, width: 320, height: 292))
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "file",
                suggestions: Self.fileSuggestions(count: 8),
                highlightedIndex: 0,
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        popup.layoutSubtreeIfNeeded()

        let stalePopupWindowPoint = surface.convert(popup.convert(NSPoint(x: 160, y: 260), to: surface), to: nil)
        let liveTranscriptWindowPoint = surface.convert(NSPoint(x: 160, y: 24), to: nil)
        window.testMouseLocationOutsideOfEventStream = liveTranscriptWindowPoint
        let event = AutocompleteScrollWheelEvent(window: window, location: stalePopupWindowPoint, deltaY: -12)

        XCTAssertTrue(surface.consumeScrollWheelEventIfInsideComposerAutocomplete(event) === event)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 0", "File 1", "File 2", "File 3", "File 4", "File 5"])
    }

    func testSurfaceCaptureForwardsOutsidePopupWheelEventsToUnderlyingScrollView() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 420))
        let window = AutocompleteMouseLocationWindow(contentRect: surface.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = surface
        let content = AutocompleteScrollHostView(height: 300)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -292, width: 320, height: 292))
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "file",
                suggestions: Self.fileSuggestions(count: 8),
                highlightedIndex: 0,
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        popup.layoutSubtreeIfNeeded()

        let popupSurfacePoint = popup.convert(NSPoint(x: 160, y: 260), to: surface)
        let captureView = try XCTUnwrap(surface.hitTest(popupSurfacePoint) as? AutocompleteSurfaceEventCaptureView)
        let liveTranscriptWindowPoint = surface.convert(NSPoint(x: 160, y: 24), to: nil)
        window.testMouseLocationOutsideOfEventStream = liveTranscriptWindowPoint
        let stalePopupWindowPoint = surface.convert(popupSurfacePoint, to: nil)
        let event = AutocompleteScrollWheelEvent(window: window, location: stalePopupWindowPoint, deltaY: -12)

        captureView.scrollWheel(with: event)

        XCTAssertTrue(content.scrollView.didReceiveScrollWheel)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 0", "File 1", "File 2", "File 3", "File 4", "File 5"])
    }

    func testSurfaceOutsideClickMonitorUsesLiveMouseLocationForPopupRowClickAfterScroll() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 420))
        let window = AutocompleteMouseLocationWindow(contentRect: surface.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = surface
        let content = AutocompleteFixedHeightView(height: 300)
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(autocompleteClickRoutingBodyConfiguration(text: "Review @"))
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 7..<8,
            query: "",
            suggestions: Self.fileSuggestions(count: 8),
            highlightedIndex: 0,
            isLoading: false
        )
        body.configureAutocompletePopup()
        surface.configure(contentView: content, composerView: body)
        surface.layoutSubtreeIfNeeded()
        body.autocompletePopupView.layoutSubtreeIfNeeded()

        let rowPopupPoint = NSPoint(x: 160, y: 28)
        let scrolled = surface.routeScrollWheelToComposerAutocomplete(
            at: body.autocompletePopupView.convert(rowPopupPoint, to: surface),
            event: Self.scrollEvent(deltaY: -12)
        )
        XCTAssertTrue(scrolled)
        XCTAssertEqual(body.autocompletePopupView.visibleSuggestionTitlesForTesting.first, "File 1")

        let livePopupSurfacePoint = body.autocompletePopupView.convert(rowPopupPoint, to: surface)
        let event = AutocompleteMouseDownEvent(
            window: window,
            location: surface.convert(NSPoint(x: 160, y: 24), to: nil)
        )
        window.testMouseLocationOutsideOfEventStream = surface.convert(livePopupSurfacePoint, to: nil)

        _ = surface.dismissComposerAutocompleteIfClickOutside(event)

        XCTAssertNotNil(body.activeAutocomplete)

        let captureView = try XCTUnwrap(surface.hitTest(livePopupSurfacePoint) as? AutocompleteSurfaceEventCaptureView)
        captureView.mouseDown(with: event)

        XCTAssertEqual(body.editorView.textViewForTesting.string, "Review @file-1 ")
        XCTAssertNil(body.activeAutocomplete)
    }
}

private final class AutocompleteMouseLocationWindow: NSWindow {
    var testMouseLocationOutsideOfEventStream: NSPoint = .zero

    override var mouseLocationOutsideOfEventStream: NSPoint {
        testMouseLocationOutsideOfEventStream
    }
}

private final class AutocompleteScrollWheelEvent: NSEvent {
    private weak var eventWindow: NSWindow?
    private let eventLocation: NSPoint
    private let eventDeltaY: CGFloat

    init(window: NSWindow, location: NSPoint, deltaY: CGFloat) {
        eventWindow = window
        eventLocation = location
        eventDeltaY = deltaY
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var type: NSEvent.EventType {
        .scrollWheel
    }

    override var window: NSWindow? {
        eventWindow
    }

    override var locationInWindow: NSPoint {
        eventLocation
    }

    override var scrollingDeltaY: CGFloat {
        eventDeltaY
    }
}

private final class AutocompleteMouseDownEvent: NSEvent {
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

private final class AutocompleteScrollHostView: NSView {
    let scrollView = AutocompleteRecordingScrollView()
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 900))
        scrollView.documentView = document
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight)
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight)
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }
}

private final class AutocompleteRecordingScrollView: NSScrollView {
    var didReceiveScrollWheel = false

    override func scrollWheel(with event: NSEvent) {
        didReceiveScrollWheel = true
    }
}

private func autocompleteClickRoutingBodyConfiguration(text: String) -> AppKitChatComposerBodyConfiguration {
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
