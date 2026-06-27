@preconcurrency import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitComposerOverlayViewTests {
    func testComposerPanelKeepsNormalComposerMountedButHiddenBehindOverlay() throws {
        let layout = AppKitChatComposerPanelView.Layout(
            horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20),
            topContentSpacing: 8,
            actionRowSpacing: 14
        )
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        let body = makeComposerBodyConfiguration()
        let actionRow = makeOverlayActionRowConfiguration()
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: body,
                actionRowConfiguration: actionRow,
                showsTopDivider: false,
                layout: layout
            )
        )
        panel.layoutSubtreeIfNeeded()
        let editorView = try XCTUnwrap(panel.editorControllerForTesting.view)
        let actionRowView = try XCTUnwrap(panel.subviews.first { $0 is ChatComposerActionRowView })

        XCTAssertFalse(editorView.isHidden)
        XCTAssertFalse(actionRowView.isHidden)

        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: body,
                actionRowConfiguration: actionRow,
                interactionOverlayConfiguration: makeOverlayConfiguration(id: "prompt"),
                showsTopDivider: false,
                layout: layout
            )
        )
        panel.layoutSubtreeIfNeeded()

        XCTAssertTrue(panel.subviews.contains(editorView))
        XCTAssertTrue(panel.subviews.contains(actionRowView))
        XCTAssertTrue(editorView.isHidden)
        XCTAssertTrue(actionRowView.isHidden)

        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: body,
                actionRowConfiguration: actionRow,
                showsTopDivider: false,
                layout: layout
            )
        )
        panel.layoutSubtreeIfNeeded()

        XCTAssertFalse(editorView.isHidden)
        XCTAssertFalse(actionRowView.isHidden)
    }

    func testCustomInputTextCellCentersWhenFocused() throws {
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 42))
        let placeholder = "No, and tell the agent what to do differently"
        row.configure(
            AppKitComposerOverlayOptionRowView.Configuration(
                id: "custom",
                indexText: "2.",
                title: "",
                isSelected: true,
                customPlaceholder: placeholder,
                customText: "srff",
                fontSize: 13,
                usesInlineCustomPlaceholder: true,
                onSelect: {}
            )
        )
        row.layoutSubtreeIfNeeded()

        let indexField = try XCTUnwrap(textField(in: row, stringValue: "2."))
        let customField = try XCTUnwrap(textField(in: row, placeholder: placeholder))
        let drawingRect = try XCTUnwrap(customField.cell?.drawingRect(forBounds: customField.bounds))

        XCTAssertFalse(customField.isHidden)
        XCTAssertEqual(indexField.frame.midY, row.bounds.midY, accuracy: 1)
        XCTAssertEqual(customField.frame.midY, row.bounds.midY, accuracy: 1)
        XCTAssertEqual(drawingRect.midY, customField.bounds.midY, accuracy: 1)
    }

    func testOverlayKeepsCustomFieldEditorFocusAcrossReconfiguration() throws {
        let placeholder = "No, and tell the agent what to do differently"
        let overlay = AppKitComposerOverlayView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        overlay.configure(makeCustomInputOverlayConfiguration(id: "custom", placeholder: placeholder, customText: ""))
        let window = NSWindow(contentRect: overlay.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = overlay
        overlay.layoutSubtreeIfNeeded()
        let customField = try XCTUnwrap(textField(in: overlay, placeholder: placeholder))
        window.makeFirstResponder(customField)
        customField.selectText(nil)
        XCTAssertTrue(customField.currentEditor() === window.firstResponder)

        overlay.configure(makeCustomInputOverlayConfiguration(id: "custom", placeholder: placeholder, customText: "s"))
        overlay.layoutSubtreeIfNeeded()
        overlay.ensureFocusIfNeeded()

        XCTAssertTrue(customField.currentEditor() === window.firstResponder)
    }

    func testInlineCustomRowHeightDoesNotChangeWhenRevealingInput() {
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 42))
        let placeholder = "No, and tell the agent what to do differently"
        row.configure(
            AppKitComposerOverlayOptionRowView.Configuration(
                id: "custom",
                indexText: "2.",
                title: "",
                customPlaceholder: placeholder,
                fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
                fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
                minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
                verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
                customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
                usesInlineCustomPlaceholder: true,
                onSelect: {}
            )
        )
        let placeholderHeight = row.measuredHeight(width: 480)

        row.configure(
            AppKitComposerOverlayOptionRowView.Configuration(
                id: "custom",
                indexText: "2.",
                title: "",
                isSelected: true,
                customPlaceholder: placeholder,
                customText: "a",
                fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
                fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
                minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
                verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
                customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
                usesInlineCustomPlaceholder: true,
                onSelect: {}
            )
        )

        XCTAssertEqual(row.measuredHeight(width: 480), placeholderHeight, accuracy: 0.5)
        XCTAssertEqual(row.measuredHeight(width: 480), AppKitComposerOverlayMetrics.compactOptionMinimumHeight, accuracy: 0.5)
    }

    func testCompactCustomInputRowMatchesCompactFixedOptionHeight() {
        let fixedRow = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 42))
        fixedRow.configure(
            AppKitComposerOverlayOptionRowView.Configuration(
                id: "fixed",
                indexText: "1.",
                title: "New feature",
                fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
                fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
                minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
                verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
                customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
                onSelect: {}
            )
        )
        let customRow = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 42))
        customRow.configure(
            AppKitComposerOverlayOptionRowView.Configuration(
                id: "custom",
                indexText: "5.",
                title: "",
                customPlaceholder: "Write your own response.",
                fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
                fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
                minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
                verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
                customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
                onSelect: {}
            )
        )

        XCTAssertEqual(customRow.measuredHeight(width: 480), fixedRow.measuredHeight(width: 480), accuracy: 0.5)
    }

    func testInfoIconSitsNextToTitleBeforeTrailingAccessories() throws {
        let helpText = "Pick the direct path."
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 48))
        row.configure(
            AppKitComposerOverlayOptionRowView.Configuration(
                id: "direct",
                indexText: "1.",
                title: "Direct implementation",
                helpText: helpText,
                isSelected: true,
                showsSelectedChip: true,
                onSelect: {}
            )
        )
        row.layoutSubtreeIfNeeded()

        let titleField = try XCTUnwrap(textField(in: row, stringValue: "Direct implementation"))
        let infoButton = try XCTUnwrap(views(in: row, ofType: AppKitComposerOverlayInfoButton.self).first)
        let chip = try XCTUnwrap(row.subviews.first { String(describing: type(of: $0)).contains("SelectedChip") })
        let expectedIconX = titleField.frame.minX +
            ceil(titleField.attributedStringValue.size().width) +
            AppKitComposerOverlayMetrics.inlineInfoSpacing

        XCTAssertNil(infoButton.toolTip)
        XCTAssertEqual(infoButton.accessibilityHelp(), helpText)
        XCTAssertEqual(infoButton.accessibilityValue() as? String, helpText)
        XCTAssertNil(infoButton.contentTintColor)
        XCTAssertEqual(infoButton.image?.isTemplate, false)
        XCTAssertEqual(infoButton.frame.minX, expectedIconX, accuracy: 1)
        XCTAssertEqual(infoButton.frame.midY, titleField.frame.midY, accuracy: 1)
        XCTAssertLessThan(infoButton.frame.maxX, chip.frame.minX)
    }

    func testInfoPopoverPrefersRightEdgeWhenThereIsHorizontalSpace() {
        let button = AppKitComposerOverlayInfoButton(frame: NSRect(x: 20, y: 20, width: 18, height: 18))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 500, height: 200))
        window.contentView = contentView
        contentView.addSubview(button)

        let edge = button.preferredPopoverEdgeForTesting(
            contentSize: NSSize(width: 300, height: 80),
            visibleFrame: NSRect(x: 0, y: 0, width: 900, height: 700)
        )

        XCTAssertEqual(edge, .maxX)
    }

    func testInfoPopoverFallsBackBelowWhenRightEdgeIsCramped() {
        let button = AppKitComposerOverlayInfoButton(frame: NSRect(x: 20, y: 20, width: 18, height: 18))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 500, height: 200))
        window.contentView = contentView
        contentView.addSubview(button)

        let edge = button.preferredPopoverEdgeForTesting(
            contentSize: NSSize(width: 300, height: 80),
            visibleFrame: NSRect(x: 0, y: 0, width: 150, height: 700)
        )

        XCTAssertEqual(edge, .maxY)
    }

    func testInfoTooltipWindowDoesNotInterceptMouseEvents() {
        let button = AppKitComposerOverlayInfoButton(frame: NSRect(x: 20, y: 20, width: 18, height: 18))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 500, height: 200))
        window.contentView = contentView
        contentView.addSubview(button)
        button.configure(helpText: "Pick the direct path.")

        button.showTooltipForTesting()

        XCTAssertEqual(button.tooltipIgnoresMouseForTesting, true)
        button.closeHoverTooltip()
    }

    func testInfoIconKeepsStableTintWhenParentDisablesIt() throws {
        let button = AppKitHoverInfoButton(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        button.appearance = NSAppearance(named: .darkAqua)
        button.configure(helpText: "Explains the setting.")
        let expectedColor = try XCTUnwrap(
            NSColor.secondaryLabelColor
                .resolved(for: button.appKitRenderingAppearance)
                .usingColorSpace(.deviceRGB)
        )
        let enabledColor = try XCTUnwrap(button.iconColorForTesting.usingColorSpace(.deviceRGB))
        let enabledImage = try XCTUnwrap(button.image?.tiffRepresentation)

        button.isEnabled = false
        let disabledColor = try XCTUnwrap(button.iconColorForTesting.usingColorSpace(.deviceRGB))

        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.alphaValue, 1)
        XCTAssertNil(button.contentTintColor)
        XCTAssertEqual(button.image?.isTemplate, false)
        XCTAssertEqual(button.image?.tiffRepresentation, enabledImage)
        XCTAssertEqual(enabledColor.alphaComponent, expectedColor.alphaComponent, accuracy: 0.001)
        XCTAssertLessThan(enabledColor.alphaComponent, 1)
        XCTAssertEqual(disabledColor.alphaComponent, expectedColor.alphaComponent, accuracy: 0.001)
    }

    func testOverlayPanelBorderUsesSeparatorColor() throws {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Implement this plan?",
                rows: [
                    makeRowConfiguration(id: "yes", title: "Yes, implement this plan")
                ],
                primaryTitle: "Submit",
                onDismiss: {},
                onPrimary: {}
            )
        )
        let window = NSWindow(contentRect: panel.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = panel
        panel.layoutSubtreeIfNeeded()

        let backgroundView = try XCTUnwrap(panel.subviews.first { $0 is AppKitFlippedDynamicColorView })
        let borderColor = try XCTUnwrap(backgroundView.layer?.borderColor)
        let expectedColor = NSColor.separatorColor
            .resolved(for: backgroundView.appKitRenderingAppearance)
            .cgColor

        XCTAssertEqual(borderColor, expectedColor)
    }

    func testPanelOptionRowsMatchContainerLeadingGapAfterIndex() throws {
        let inlinePlaceholder = "No, and tell the agent what to do differently"
        let customPlaceholder = "Write your own response."
        let panel = makePromptOptionGapPanel(inlinePlaceholder: inlinePlaceholder, customPlaceholder: customPlaceholder)
        panel.layoutSubtreeIfNeeded()
        let rows = panel.rowViews
        XCTAssertEqual(rows.count, 4)

        try assertHelpRowSpacing(rows[0])
        try assertInlineCustomRowSpacing(rows[1], placeholder: inlinePlaceholder)
        try assertCustomInputRowSpacing(rows[2], placeholder: customPlaceholder)
        try assertSelectedCustomInputRowSpacing(rows[3], placeholder: customPlaceholder)
    }
}

