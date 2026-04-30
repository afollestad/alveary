import AppKit
import SwiftUI

struct DiffViewerVerticalSplit<TopContent: View, BottomContent: View>: View {
    @Binding var splitFraction: CGFloat

    let bounds: ClosedRange<Double>
    let onCommit: (CGFloat) -> Void
    @ViewBuilder let top: () -> TopContent
    @ViewBuilder let bottom: () -> BottomContent

    var body: some View {
        GeometryReader { proxy in
            let contentHeight = max(proxy.size.height - DiffViewerVerticalResizeHandle.thickness, 0)
            let topSectionHeight = contentHeight * clampedSplitFraction(splitFraction)
            let bottomSectionHeight = max(contentHeight - topSectionHeight, 0)

            VStack(spacing: 0) {
                top()
                    .frame(maxWidth: .infinity)
                    .frame(height: topSectionHeight)

                DiffViewerVerticalResizeHandle(
                    splitFraction: $splitFraction,
                    totalHeight: contentHeight,
                    bounds: bounds,
                    onCommit: onCommit
                )

                bottom()
                    .frame(maxWidth: .infinity)
                    .frame(height: bottomSectionHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func clampedSplitFraction(_ candidate: CGFloat) -> CGFloat {
        let lowerBound = CGFloat(bounds.lowerBound)
        let upperBound = CGFloat(bounds.upperBound)
        return min(max(candidate, lowerBound), upperBound)
    }
}

private struct DiffViewerVerticalResizeHandle: View {
    static let thickness: CGFloat = 8

    @Binding var splitFraction: CGFloat
    @Environment(\.displayScale) private var displayScale

    let totalHeight: CGFloat
    let bounds: ClosedRange<Double>
    let onCommit: (CGFloat) -> Void

    @State private var dragStartFraction: CGFloat?
    @State private var isHovering = false
    @State private var hasPushedCursor = false

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(isHovering ? Color.accentColor : Color(nsColor: .separatorColor))
                .frame(height: 1)

            Rectangle()
                .fill(isHovering ? Color.accentColor.opacity(0.18) : Color.clear)
                .frame(height: 6)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: Self.thickness)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering, !hasPushedCursor {
                NSCursor.resizeUpDown.push()
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
            // resize handle itself shifts as the split moves.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    let startFraction = dragStartFraction ?? splitFraction
                    if dragStartFraction == nil {
                        dragStartFraction = startFraction
                    }
                    splitFraction = snappedFraction(startFraction + (value.translation.height / max(totalHeight, 1)))
                }
                .onEnded { value in
                    let startFraction = dragStartFraction ?? splitFraction
                    let committedFraction = snappedFraction(startFraction + (value.translation.height / max(totalHeight, 1)))
                    splitFraction = committedFraction
                    dragStartFraction = nil
                    onCommit(committedFraction)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Resize diff sections")
        .accessibilityHint("Drag up or down to resize the file list and diff preview.")
        .accessibilityValue("Top section \(Int((splitFraction * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let delta = CGFloat(0.05)
            let updatedFraction: CGFloat

            switch direction {
            case .increment:
                updatedFraction = snappedFraction(splitFraction + delta)
            case .decrement:
                updatedFraction = snappedFraction(splitFraction - delta)
            @unknown default:
                updatedFraction = splitFraction
            }

            splitFraction = updatedFraction
            onCommit(updatedFraction)
        }
    }

    private func snappedFraction(_ candidate: CGFloat) -> CGFloat {
        let lowerBound = CGFloat(bounds.lowerBound)
        let upperBound = CGFloat(bounds.upperBound)
        let clamped = min(max(candidate, lowerBound), upperBound)

        guard totalHeight > 0 else {
            return clamped
        }

        let pixelStep = max(1 / max(displayScale, 1), 0.5)
        let steppedHeight = ((clamped * totalHeight) / pixelStep).rounded() * pixelStep
        let steppedFraction = steppedHeight / totalHeight
        return min(max(steppedFraction, lowerBound), upperBound)
    }
}
