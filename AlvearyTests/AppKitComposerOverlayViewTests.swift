@preconcurrency import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitComposerOverlayViewTests: XCTestCase {
    func testOverlayHitTestsTransparentBoundsToBlockClickThrough() {
        let overlay = AppKitComposerOverlayView(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
        overlay.configure(makeOverlayConfiguration(id: "overlay"))
        let measuredHeight = overlay.measuredHeight(width: 360)
        overlay.frame.size.height = measuredHeight + 44
        overlay.layoutSubtreeIfNeeded()
        let panelView = views(in: overlay, ofType: AppKitComposerOverlayPanelView.self)[0]

        let hit = overlay.hitTest(NSPoint(x: 340, y: panelView.frame.minY / 2))

        XCTAssertTrue(hit === overlay)
    }

    func testOverlayBackingCoversBoundsWithoutPaintingBackground() throws {
        let overlay = AppKitComposerOverlayView(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
        overlay.appearance = NSAppearance(named: .darkAqua)
        overlay.configure(makeOverlayConfiguration(id: "overlay"))
        let measuredHeight = overlay.measuredHeight(width: 360)
        overlay.frame.size.height = measuredHeight + 44
        overlay.layoutSubtreeIfNeeded()

        let backingView = try XCTUnwrap(
            overlay.subviews.first { $0.identifier?.rawValue == "composer-overlay-backing" }
        )
        let panelView = try XCTUnwrap(overlay.subviews.first { $0 is AppKitComposerOverlayPanelView })

        XCTAssertEqual(backingView.frame, overlay.bounds)
        XCTAssertTrue(backingView.wantsLayer)
        XCTAssertNil(backingView.layer?.backgroundColor)
        XCTAssertTrue(overlay.subviews.first === backingView)
        XCTAssertTrue(overlay.subviews.last === panelView)
        XCTAssertTrue(overlay.hitTest(NSPoint(x: 340, y: panelView.frame.minY / 2)) === overlay)
    }

    func testComposerPanelUsesOverlayHeightWhenOverlayIsTallerThanComposer() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: makeComposerBodyConfiguration(),
                interactionOverlayConfiguration: makeOverlayConfiguration(id: "prompt", rowCount: 5),
                showsTopDivider: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )
        panel.layoutSubtreeIfNeeded()

        let overlay = try XCTUnwrap(panel.subviews.first { $0 is AppKitComposerOverlayView })
        let preferredHeight = panel.fittingSize.height
        XCTAssertFalse(overlay.isHidden)
        XCTAssertEqual(overlay.frame, panel.bounds)
        XCTAssertGreaterThan(preferredHeight, 180)
    }

    func testComposerPanelUsesOverlayHeightWhenHiddenComposerIsTaller() throws {
        let layout = AppKitChatComposerPanelView.Layout(
            horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20),
            topContentSpacing: 8,
            actionRowSpacing: 14
        )
        let body = makeComposerBodyConfiguration(text: (0..<14).map { "Line \($0)" }.joined(separator: "\n"))
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: body,
                actionRowConfiguration: makeOverlayActionRowConfiguration(),
                showsTopDivider: false,
                layout: layout
            )
        )
        panel.layoutSubtreeIfNeeded()
        let normalHeight = panel.fittingSize.height

        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: body,
                actionRowConfiguration: makeOverlayActionRowConfiguration(),
                interactionOverlayConfiguration: makeOverlayConfiguration(
                    id: "prompt",
                    density: AppKitComposerOverlayMetrics.compactDensity
                ),
                showsTopDivider: false,
                layout: layout
            )
        )
        panel.layoutSubtreeIfNeeded()
        let overlay = try XCTUnwrap(panel.subviews.first { $0 is AppKitComposerOverlayView })

        XCTAssertLessThan(panel.fittingSize.height, normalHeight)
        XCTAssertEqual(overlay.frame, panel.bounds)
        XCTAssertTrue(panel.wantsLayer)
        XCTAssertEqual(panel.layer?.masksToBounds, true)
    }

    func testCompactDensityMeasuresShorterThanRegularDensity() {
        let rows = [
            makeRowConfiguration(id: "one", title: "One"),
            makeRowConfiguration(id: "two", title: "Two")
        ]
        let regular = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 360, height: 220))
        regular.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Question",
                rows: rows,
                density: AppKitComposerOverlayMetrics.regularDensity,
                primaryTitle: "Continue",
                onDismiss: {},
                onPrimary: {}
            )
        )
        let compact = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 360, height: 220))
        compact.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Question",
                rows: rows,
                density: AppKitComposerOverlayMetrics.compactDensity,
                primaryTitle: "Continue",
                onDismiss: {},
                onPrimary: {}
            )
        )

        XCTAssertLessThan(compact.measuredHeight(width: 360), regular.measuredHeight(width: 360))
    }

    func testCompactDensityPlacesFooterInlineWithLastRow() throws {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 900, height: 180))
        let inlineDensity = AppKitComposerOverlayPanelDensity(
            panelPadding: 12,
            headerRowsSpacing: 8,
            rowSpacing: 0,
            footerSpacing: 8,
            placesFooterInlineWithLastRow: true,
            bottomClearance: 12
        )
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Implement this plan?",
                rows: [
                    makeRowConfiguration(id: "yes", title: "Yes, implement this plan"),
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "custom",
                        indexText: "2.",
                        title: "",
                        customPlaceholder: "No, and tell the agent what to do differently",
                        usesInlineCustomPlaceholder: true,
                        onSelect: {}
                    )
                ],
                density: inlineDensity,
                primaryTitle: "Submit",
                onDismiss: {},
                onPrimary: {}
            )
        )
        let measuredHeight = panel.measuredHeight(width: 900)
        panel.frame.size.height = measuredHeight
        panel.layoutSubtreeIfNeeded()

        let rows = views(in: panel, ofType: AppKitComposerOverlayOptionRowView.self)
        let lastRow = try XCTUnwrap(rows.last)
        let dismissButton = try XCTUnwrap(approvalButton(in: panel, title: "Dismiss"))
        let submitButton = try XCTUnwrap(approvalButton(in: panel, title: "Submit"))

        XCTAssertLessThan(measuredHeight, 160)
        XCTAssertEqual(dismissButton.frame.midY, lastRow.frame.midY, accuracy: 0.5)
        XCTAssertEqual(submitButton.frame.midY, lastRow.frame.midY, accuracy: 0.5)
        XCTAssertLessThan(lastRow.frame.width, rows[0].frame.width)
    }

    func testShortcutAccessoryIncreasesApprovalButtonWidth() {
        let button = AppKitTranscriptApprovalButton()
        button.title = "Dismiss"
        let plainWidth = button.preferredWidth

        button.shortcutTitle = "Esc"

        XCTAssertGreaterThan(button.preferredWidth, plainWidth)
    }

    func testDownArrowMovesFocusIntoCustomInputAndSelectsIt() throws {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        var selectedID: String?
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Implement this plan?",
                rows: [
                    makeRowConfiguration(id: "yes", title: "Yes, implement this plan"),
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
        panel.focusInitialOption()

        XCTAssertTrue(panel.handleKeyDown(makeKeyEvent(characters: "\u{F701}", keyCode: 125)))
        let customField = try XCTUnwrap(textField(in: panel, placeholder: "No, and tell the agent what to do differently"))

        XCTAssertEqual(selectedID, "custom")
        XCTAssertTrue(customField.currentEditor() === window.firstResponder)
    }

    func testInlineCustomPlaceholderCentersWithIndexBeforeFocus() throws {
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 42))
        let placeholder = "No, and tell the agent what to do differently"
        row.configure(
            AppKitComposerOverlayOptionRowView.Configuration(
                id: "custom",
                indexText: "2.",
                title: "",
                customPlaceholder: placeholder,
                fontSize: 13,
                usesInlineCustomPlaceholder: true,
                onSelect: {}
            )
        )
        row.layoutSubtreeIfNeeded()

        let indexField = try XCTUnwrap(textField(in: row, stringValue: "2."))
        let placeholderField = try XCTUnwrap(textField(in: row, stringValue: placeholder))
        let hiddenCustomInput = try XCTUnwrap(textField(in: row, placeholder: placeholder))

        XCTAssertEqual(indexField.frame.midY, row.bounds.midY, accuracy: 1)
        XCTAssertEqual(placeholderField.frame.midY, row.bounds.midY, accuracy: 1)
        XCTAssertTrue(hiddenCustomInput.isHidden)
    }

    func testSelectedChipUsesCenteredCustomView() throws {
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 360, height: 48))
        row.configure(
            AppKitComposerOverlayOptionRowView.Configuration(
                id: "one",
                indexText: "1.",
                title: "One",
                isSelected: true,
                showsSelectedChip: true,
                onSelect: {}
            )
        )
        row.layoutSubtreeIfNeeded()

        let chip = try XCTUnwrap(row.subviews.first { String(describing: type(of: $0)).contains("SelectedChip") })
        XCTAssertEqual(chip.frame.height, AppKitComposerOverlayMetrics.chipHeight)
        XCTAssertEqual(chip.frame.midY, row.bounds.midY, accuracy: 0.5)
    }

    func testTitleOnlyRowCentersIndexAndTitleVertically() throws {
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 360, height: 42))
        row.configure(
            AppKitComposerOverlayOptionRowView.Configuration(
                id: "yes",
                indexText: "1.",
                title: "Yes, implement this plan",
                onSelect: {}
            )
        )
        row.layoutSubtreeIfNeeded()

        let indexField = try XCTUnwrap(textField(in: row, stringValue: "1."))
        let titleField = try XCTUnwrap(textField(in: row, stringValue: "Yes, implement this plan"))
        XCTAssertEqual(indexField.frame.midY, row.bounds.midY, accuracy: 1)
        XCTAssertEqual(titleField.frame.midY, row.bounds.midY, accuracy: 1)
    }

    func testOverlayPanelRoutesKeyboardActions() throws {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 360, height: 220))

        var primaryCount = 0
        var dismissCount = 0
        var forwardCount = 0
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Question",
                rows: [
                    makeRowConfiguration(id: "one", title: "One"),
                    makeRowConfiguration(id: "two", title: "Two")
                ],
                pageText: "1 of 2",
                canNavigateForward: true,
                primaryTitle: "Continue",
                onNavigateForward: { forwardCount += 1 },
                onDismiss: { dismissCount += 1 },
                onPrimary: { primaryCount += 1 }
            )
        )
        panel.layoutSubtreeIfNeeded()

        XCTAssertTrue(panel.handleKeyDown(makeKeyEvent(characters: "\r", keyCode: 36)))
        XCTAssertEqual(primaryCount, 1)
        XCTAssertTrue(panel.handleKeyDown(makeKeyEvent(characters: "\u{F703}", keyCode: 124)))
        XCTAssertEqual(forwardCount, 1)
        XCTAssertTrue(panel.handleKeyDown(makeKeyEvent(characters: "\u{1B}", keyCode: 53)))
        XCTAssertEqual(dismissCount, 1)
    }
}

