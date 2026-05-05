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
        XCTAssertTrue(hitView is AppKitComposerAutocompleteRowView)
        XCTAssertTrue(hitView.accessibilityPerformPress())
        XCTAssertEqual(selectedID, suggestion.id)
    }

    func testNativeAutocompletePopupScrollsToHighlightedSuggestionWindow() {
        let popup = AppKitComposerAutocompletePopupView(frame: NSRect(x: 0, y: 0, width: 320, height: 292))
        let suggestions = (0..<8).map { index in
            ComposerAutocompleteSuggestion(
                id: "file-\(index)",
                title: "File \(index)",
                subtitle: nil,
                trailingText: nil,
                replacementText: "@file-\(index)",
                symbolName: "doc.text"
            )
        }
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
            onSelect: { selectedID = $0.id },
            onHighlight: { highlightedIndex = $0 }
        )
        popup.layoutSubtreeIfNeeded()

        let secondRow = try XCTUnwrap(popup.hitTest(NSPoint(x: 60, y: 74)) as? AppKitComposerAutocompleteRowView)
        secondRow.mouseEntered(with: Self.mouseEvent(type: .mouseMoved))
        secondRow.mouseDown(with: Self.mouseEvent(type: .leftMouseDown))

        XCTAssertEqual(highlightedIndex, 1)
        XCTAssertEqual(selectedID, "second")
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

    private static func mouseEvent(type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }
}

private final class AutocompleteFixedHeightView: NSView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
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
}
