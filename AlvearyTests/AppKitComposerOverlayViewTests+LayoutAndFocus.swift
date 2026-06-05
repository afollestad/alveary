@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitComposerOverlayViewTests {
    func testOverlayHeightIncludesBottomClearanceBelowPanel() throws {
        let overlay = AppKitComposerOverlayView(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
        overlay.configure(makeOverlayConfiguration(id: "overlay", density: AppKitComposerOverlayMetrics.compactDensity))
        let measuredHeight = overlay.measuredHeight(width: 360)
        overlay.frame.size.height = measuredHeight
        overlay.layoutSubtreeIfNeeded()

        let panelView = try XCTUnwrap(overlay.subviews.first { $0 is AppKitComposerOverlayPanelView })

        XCTAssertEqual(measuredHeight, panelView.frame.height + AppKitComposerOverlayMetrics.compactDensity.bottomClearance, accuracy: 0.5)
        XCTAssertEqual(panelView.frame.maxY, overlay.bounds.maxY - AppKitComposerOverlayMetrics.compactDensity.bottomClearance, accuracy: 0.5)
        XCTAssertTrue(overlay.hitTest(NSPoint(x: 340, y: overlay.bounds.maxY - 2)) === overlay)
    }

    func testOverlayPanelBottomStaysPinnedWhenOverlayIsTallerThanMeasuredHeight() throws {
        let overlay = AppKitComposerOverlayView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        overlay.configure(makeOverlayConfiguration(id: "overlay", density: AppKitComposerOverlayMetrics.compactDensity))
        let measuredHeight = overlay.measuredHeight(width: 360)
        overlay.frame.size.height = measuredHeight + 44
        overlay.layoutSubtreeIfNeeded()

        let panelView = try XCTUnwrap(overlay.subviews.first { $0 is AppKitComposerOverlayPanelView })

        XCTAssertGreaterThan(panelView.frame.minY, 0)
        XCTAssertEqual(panelView.frame.maxY, overlay.bounds.maxY - AppKitComposerOverlayMetrics.compactDensity.bottomClearance, accuracy: 0.5)
        XCTAssertTrue(overlay.hitTest(NSPoint(x: 340, y: panelView.frame.minY / 2)) === overlay)
    }

    func testOverlayPanelBottomStaysPinnedWhenOverlayIsShorterThanMeasuredHeight() throws {
        let overlay = AppKitComposerOverlayView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        overlay.configure(makeOverlayConfiguration(id: "overlay", density: AppKitComposerOverlayMetrics.compactDensity))
        let measuredHeight = overlay.measuredHeight(width: 360)
        overlay.frame.size.height = measuredHeight - 20
        overlay.layoutSubtreeIfNeeded()

        let panelView = try XCTUnwrap(overlay.subviews.first { $0 is AppKitComposerOverlayPanelView })

        XCTAssertLessThan(panelView.frame.minY, 0)
        XCTAssertEqual(panelView.frame.maxY, overlay.bounds.maxY - AppKitComposerOverlayMetrics.compactDensity.bottomClearance, accuracy: 0.5)
    }

    func testConfiguredRowHeightCanMakeCompactPanelShorter() {
        let defaultRows = [
            makeRowConfiguration(id: "one", title: "One"),
            makeRowConfiguration(id: "two", title: "Two")
        ]
        let compactRows = [
            makeRowConfiguration(id: "one", title: "One", minimumHeight: 36, verticalPadding: 6),
            makeRowConfiguration(id: "two", title: "Two", minimumHeight: 36, verticalPadding: 6)
        ]
        let defaultPanel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 700, height: 180))
        defaultPanel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Implement this plan?",
                rows: defaultRows,
                density: AppKitComposerOverlayMetrics.compactDensity,
                primaryTitle: "Submit",
                onDismiss: {},
                onPrimary: {}
            )
        )
        let compactPanel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 700, height: 180))
        compactPanel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Implement this plan?",
                rows: compactRows,
                density: AppKitComposerOverlayMetrics.compactDensity,
                primaryTitle: "Submit",
                onDismiss: {},
                onPrimary: {}
            )
        )

        XCTAssertLessThan(compactPanel.measuredHeight(width: 700), defaultPanel.measuredHeight(width: 700))
    }

    func testOverlayDensitiesUseTighterPanelSpacing() {
        XCTAssertEqual(AppKitComposerOverlayMetrics.regularDensity.panelPadding, 9)
        XCTAssertEqual(AppKitComposerOverlayMetrics.regularDensity.topPadding, 12)
        XCTAssertEqual(AppKitComposerOverlayMetrics.regularDensity.headerRowsSpacing, 8)
        XCTAssertEqual(AppKitComposerOverlayMetrics.regularDensity.footerSpacing, 8)
        XCTAssertEqual(AppKitComposerOverlayMetrics.compactDensity.panelPadding, 6)
        XCTAssertEqual(AppKitComposerOverlayMetrics.compactDensity.topPadding, 8)
        XCTAssertEqual(AppKitComposerOverlayMetrics.compactDensity.headerRowsSpacing, 4)
        XCTAssertEqual(AppKitComposerOverlayMetrics.compactDensity.footerSpacing, 5)
    }

    func testQuestionNavigationCentersWithHeader() throws {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 520, height: 160))
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "What area of the codebase does this task touch?",
                rows: [
                    makeRowConfiguration(id: "one", title: "One")
                ],
                pageText: "1 of 3",
                canNavigateForward: true,
                primaryTitle: "Continue",
                onDismiss: {},
                onPrimary: {}
            )
        )
        let measuredHeight = panel.measuredHeight(width: 520)
        panel.frame.size.height = measuredHeight
        panel.layoutSubtreeIfNeeded()

        let titleField = try XCTUnwrap(textField(in: panel, stringValue: "What area of the codebase does this task touch?"))
        let pageField = try XCTUnwrap(textField(in: panel, stringValue: "1 of 3"))
        let expectedHeaderMidY = titleField.frame.midY

        XCTAssertEqual(panel.previousButton.frame.midY, expectedHeaderMidY, accuracy: 0.5)
        XCTAssertEqual(pageField.frame.midY, expectedHeaderMidY, accuracy: 0.5)
        XCTAssertEqual(panel.nextButton.frame.midY, expectedHeaderMidY, accuracy: 0.5)
    }

    func testComposerPanelKeepsOverlayPanelBottomPinnedWhenBoundsExceedPreferredHeight() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: makeComposerBodyConfiguration(),
                interactionOverlayConfiguration: makeOverlayConfiguration(id: "prompt", rowCount: 2),
                showsTopDivider: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )
        let preferredHeight = panel.fittingSize.height
        XCTAssertLessThan(preferredHeight, panel.bounds.height)

        panel.layoutSubtreeIfNeeded()

        let overlay = try XCTUnwrap(panel.subviews.first { $0 is AppKitComposerOverlayView })
        let overlayPanel = try XCTUnwrap(views(in: overlay, ofType: AppKitComposerOverlayPanelView.self).first)

        XCTAssertEqual(overlay.frame, panel.bounds)
        XCTAssertEqual(
            overlayPanel.frame.maxY,
            overlay.bounds.height - AppKitComposerOverlayMetrics.regularDensity.bottomClearance,
            accuracy: 0.5
        )
    }

    func testReturnShortcutSymbolCentersInBadge() throws {
        let button = AppKitTranscriptApprovalButton()
        button.title = "Continue"
        button.shortcutTitle = "↩"
        let badgeRect = NSRect(x: 0, y: 0, width: 26, height: 18)

        let symbolRect = try XCTUnwrap(button.shortcutSymbolDrawingRectForTesting(title: "↩", in: badgeRect))

        XCTAssertEqual(symbolRect.midX, badgeRect.midX, accuracy: 0.5)
        XCTAssertEqual(symbolRect.midY, badgeRect.midY, accuracy: 0.5)
        XCTAssertLessThanOrEqual(symbolRect.width, badgeRect.width)
        XCTAssertLessThanOrEqual(symbolRect.height, badgeRect.height)
    }

    func testOverlayClaimsFirstResponderWhenActive() {
        let overlay = AppKitComposerOverlayView(frame: NSRect(x: 0, y: 0, width: 360, height: 220))
        overlay.configure(makeOverlayConfiguration(id: "overlay"))
        let outside = FocusableOverlayTestView(frame: overlay.frame)
        let window = NSWindow(contentRect: overlay.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = outside
        outside.addSubview(overlay)
        window.makeFirstResponder(outside)
        overlay.layoutSubtreeIfNeeded()

        overlay.ensureFocusIfNeeded()

        let firstResponder = window.firstResponder
        XCTAssertTrue(
            firstResponder === overlay ||
                (firstResponder as? NSView)?.isDescendant(of: overlay) == true
        )
    }

    func testDownArrowUsesConfiguredFocusWhenFirstResponderIsOutsidePanel() throws {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        var selectedID: String?
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Implement this plan?",
                rows: [
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "yes",
                        indexText: "1.",
                        title: "Yes, implement this plan",
                        isFocused: true,
                        onSelect: {}
                    ),
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "custom",
                        indexText: "2.",
                        title: "",
                        customPlaceholder: "No, and tell the agent what to do differently",
                        usesInlineCustomPlaceholder: true,
                        onSelect: { selectedID = "custom" },
                        onCustomTextChanged: { _ in }
                    )
                ],
                primaryTitle: "Submit",
                onDismiss: {},
                onPrimary: {}
            )
        )
        let window = NSWindow(contentRect: panel.frame, styleMask: .borderless, backing: .buffered, defer: false)
        let outside = FocusableOverlayTestView(frame: panel.bounds)
        window.contentView = outside
        outside.addSubview(panel)
        window.makeFirstResponder(outside)
        panel.layoutSubtreeIfNeeded()

        XCTAssertTrue(panel.handleKeyDown(makeKeyEvent(characters: "\u{F701}", keyCode: 125)))
        let customField = try XCTUnwrap(textField(in: panel, placeholder: "No, and tell the agent what to do differently"))

        XCTAssertEqual(selectedID, "custom")
        XCTAssertTrue(customField.currentEditor() === window.firstResponder)
    }

    func testTabMovesFromConfiguredFocusToCustomInput() throws {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        var selectedID: String?
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Implement this plan?",
                rows: [
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "yes",
                        indexText: "1.",
                        title: "Yes, implement this plan",
                        isFocused: true,
                        onSelect: {}
                    ),
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "custom",
                        indexText: "2.",
                        title: "",
                        customPlaceholder: "No, and tell the agent what to do differently",
                        usesInlineCustomPlaceholder: true,
                        onSelect: { selectedID = "custom" },
                        onCustomTextChanged: { _ in }
                    )
                ],
                primaryTitle: "Submit",
                onDismiss: {},
                onPrimary: {}
            )
        )
        let window = NSWindow(contentRect: panel.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = panel
        panel.layoutSubtreeIfNeeded()

        XCTAssertTrue(panel.handleKeyDown(makeKeyEvent(characters: "\t", keyCode: 48)))
        let customField = try XCTUnwrap(textField(in: panel, placeholder: "No, and tell the agent what to do differently"))

        XCTAssertEqual(selectedID, "custom")
        XCTAssertTrue(customField.currentEditor() === window.firstResponder)
    }
}

private final class FocusableOverlayTestView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