@MainActor
private func makePromptOptionGapPanel(
    inlinePlaceholder: String,
    customPlaceholder: String
) -> AppKitComposerOverlayPanelView {
    let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 700, height: 220))
    panel.configure(
        AppKitComposerOverlayPanelView.Configuration(
            title: "Question",
            rows: [
                makeHelpGapRow(),
                makeInlineCustomGapRow(placeholder: inlinePlaceholder),
                makeCustomInputGapRow(indexText: "3.", placeholder: customPlaceholder, isSelected: false),
                makeCustomInputGapRow(indexText: "10.", placeholder: customPlaceholder, isSelected: true)
            ],
            primaryTitle: "Continue",
            onDismiss: {},
            onPrimary: {}
        )
    )
    return panel
}

private func makeHelpGapRow() -> AppKitComposerOverlayOptionRowView.Configuration {
    AppKitComposerOverlayOptionRowView.Configuration(
        id: "help",
        indexText: "1.",
        title: "Direct implementation",
        description: "Make the smallest focused change.",
        helpText: "Pick the direct path.",
        onSelect: {}
    )
}

private func makeInlineCustomGapRow(placeholder: String) -> AppKitComposerOverlayOptionRowView.Configuration {
    AppKitComposerOverlayOptionRowView.Configuration(
        id: "inline-custom",
        indexText: "2.",
        title: "",
        customPlaceholder: placeholder,
        usesInlineCustomPlaceholder: true,
        onSelect: {}
    )
}

