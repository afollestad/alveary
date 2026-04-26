import SwiftUI

struct SettingsResponsiveControlRow<Control: View>: View {
    let title: String
    private let horizontalControlSizing: SettingsControlHorizontalSizing
    private let control: Control

    init(
        _ title: String,
        horizontalControlSizing: SettingsControlHorizontalSizing = .fillsAvailableWidth,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.horizontalControlSizing = horizontalControlSizing
        self.control = control()
    }

    var body: some View {
        SettingsResponsiveControlRowLayout(horizontalControlSizing: horizontalControlSizing) {
            Text(title)
                .accessibilityHidden(true)

            control
        }
        .frame(maxWidth: .infinity, minHeight: SettingsScreenLayout.settingsRowHeight, alignment: .leading)
    }
}

private struct SettingsResponsiveControlRowLayout: Layout {
    let horizontalControlSizing: SettingsControlHorizontalSizing

    private let spacing = SettingsScreenLayout.settingsResponsiveRowSpacing
    private let stackedSpacing = SettingsScreenLayout.settingsResponsiveStackedSpacing
    private let controlWidthFraction = SettingsScreenLayout.settingsControlWidthFraction
    private let minimumControlWidth = SettingsScreenLayout.settingsMinimumHorizontalControlWidth
    private let minimumRowHeight = SettingsScreenLayout.settingsRowHeight

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else {
            return .zero
        }

        let availableWidth = proposal.width
        let layout = rowLayout(for: availableWidth, subviews: subviews)
        switch layout {
        case .horizontal(let width, let controlWidth):
            let labelWidth = max(width - spacing - controlWidth, 0)
            let labelSize = subviews[0].sizeThatFits(ProposedViewSize(width: labelWidth, height: proposal.height))
            let controlSize = subviews[1].sizeThatFits(ProposedViewSize(width: controlWidth, height: proposal.height))
            return CGSize(
                width: width,
                height: max(minimumRowHeight, labelSize.height, controlSize.height)
            )
        case .stacked(let width):
            let labelSize = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
            let controlSize = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
            return CGSize(
                width: width,
                height: max(minimumRowHeight, labelSize.height + stackedSpacing + controlSize.height)
            )
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else {
            return
        }

        switch rowLayout(for: bounds.width, subviews: subviews) {
        case .horizontal(_, let controlWidth):
            let labelWidth = max(bounds.width - spacing - controlWidth, 0)
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: labelWidth, height: bounds.height)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.maxX, y: bounds.midY),
                anchor: .trailing,
                proposal: ProposedViewSize(width: controlWidth, height: bounds.height)
            )
        case .stacked:
            let labelSize = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let controlHeight = max(bounds.height - labelSize.height - stackedSpacing, 0)
            subviews[0].place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: labelSize.height)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + labelSize.height + stackedSpacing),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: controlHeight)
            )
        }
    }

    private func rowLayout(for proposedWidth: CGFloat?, subviews: Subviews) -> SettingsResponsiveControlRowPlacement {
        // Only real width proposals should trigger stacking; nil means SwiftUI wants an ideal size.
        guard let proposedWidth else {
            let width = idealWidth(subviews: subviews)
            let controlWidth = max(minimumControlWidth, subviews[1].sizeThatFits(.unspecified).width)
            return .horizontal(width: width, controlWidth: controlWidth)
        }

        let width = max(proposedWidth, 0)
        let preferredControlWidth = preferredHorizontalControlWidth(for: width, subviews: subviews)
        let controlWidth = max(preferredControlWidth, 0)
        let labelWidth = width - spacing - controlWidth
        let labelIdealWidth = subviews[0].sizeThatFits(.unspecified).width
        let responsiveControlWidth = width * controlWidthFraction

        if horizontalControlSizing == .intrinsicInline {
            return labelWidth > 0 ? .horizontal(width: width, controlWidth: controlWidth) : .stacked(width: width)
        }

        guard responsiveControlWidth >= minimumControlWidth,
              labelWidth >= labelIdealWidth else {
            return .stacked(width: width)
        }

        return .horizontal(width: width, controlWidth: controlWidth)
    }

    private func idealWidth(subviews: Subviews) -> CGFloat {
        let labelWidth = subviews[0].sizeThatFits(.unspecified).width
        let controlWidth = max(minimumControlWidth, subviews[1].sizeThatFits(.unspecified).width)
        return labelWidth + spacing + controlWidth
    }

    private func preferredHorizontalControlWidth(for availableWidth: CGFloat, subviews: Subviews) -> CGFloat {
        switch horizontalControlSizing {
        case .fillsAvailableWidth:
            return availableWidth * controlWidthFraction
        case .intrinsic:
            return max(minimumControlWidth, subviews[1].sizeThatFits(.unspecified).width)
        case .intrinsicInline:
            return subviews[1].sizeThatFits(.unspecified).width
        }
    }
}

private enum SettingsResponsiveControlRowPlacement {
    case horizontal(width: CGFloat, controlWidth: CGFloat)
    case stacked(width: CGFloat)
}

enum SettingsControlHorizontalSizing {
    case fillsAvailableWidth
    case intrinsic
    case intrinsicInline
}
