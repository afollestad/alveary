#if DEBUG
@preconcurrency import AppKit

extension AppKitTranscriptPromptQuestionCardView {
    var optionRowsForTesting: [AppKitPromptOptionRowView] {
        optionRows
    }

    var firstOptionGlyphTextGapForTesting: CGFloat? {
        optionRowsForTesting.first?.glyphTextGapForTesting
    }

    var firstOptionPressedFillForTesting: CGColor? {
        optionRowsForTesting.first?.pressedBackgroundColorForTesting
    }

    var firstOptionHitTestUsesWholeRowForTesting: Bool {
        optionRowsForTesting.first?.usesWholeRowHitTargetForTesting ?? false
    }

    var firstOptionOverlayFocusableForTesting: Bool {
        optionRowsForTesting.first?.overlayFocusableForTesting ?? false
    }

    var firstOptionHeightForTesting: CGFloat? {
        optionRowsForTesting.first?.intrinsicContentSize.height
    }

    var firstOptionFrameForTesting: CGRect? {
        optionRowsForTesting.first?.frame
    }

    func setFirstOptionPressedForTesting(_ pressed: Bool) {
        optionRowsForTesting.first?.setPressedForTesting(pressed)
    }

    func clickFirstOptionRowForTesting() {
        optionRowsForTesting.first?.clickForTesting()
    }

    func cancelFirstOptionRowClickForTesting() {
        optionRowsForTesting.first?.cancelClickForTesting()
    }

    func activateFirstNativeOptionControlForTesting() {
        optionRowsForTesting.first?.activateNativeControlForTesting()
    }

    func optionHeightForTesting(label: String) -> CGFloat? {
        optionRowsForTesting.first { $0.optionLabelForTesting == label }?.intrinsicContentSize.height
    }

    var customFieldHitTargetForTesting: Bool {
        optionRowsForTesting.first { $0.customFieldHitTargetForTesting } != nil
    }
}

extension AppKitPromptOptionRowView {
    var optionLabelForTesting: String {
        configuration?.option.label ?? ""
    }

    var glyphTextGapForTesting: CGFloat {
        titleField.frame.minX - button.frame.maxX
    }

    var pressedBackgroundColorForTesting: CGColor? {
        layer?.backgroundColor
    }

    var usesWholeRowHitTargetForTesting: Bool {
        let point = NSPoint(x: max(rowButton.bounds.maxX - 1, 0), y: rowButton.bounds.midY)
        return abs(rowButton.frame.width - bounds.width) < 0.5
            && abs(rowButton.frame.height - intrinsicContentSize.height) < 0.5
            && !rowButton.isHidden
            && rowButton.hitTest(point) === rowButton
    }

    var overlayFocusableForTesting: Bool {
        rowButton.acceptsFirstResponder
    }

    var customFieldHitTargetForTesting: Bool {
        guard !customField.isHidden, let superview else {
            return false
        }
        let point = customField.convert(
            NSPoint(x: customField.bounds.midX, y: customField.bounds.midY),
            to: superview
        )
        return hitTest(point) === customField
    }

    func setPressedForTesting(_ pressed: Bool) {
        setPressed(pressed)
    }

    func clickForTesting() {
        previewToggle()
        finishTogglePreview(releasedInside: true)
    }

    func cancelClickForTesting() {
        previewToggle()
        finishTogglePreview(releasedInside: false)
    }

    func activateNativeControlForTesting() {
        button.performClick(nil)
    }
}
#endif