func makeOverlayConfiguration(
    id: String,
    rowCount: Int = 1,
    density: AppKitComposerOverlayPanelDensity = AppKitComposerOverlayMetrics.regularDensity
) -> AppKitComposerOverlayConfiguration {
    AppKitComposerOverlayConfiguration(
        id: id,
        panelConfiguration: AppKitComposerOverlayPanelView.Configuration(
            title: "Question",
            rows: (1...rowCount).map { index in
                makeRowConfiguration(id: "row-\(index)", title: "Option \(index)")
            },
            density: density,
            primaryTitle: "Continue",
            onDismiss: {},
            onPrimary: {}
        )
    )
}

func makeRowConfiguration(
    id: String,
    title: String,
    minimumHeight: CGFloat = AppKitComposerOverlayMetrics.optionMinimumHeight,
    verticalPadding: CGFloat = AppKitComposerOverlayMetrics.optionVerticalPadding,
    onSelect: @escaping () -> Void = {}
) -> AppKitComposerOverlayOptionRowView.Configuration {
    AppKitComposerOverlayOptionRowView.Configuration(
        id: id,
        indexText: "1.",
        title: title,
        minimumHeight: minimumHeight,
        verticalPadding: verticalPadding,
        onSelect: onSelect
    )
}

func makeComposerBodyConfiguration(text: String = "Panel body") -> AppKitChatComposerBodyConfiguration {
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
        loadFileCompletions: { [] },
        loadSkillCompletions: { [] },
        onSubmit: {},
        onSteer: {},
        onStop: {},
        onStopConfirmationChange: { _ in },
        onFocusRequestConsumed: { _ in }
    )
}