private func makeCustomInputGapRow(
    indexText: String,
    placeholder: String,
    isSelected: Bool
) -> AppKitComposerOverlayOptionRowView.Configuration {
    AppKitComposerOverlayOptionRowView.Configuration(
        id: isSelected ? "selected-custom" : "custom-input",
        indexText: indexText,
        title: "",
        isSelected: isSelected,
        showsSelectedChip: isSelected,
        customPlaceholder: placeholder,
        customText: isSelected ? "Keep the selected chip clear." : "Use a smaller row slice.",
        onSelect: {}
    )
}

@MainActor
private func assertHelpRowSpacing(_ row: AppKitComposerOverlayOptionRowView) throws {
    let indexField = try XCTUnwrap(textField(in: row, stringValue: "1."))
    let titleField = try XCTUnwrap(textField(in: row, stringValue: "Direct implementation"))
    let descriptionField = try XCTUnwrap(textField(in: row, stringValue: "Make the smallest focused change."))
    XCTAssertPromptOptionGapMatchesContainerLeading(row: row, indexField: indexField, textField: titleField)
    XCTAssertEqual(descriptionField.frame.minX, titleField.frame.minX, accuracy: 0.5)

    let infoButton = try XCTUnwrap(views(in: row, ofType: AppKitComposerOverlayInfoButton.self).first)
    let expectedInfoButtonX = titleField.frame.minX +
        ceil(titleField.attributedStringValue.size().width) +
        AppKitComposerOverlayMetrics.inlineInfoSpacing
    XCTAssertEqual(infoButton.frame.minX, expectedInfoButtonX, accuracy: 0.5)
}

