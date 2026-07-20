import AppKit
import SwiftUI

struct ResizableRightPane<Destination: Hashable, MainContent: View, PaneContent: View>: View {
    let destination: Destination?
    @Binding var width: CGFloat
    let onWidthCommit: (CGFloat) -> Void
    @ViewBuilder let mainContent: () -> MainContent
    @ViewBuilder let paneContent: (Destination) -> PaneContent

    var body: some View {
        GeometryReader { proxy in
            let bounds = RightPaneWidthPolicy.bounds(availableWidth: proxy.size.width)
            let effectiveWidth = RightPaneWidthPolicy.effectiveWidth(
                storedWidth: width,
                availableWidth: proxy.size.width
            )
            let effectiveWidthBinding = Binding(
                get: { effectiveWidth },
                set: { width = $0 }
            )

            HStack(spacing: 0) {
                mainContent()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .clipped()

                if let destination {
                    RightPaneResizeHandle(
                        width: effectiveWidthBinding,
                        bounds: bounds,
                        onCommit: onWidthCommit
                    )
                    .id(destination)

                    paneContent(destination)
                        .id(destination)
                        .frame(width: effectiveWidth)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: destination != nil)
    }
}

struct RightPaneResizeHandle: View {
    @Binding var width: CGFloat
    @Environment(\.displayScale) private var displayScale

    let bounds: ClosedRange<Double>
    let onCommit: (CGFloat) -> Void

    @State private var dragStartWidth: CGFloat?
    @State private var isHovering = false
    @State private var hasPushedCursor = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isHovering ? Color.accentColor : Color(nsColor: .separatorColor))
                .frame(width: 1)

            Rectangle()
                .fill(isHovering ? Color.accentColor.opacity(0.18) : Color.clear)
                .frame(width: 6)
        }
        .frame(width: RightPaneWidthPolicy.resizeHandleThickness)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("Resize right pane")
        .accessibilityValue("\(Int(width.rounded())) points")
        .accessibilityHint("Adjusts the width of the right pane")
        .accessibilityAdjustableAction { direction in
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
            isHovering = hovering
            if hovering, !hasPushedCursor {
                NSCursor.resizeLeftRight.push()
                hasPushedCursor = true
            } else if !hovering, hasPushedCursor {
                NSCursor.pop()
                hasPushedCursor = false
            }
        }
        .onDisappear {
            guard hasPushedCursor else {
                return
            }

            NSCursor.pop()
            hasPushedCursor = false
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

    private func commitAdjustedWidth(_ candidate: CGFloat) {
        let committedWidth = snappedWidth(candidate)
        width = committedWidth
        onCommit(committedWidth)
    }

    private func snappedWidth(_ candidate: CGFloat) -> CGFloat {
        let lowerBound = CGFloat(bounds.lowerBound)
        let upperBound = CGFloat(bounds.upperBound)
        let clamped = min(max(candidate, lowerBound), upperBound)
        let step = max(1 / max(displayScale, 1), 0.5)
        return (clamped / step).rounded() * step
    }
}

enum RightPaneWidthPolicy {
    static let minimumMainPaneWidth: CGFloat = 420
    static let resizeHandleThickness: CGFloat = 8
    static let accessibilityStep: CGFloat = 20

    static func effectiveWidth(storedWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let bounds = bounds(availableWidth: availableWidth)
        return min(max(storedWidth, CGFloat(bounds.lowerBound)), CGFloat(bounds.upperBound))
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
}