func makeOverlayActionRowConfiguration() -> ChatComposerActionRowView.Configuration {
    ChatComposerActionRowView.Configuration(
        reasoning: makeReasoningConfiguration(),
        supportedPermissionModes: [.init(value: "default", title: "Default")],
        selectedPermissionMode: "default",
        showWorktreePicker: false,
        selectedUseWorktree: false,
        usageSummary: nil,
        areControlsDisabled: false,
        mode: .idle,
        primaryActionTitle: "Send",
        primaryActionSystemImage: "paperplane.fill",
        isPrimaryActionDisabled: false,
        isStopConfirmationArmed: false,
        composerActionRowHeight: ChatComposerActionRowView.defaultHeight,
        onPermissionModeChange: { _ in },
        onUseWorktreeChange: { _ in },
        taskWorkspace: nil,
        voiceInput: nil,
        onSubmit: {},
        onStop: {}
    )
}

func makeKeyEvent(
    characters: String,
    keyCode: UInt16
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
    )!
}

func makeMouseEvent() -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseDown,
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

@MainActor
func views<View: NSView>(in view: NSView, ofType type: View.Type) -> [View] {
    var matches: [View] = []
    if let typedView = view as? View {
        matches.append(typedView)
    }
    for subview in view.subviews {
        matches.append(contentsOf: views(in: subview, ofType: type))
    }
    return matches
}

@MainActor
func approvalButton(in view: NSView, title: String) -> AppKitTranscriptApprovalButton? {
    views(in: view, ofType: AppKitTranscriptApprovalButton.self).first { $0.title == title }
}

@MainActor
func textField(in view: NSView, placeholder: String) -> NSTextField? {
    if let field = view as? NSTextField,
       field.placeholderString == placeholder {
        return field
    }
    for subview in view.subviews {
        if let field = textField(in: subview, placeholder: placeholder) {
            return field
        }
    }
    return nil
}

@MainActor
func textField(in view: NSView, stringValue: String) -> NSTextField? {
    if let field = view as? NSTextField,
       field.stringValue == stringValue {
        return field
    }
    for subview in view.subviews {
        if let field = textField(in: subview, stringValue: stringValue) {
            return field
        }
    }
    return nil
}
