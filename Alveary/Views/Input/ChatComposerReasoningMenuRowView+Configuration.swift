import AppKit

extension ComposerReasoningMenuRowView {
    struct Configuration {
        let title: String
        let subtitle: String?
        /// Subtitles render single-line and tail-truncated by default; permission
        /// rows opt into 2 lines so descriptions stay readable at narrow widths.
        let subtitleLineLimit: Int
        let iconName: String?
        let iconRotationRadians: CGFloat
        let trailingIconName: String?
        let accessibilityLabel: String
        let isSelected: Bool
        let isEnabled: Bool
        let isWarning: Bool
        let showsFocusBackground: Bool
        let activatesWithRightArrow: Bool
        let action: () -> Void
        let cancelAction: () -> Void

        init(
            title: String,
            subtitle: String? = nil,
            subtitleLineLimit: Int = 1,
            iconName: String?,
            iconRotationRadians: CGFloat = 0,
            trailingIconName: String?,
            accessibilityLabel: String,
            isSelected: Bool,
            isEnabled: Bool,
            isWarning: Bool = false,
            showsFocusBackground: Bool = false,
            activatesWithRightArrow: Bool = true,
            action: @escaping () -> Void,
            cancelAction: @escaping () -> Void
        ) {
            self.title = title
            self.subtitle = subtitle
            self.subtitleLineLimit = subtitleLineLimit
            self.iconName = iconName
            self.iconRotationRadians = iconRotationRadians
            self.trailingIconName = trailingIconName
            self.accessibilityLabel = accessibilityLabel
            self.isSelected = isSelected
            self.isEnabled = isEnabled
            self.isWarning = isWarning
            self.showsFocusBackground = showsFocusBackground
            self.activatesWithRightArrow = activatesWithRightArrow
            self.action = action
            self.cancelAction = cancelAction
        }
    }
}

extension ComposerReasoningMenuRowView {
    /// Font/paragraph attributes shared by subtitle measurement and drawing so
    /// menu metrics can compute row heights without duplicating text styling.
    static func subtitleMeasurementAttributes(lineLimit: Int) -> [NSAttributedString.Key: Any] {
        [
            .font: ComposerReasoningMenuMetrics.subtitleFont,
            .paragraphStyle: lineLimit > 1
                ? ComposerReasoningMenuMetrics.wrappingParagraphStyle
                : ComposerReasoningMenuMetrics.truncatingParagraphStyle
        ]
    }

    static func subtitleLineHeight() -> CGFloat {
        ("Ag" as NSString).size(withAttributes: subtitleMeasurementAttributes(lineLimit: 1)).height
    }

    static func subtitleHeight(_ subtitle: String, availableWidth: CGFloat, lineLimit: Int) -> CGFloat {
        let attributes = subtitleMeasurementAttributes(lineLimit: lineLimit)
        guard lineLimit > 1 else {
            return subtitle.size(withAttributes: attributes).height
        }
        let bounded = (subtitle as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attributes
        )
        return min(ceil(bounded.height), ceil(subtitleLineHeight() * CGFloat(lineLimit)))
    }

    /// Wrap width for rows with an icon and a (possibly hidden) trailing icon
    /// slot, mirroring `titleTextRect`'s multi-line branch.
    static func stackedSubtitleAvailableWidth(rowWidth: CGFloat) -> CGFloat {
        max(
            0,
            rowWidth -
                ComposerReasoningMenuMetrics.iconTitleLeading -
                ComposerReasoningMenuMetrics.titleTrailing -
                ComposerReasoningMenuMetrics.trailingIconReservedWidth
        )
    }
}
