import SwiftUI

/// Repositions the same icon, name, command, and remove controls so crossing the breakpoint never remounts a focused editor.
struct ProjectSettingsActionRowLayout: Layout {
    let isCompact: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = max(proposal.width ?? ProjectSettingsLayout.compactBreakpoint, 0)
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        guard subviews.count == 4 else { return [] }
        let buttonWidth = ActionButtonMetrics.iconButtonDiameter
        let spacing = ProjectSettingsLayout.rowSpacing
        let nameWidth: CGFloat
        let commandWidth: CGFloat
        if isCompact {
            nameWidth = max(width - 2 * (buttonWidth + spacing), 0)
            commandWidth = max(width - buttonWidth - spacing, 0)
        } else {
            let fieldWidth = max(width - 2 * buttonWidth - 3 * spacing, 0)
            nameWidth = min(fieldWidth * 0.3, 240)
            commandWidth = max(fieldWidth - nameWidth, 0)
        }
        let widths = [buttonWidth, nameWidth, commandWidth, buttonWidth]
        let sizes = zip(subviews, widths).map { subview, width in
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        }
        let topHeight = isCompact
            ? max(sizes[0].height, sizes[1].height, sizes[3].height)
            : sizes.map(\.height).max() ?? 0
        let nameX = buttonWidth + spacing
        let commandX = isCompact ? nameX : nameX + nameWidth + spacing
        let commandY = isCompact ? topHeight + spacing : topHeight - sizes[2].height
        return [
            CGRect(x: 0, y: topHeight - sizes[0].height, width: buttonWidth, height: sizes[0].height),
            CGRect(x: nameX, y: topHeight - sizes[1].height, width: nameWidth, height: sizes[1].height),
            CGRect(x: commandX, y: commandY, width: commandWidth, height: sizes[2].height),
            CGRect(x: width - buttonWidth, y: topHeight - sizes[3].height, width: buttonWidth, height: sizes[3].height)
        ]
    }
}
