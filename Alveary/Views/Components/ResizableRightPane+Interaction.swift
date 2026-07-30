import AppKit
import SwiftUI

struct RightPanePresentationIdentity<Destination: Hashable>: Hashable {
    let destination: Destination
    let generation: UUID
}

enum RightPanePresentationPolicy {
    static func canResize<Destination: Hashable>(
        active: RightPanePresentationIdentity<Destination>?,
        displayed: RightPanePresentationIdentity<Destination>?,
        captured: RightPanePresentationIdentity<Destination>
    ) -> Bool {
        active == captured && displayed == captured
    }

    static func shouldTearDown<Destination: Hashable>(
        displayed: RightPanePresentationIdentity<Destination>?,
        completedDismissal: RightPanePresentationIdentity<Destination>
    ) -> Bool {
        displayed == completedDismissal
    }

    static func shouldCancelDismissal<Destination: Hashable>(
        active: RightPanePresentationIdentity<Destination>,
        pending: RightPanePresentationIdentity<Destination>?
    ) -> Bool {
        active == pending
    }
}

struct RightPaneResizeHandle: View {
    @Binding var width: CGFloat
    @Environment(\.displayScale) private var displayScale

    let bounds: ClosedRange<Double>
    let isInteractionEnabled: Bool
    let onCommit: (CGFloat) -> Void

    @State private var dragStartWidth: CGFloat?
    @State private var isHovering = false
    @State private var hasPushedCursor = false

    var body: some View {
        let showsHoverFeedback = isInteractionEnabled && isHovering

        // The divider line sits at the lane's trailing edge — flush with the
        // pane's frame — so the pane's padding is its visible inset. A centered
        // line put ~4pt of lane between the divider and the pane's content edge,
        // which made a 16pt padding read as 20pt.
        ZStack(alignment: .trailing) {
            Rectangle()
                .fill(showsHoverFeedback ? Color.accentColor.opacity(0.18) : Color.clear)
                .frame(width: 6)

            Rectangle()
                .fill(showsHoverFeedback ? Color.accentColor : Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .frame(width: RightPaneWidthPolicy.resizeHandleThickness, alignment: .trailing)
        .contentShape(Rectangle())
        .allowsHitTesting(isInteractionEnabled)
        .accessibilityElement()
        .accessibilityHidden(!isInteractionEnabled)
        .accessibilityLabel("Resize right pane")
        .accessibilityValue("\(Int(width.rounded())) points")
        .accessibilityHint("Adjusts the width of the right pane")
        .accessibilityAdjustableAction { direction in
            guard isInteractionEnabled else {
                return
            }
            switch direction {
            case .increment:
                commitAdjustedWidth(width + RightPaneWidthPolicy.accessibilityStep)
            case .decrement:
                commitAdjustedWidth(width - RightPaneWidthPolicy.accessibilityStep)
            @unknown default:
                break
            }
        }
        .onHover { hovering in
            guard isInteractionEnabled else {
                clearHoverState()
                return
            }
            isHovering = hovering
            if hovering, !hasPushedCursor {
                NSCursor.resizeLeftRight.push()
                hasPushedCursor = true
            } else if !hovering, hasPushedCursor {
                NSCursor.pop()
                hasPushedCursor = false
            }
        }
        .onChange(of: isInteractionEnabled, initial: true) { _, isEnabled in
            if !isEnabled {
                dragStartWidth = nil
                clearHoverState()
            }
        }
        .onDisappear {
            clearHoverState()
        }
        .gesture(
            // Global coordinates keep the delta stable while the handle itself moves.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    let startWidth = dragStartWidth ?? width
                    if dragStartWidth == nil {
                        dragStartWidth = startWidth
                    }
                    width = snappedWidth(startWidth - value.translation.width)
                }
                .onEnded { value in
                    let startWidth = dragStartWidth ?? width
                    let committedWidth = snappedWidth(startWidth - value.translation.width)
                    width = committedWidth
                    dragStartWidth = nil
                    onCommit(committedWidth)
                }
        )
    }

    private func clearHoverState() {
        isHovering = false
        guard hasPushedCursor else {
            return
        }

        NSCursor.pop()
        hasPushedCursor = false
    }

    private func commitAdjustedWidth(_ candidate: CGFloat) {
        let committedWidth = snappedWidth(candidate)
        width = committedWidth
        onCommit(committedWidth)
    }

    /// Whole points, not display pixels: a half-point pane width makes the
    /// AppKit-backed scroll content inside the pane pixel-align a point short of
    /// the trailing inset while non-scrolling siblings keep the exact edge.
    private func snappedWidth(_ candidate: CGFloat) -> CGFloat {
        let lowerBound = CGFloat(bounds.lowerBound)
        let upperBound = CGFloat(bounds.upperBound)
        let clamped = min(max(candidate, lowerBound), upperBound)
        return min(max(clamped.rounded(), lowerBound), upperBound)
    }
}
