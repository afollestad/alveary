import SwiftUI

enum RightPaneWidthPolicy {
    static let minimumMainPaneWidth: CGFloat = 420
    static let resizeHandleThickness: CGFloat = 8
    static let accessibilityStep: CGFloat = 20
    static let presentationDuration = 0.25
    static let presentationAnimation = Animation.easeInOut(duration: presentationDuration)

    static func presentationLaneWidth(paneWidth: CGFloat, progress: CGFloat) -> CGFloat {
        (paneWidth + resizeHandleThickness) * normalizedPresentationProgress(progress)
    }

    static func presentationOffset(paneWidth: CGFloat, progress: CGFloat) -> CGFloat {
        paneWidth + resizeHandleThickness - presentationLaneWidth(paneWidth: paneWidth, progress: progress)
    }

    /// Clamps to bounds, then rounds to whole points. Fractional widths (older
    /// persisted values were snapped to half-points on Retina) make the
    /// AppKit-backed scroll content inside the pane pixel-align a point short of
    /// its trailing inset while non-scrolling siblings keep the exact edge.
    static func effectiveWidth(storedWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let bounds = bounds(availableWidth: availableWidth)
        let lowerBound = CGFloat(bounds.lowerBound)
        let upperBound = CGFloat(bounds.upperBound)
        let clamped = min(max(storedWidth, lowerBound), upperBound)
        return min(max(clamped.rounded(), lowerBound), upperBound)
    }

    static func bounds(
        availableWidth: CGFloat,
        supportedBounds: ClosedRange<Double> = AppSettings.supportedRightPaneWidthRange
    ) -> ClosedRange<Double> {
        let maximumAvailableWidth = Double(max(
            availableWidth - minimumMainPaneWidth - resizeHandleThickness,
            CGFloat(supportedBounds.lowerBound)
        ))
        let upperBound = min(supportedBounds.upperBound, maximumAvailableWidth)
        return supportedBounds.lowerBound...upperBound
    }

    private static func normalizedPresentationProgress(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }
}

struct RightPanePresentationLayout: Layout, Animatable {
    let paneWidth: CGFloat
    var presentationProgress: CGFloat

    var animatableData: CGFloat {
        get { presentationProgress }
        set { presentationProgress = newValue }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews _: Subviews,
        cache _: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        guard let mainContent = subviews.first else {
            return
        }

        let laneWidth = RightPaneWidthPolicy.presentationLaneWidth(
            paneWidth: paneWidth,
            progress: presentationProgress
        )
        let mainContentWidth = max(bounds.width - laneWidth, 0)
        mainContent.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: mainContentWidth, height: bounds.height)
        )

        guard subviews.count > 1 else {
            return
        }
        let paneOffset = RightPaneWidthPolicy.presentationOffset(
            paneWidth: paneWidth,
            progress: presentationProgress
        )
        subviews[1].place(
            at: CGPoint(
                x: bounds.maxX - paneWidth - RightPaneWidthPolicy.resizeHandleThickness + paneOffset,
                y: bounds.minY
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: paneWidth + RightPaneWidthPolicy.resizeHandleThickness,
                height: bounds.height
            )
        )
    }
}
