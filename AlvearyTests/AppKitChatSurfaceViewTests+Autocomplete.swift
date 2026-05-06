@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    func testSurfaceRoutesHitTestingToFloatingAutocompletePopup() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = AutocompleteFixedHeightView(height: 80)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -56, width: 300, height: 48))
        var selectedID: String?
        let suggestion = ComposerAutocompleteSuggestion(
            id: "Alveary/Views/Input/ChatInputAutocomplete.swift",
            title: "Alveary/Views/Input/ChatInputAutocomplete.swift",
            subtitle: nil,
            trailingText: nil,
            replacementText: "@Alveary/Views/Input/ChatInputAutocomplete.swift",
            symbolName: "doc.text"
        )
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "chat",
                suggestions: [suggestion],
                isLoading: false
            ),
            onSelect: { selectedID = $0.id },
            onHighlight: { _ in }
        )
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        popup.layoutSubtreeIfNeeded()
        popup.layout()

        let popupRowPoint = popup.convert(NSPoint(x: 50, y: 20), to: surface)
        let hitView = try XCTUnwrap(surface.hitTest(popupRowPoint))
        XCTAssertFalse(hitView === content)
        XCTAssertFalse(hitView === composer)
        XCTAssertTrue(surface.routeMouseDownToComposerAutocomplete(
            at: popupRowPoint,
            event: Self.mouseEvent(type: .leftMouseDown, location: popupRowPoint)
        ))
        XCTAssertEqual(selectedID, suggestion.id)
    }

    func testSurfaceRoutesMouseMovedToFloatingAutocompletePopup() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = AutocompleteFixedHeightView(height: 80)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -102, width: 300, height: 102))
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
        var highlightedIndex: Int?
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "chat",
                suggestions: suggestions,
                highlightedIndex: 0,
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { highlightedIndex = $0 }
        )
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        popup.layoutSubtreeIfNeeded()

        let popupSecondRowPoint = popup.convert(NSPoint(x: 50, y: 74), to: surface)
        surface.updateTrackingAreas()
        let routed = surface.routeMouseMovedToComposerAutocomplete(
            at: popupSecondRowPoint,
            event: Self.mouseEvent(type: .mouseMoved, location: popupSecondRowPoint)
        )

        XCTAssertTrue(routed)
        XCTAssertEqual(highlightedIndex, 1)
    }

    func testSurfaceRoutesMouseDownToFloatingAutocompletePopup() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = AutocompleteFixedHeightView(height: 80)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -102, width: 300, height: 102))
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
        var highlightedIndex: Int?
        var selectedID: String?
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "chat",
                suggestions: suggestions,
                highlightedIndex: 0,
                isLoading: false
            ),
            onSelect: { selectedID = $0.id },
            onHighlight: { highlightedIndex = $0 }
        )
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        popup.layoutSubtreeIfNeeded()

        let popupSecondRowPoint = popup.convert(NSPoint(x: 50, y: 74), to: surface)
        let routed = surface.routeMouseDownToComposerAutocomplete(
            at: popupSecondRowPoint,
            event: Self.mouseEvent(type: .leftMouseDown, location: popupSecondRowPoint)
        )

        XCTAssertTrue(routed)
        XCTAssertEqual(highlightedIndex, 1)
        XCTAssertEqual(selectedID, "second")
    }

    func testSurfaceRoutesScrollWheelToFloatingAutocompletePopup() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = AutocompleteFixedHeightView(height: 80)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -292, width: 300, height: 292))
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
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        popup.layoutSubtreeIfNeeded()

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 0", "File 1", "File 2", "File 3", "File 4", "File 5"])

        let popupPoint = popup.convert(NSPoint(x: 150, y: 100), to: surface)
        let routed = surface.routeScrollWheelToComposerAutocomplete(
            at: popupPoint,
            event: Self.scrollEvent(deltaY: -12)
        )

        XCTAssertTrue(routed)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 1", "File 2", "File 3", "File 4", "File 5", "File 6"])
        XCTAssertTrue(popup.isScrollbarVisibleForTesting)
        XCTAssertGreaterThan(popup.scrollbarFrameForTesting.height, 0)
    }

    func testSurfaceLeavesScrollWheelForTranscriptOutsideFloatingAutocompletePopup() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 420))
        let content = AutocompleteFixedHeightView(height: 300)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -102, width: 300, height: 102))
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

        let transcriptPointAbovePopup = NSPoint(x: 150, y: 40)
        let routed = surface.routeScrollWheelToComposerAutocomplete(
            at: transcriptPointAbovePopup,
            event: Self.scrollEvent(deltaY: -12)
        )

        XCTAssertFalse(routed)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 0", "File 1", "File 2", "File 3", "File 4", "File 5"])
    }

    func testSurfaceRoutesLowerHalfEventsToFloatingAutocompletePopup() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        let content = AutocompleteFixedHeightView(height: 100)
        let composer = AutocompleteFixedHeightView(height: 60)
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: -292, width: 320, height: 292))
        let suggestions = Self.fileSuggestions(count: 8)
        var selectedID: String?
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
            onSelect: { selectedID = $0.id },
            onHighlight: { _ in }
        )
        composer.addSubview(popup)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        popup.layoutSubtreeIfNeeded()

        let surfacePoint = popup.convert(NSPoint(x: 150, y: 260), to: surface)

        let hitView = try XCTUnwrap(surface.hitTest(surfacePoint))
        XCTAssertFalse(hitView === content)
        XCTAssertFalse(hitView === composer)

        let clicked = surface.routeMouseDownToComposerAutocomplete(
            at: surfacePoint,
            event: Self.mouseEvent(type: .leftMouseDown, location: surfacePoint)
        )
        XCTAssertTrue(clicked)
        XCTAssertEqual(selectedID, "file-5")

        let scrolled = surface.routeScrollWheelToComposerAutocomplete(
            at: surfacePoint,
            event: Self.scrollEvent(deltaY: -12)
        )
        XCTAssertTrue(scrolled)
        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 1", "File 2", "File 3", "File 4", "File 5", "File 6"])
    }

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

    func testNativeAutocompletePopupScrollsToHighlightedSuggestionWindow() {
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: 0, width: 320, height: 292))
        let suggestions = Self.fileSuggestions(count: 8)
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "file",
                suggestions: suggestions,
                highlightedIndex: 7,
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { _ in }
        )

        XCTAssertEqual(popup.visibleSuggestionTitlesForTesting, ["File 2", "File 3", "File 4", "File 5", "File 6", "File 7"])
    }

    func testNativeAutocompletePopupHoverAndClickUsePointerRow() throws {
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: 0, width: 320, height: 102))
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
        var events: [String] = []
        var highlightedIndex: Int?
        var selectedID: String?
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "swift",
                suggestions: suggestions,
                highlightedIndex: 0,
                isLoading: false
            ),
            onSelect: {
                selectedID = $0.id
                events.append("select:\($0.id)")
            },
            onHighlight: {
                highlightedIndex = $0
                events.append("highlight:\($0)")
            }
        )
        popup.layoutSubtreeIfNeeded()

        let secondRow = try XCTUnwrap(popup.hitTest(NSPoint(x: 60, y: 74)) as? AppKitComposerAutocompleteRowView)
        secondRow.mouseMoved(with: Self.mouseEvent(type: .mouseMoved))
        secondRow.mouseDown(with: Self.mouseEvent(type: .leftMouseDown))

        XCTAssertEqual(highlightedIndex, 1)
        XCTAssertEqual(selectedID, "second")
        XCTAssertEqual(events, ["highlight:1", "select:second"])
    }

    func testNativeAutocompletePopupPlaceholderRowsAreVerticallyCentered() {
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: 0, width: 320, height: 48))
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "swift",
                suggestions: [],
                isLoading: true
            ),
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        popup.layoutSubtreeIfNeeded()

        var metrics = popup.placeholderLayoutMetricsForTesting
        XCTAssertEqual(metrics.loadingIndicatorMidY, metrics.popupMidY, accuracy: 0.5)
        XCTAssertEqual(metrics.loadingTextMidY, metrics.popupMidY, accuracy: 0.5)

        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .file,
                replacementOffsets: 0..<1,
                query: "swift",
                suggestions: [],
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        popup.layoutSubtreeIfNeeded()

        metrics = popup.placeholderLayoutMetricsForTesting
        XCTAssertEqual(metrics.emptyTextMidY, metrics.popupMidY, accuracy: 0.5)
    }

    func testNativeAutocompleteSkillRowPreservesTitleAndTrailingPriority() throws {
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: 0, width: 240, height: 56))
        popup.configure(
            autocomplete: ComposerAutocompleteState(
                sessionID: UUID(),
                kind: .skill,
                replacementOffsets: 0..<1,
                query: "self",
                suggestions: [
                    ComposerAutocompleteSuggestion(
                        id: "self-review-alveary",
                        title: "self-review-alveary",
                        subtitle: "Perform a detailed Alveary self review before committing changes",
                        trailingText: "afollestad/alveary",
                        replacementText: "/self-review-alveary",
                        symbolName: "shippingbox"
                    )
                ],
                isLoading: false
            ),
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        popup.layoutSubtreeIfNeeded()

        let metrics = try XCTUnwrap(popup.visibleRowLayoutMetricsForTesting.first)
        XCTAssertGreaterThan(metrics.titleWidth, 0)
        XCTAssertGreaterThan(metrics.trailingWidth, 0)
        XCTAssertLessThanOrEqual(metrics.trailingWidth, metrics.trailingIntrinsicWidth)
        XCTAssertLessThanOrEqual(metrics.trailingMaxX, 212)
        XCTAssertGreaterThanOrEqual(metrics.detailMinX, metrics.titleWidth)
    }

}
