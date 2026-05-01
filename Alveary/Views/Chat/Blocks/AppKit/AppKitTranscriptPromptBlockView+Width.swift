@preconcurrency import AppKit
import Foundation

@MainActor
func appKitPromptIdealQuestionCardWidth(
    for questions: [PromptEntry.PromptQuestion],
    typography: TranscriptTypography,
    maxWidth: CGFloat
) -> CGFloat {
    let widths = questions.map { question in
        appKitPromptQuestionWidth(question, typography: typography) + (promptQuestionCardPadding * 2)
    }
    return min(max(widths.max() ?? appKitPromptMinimumWidth, appKitPromptMinimumWidth), maxWidth)
}

@MainActor
private func appKitPromptQuestionWidth(_ question: PromptEntry.PromptQuestion, typography: TranscriptTypography) -> CGFloat {
    let headerWidth = question.header.map { appKitPromptStringWidth($0, font: typography.nsFont(.caption, weight: .semibold)) + 16 } ?? 0
    let questionWidth = appKitPromptStringWidth(question.question, font: typography.nsFont(.subheadline, weight: .semibold))
    let optionWidths = question.renderedOptions.map { option in
        let labelWidth = appKitPromptStringWidth(option.label, font: typography.nsFont(.subheadline, weight: .medium))
        let descriptionWidth = appKitPromptStringWidth(option.description, font: typography.nsFont(.caption))
        return 32 + max(labelWidth, descriptionWidth)
    }
    return max(headerWidth, questionWidth, optionWidths.max() ?? 0)
}

@MainActor
func appKitPromptStringWidth(_ value: String, font: NSFont) -> CGFloat {
    let field = NSTextField(labelWithString: value)
    field.font = font
    // NSTextField labels reserve a small amount of cell space beyond raw glyph
    // bounds. Measuring that same control avoids orphaning the final word even
    // when the prompt bubble still has room to grow.
    return ceil(field.fittingSize.width)
}

@MainActor
func appKitPromptWrappedTextHeight(for field: NSTextField, width: CGFloat) -> CGFloat {
    guard width > 0 else {
        return ceil(field.fittingSize.height)
    }
    // `sizeToFit()` measures the natural single-line width first; forcing a
    // narrower width afterward clips prompt text instead of wrapping.
    let bounds = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
    let cellHeight = field.cell?.cellSize(forBounds: bounds).height ?? 0
    let rect = field.attributedStringValue.boundingRect(
        with: bounds.size,
        options: [.usesLineFragmentOrigin, .usesFontLeading, .usesDeviceMetrics]
    )
    return ceil(max(cellHeight, rect.height))
}

@MainActor
func appKitPromptWrappedTextHeight(_ value: String, font: NSFont, width: CGFloat) -> CGFloat {
    let field = NSTextField(labelWithString: value)
    field.lineBreakMode = .byWordWrapping
    field.maximumNumberOfLines = 0
    field.font = font
    return appKitPromptWrappedTextHeight(for: field, width: width)
}
