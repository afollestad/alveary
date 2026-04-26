import AppKit
import SwiftUI

struct ContentDiffViewerResizeHandle: View {
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
        .frame(width: ContentDiffViewerWidthPolicy.resizeHandleThickness)
        .contentShape(Rectangle())
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
            // Keep drag deltas in global coordinates so they stay stable while the
            // resize handle itself shifts as the diff pane width changes.
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

    private func snappedWidth(_ candidate: CGFloat) -> CGFloat {
        let lowerBound = CGFloat(bounds.lowerBound)
        let upperBound = CGFloat(bounds.upperBound)
        let clamped = min(max(candidate, lowerBound), upperBound)
        let step = max(1 / max(displayScale, 1), 0.5)
        return (clamped / step).rounded() * step
    }
}

enum ContentDiffViewerWidthPolicy {
    static let minimumMiddlePaneWidth: CGFloat = 420
    static let resizeHandleThickness: CGFloat = 8

    static func effectiveWidth(storedWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let bounds = bounds(availableWidth: availableWidth)
        return min(max(storedWidth, CGFloat(bounds.lowerBound)), CGFloat(bounds.upperBound))
    }

    static func bounds(
        availableWidth: CGFloat,
        supportedBounds: ClosedRange<Double> = AppSettings.supportedDiffViewerWidthRange
    ) -> ClosedRange<Double> {
        let maximumAvailableWidth = Double(max(
            availableWidth - minimumMiddlePaneWidth - resizeHandleThickness,
            CGFloat(supportedBounds.lowerBound)
        ))
        let upperBound = min(supportedBounds.upperBound, maximumAvailableWidth)
        return supportedBounds.lowerBound...upperBound
    }
}