@MainActor
private func assertInlineCustomRowSpacing(
    _ row: AppKitComposerOverlayOptionRowView,
    placeholder: String
) throws {
    let indexField = try XCTUnwrap(textField(in: row, stringValue: "2."))
    let titleField = try XCTUnwrap(textField(in: row, stringValue: placeholder))
    XCTAssertPromptOptionGapMatchesContainerLeading(row: row, indexField: indexField, textField: titleField)
}

@MainActor
private func assertCustomInputRowSpacing(
    _ row: AppKitComposerOverlayOptionRowView,
    placeholder: String
) throws {
    let indexField = try XCTUnwrap(textField(in: row, stringValue: "3."))
    let customField = try XCTUnwrap(textField(in: row, placeholder: placeholder))
    XCTAssertPromptOptionGapMatchesContainerLeading(row: row, indexField: indexField, textField: customField)
}

@MainActor
private func assertSelectedCustomInputRowSpacing(
    _ row: AppKitComposerOverlayOptionRowView,
    placeholder: String
) throws {
    let indexField = try XCTUnwrap(textField(in: row, stringValue: "10."))
    let customField = try XCTUnwrap(textField(in: row, placeholder: placeholder))
    XCTAssertPromptOptionGapMatchesContainerLeading(row: row, indexField: indexField, textField: customField)
    XCTAssertLessThanOrEqual(customField.frame.maxX, row.selectedChipView.frame.minX - AppKitComposerOverlayMetrics.accessorySpacing)
}

@MainActor
private func XCTAssertPromptOptionGapMatchesContainerLeading(
    row: AppKitComposerOverlayOptionRowView,
    indexField: NSTextField,
    textField: NSTextField,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let indexVisibleWidth = ceil(indexField.attributedStringValue.size().width)
    let containerLeadingGap = row.frame.minX + indexField.frame.minX
    let indexToTextGap = textField.frame.minX - (indexField.frame.minX + indexVisibleWidth)
    XCTAssertEqual(indexToTextGap, containerLeadingGap, accuracy: 0.5, file: file, line: line)
}

func makeCustomInputOverlayConfiguration(
    id: String,
    placeholder: String,
    customText: String
) -> AppKitComposerOverlayConfiguration {
    AppKitComposerOverlayConfiguration(
        id: id,
        panelConfiguration: AppKitComposerOverlayPanelView.Configuration(
            title: "Question",
            rows: [
                AppKitComposerOverlayOptionRowView.Configuration(
                    id: "\(id)-custom",
                    indexText: "1.",
                    title: "",
                    isSelected: true,
                    customPlaceholder: placeholder,
                    customText: customText,
                    usesInlineCustomPlaceholder: true,
                    onSelect: {},
                    onCustomTextChanged: { _ in }
                )
            ],
            primaryTitle: "Continue",
            onDismiss: {},
            onPrimary: {}
        )
    )
}
