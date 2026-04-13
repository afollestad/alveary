import SwiftUI

struct TerminalPaneResizeHandle: View {
    static let thickness: CGFloat = 14

    @Binding var height: CGFloat
    @Environment(\.displayScale) private var displayScale

    let bounds: ClosedRange<Double>
    let onCommit: (CGFloat) -> Void

    @State private var dragStartHeight: CGFloat?
    @State private var isHovering = false
    @State private var hasPushedCursor = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isHovering ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.65))
                .frame(height: 1 / max(displayScale, 1))

            Capsule(style: .continuous)
                .fill(isHovering ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.28))
                .frame(width: 54, height: 5)
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
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    let startHeight = dragStartHeight ?? height
                    if dragStartHeight == nil {
                        dragStartHeight = startHeight
                    }
                    height = snappedHeight(startHeight - value.translation.height)
                }
                .onEnded { value in
                    let startHeight = dragStartHeight ?? height
                    let committedHeight = snappedHeight(startHeight - value.translation.height)
                    height = committedHeight
                    dragStartHeight = nil
                    onCommit(committedHeight)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Resize terminal")
        .accessibilityHint("Drag up or down to resize the terminal pane.")
        .accessibilityValue("Height \(Int(height.rounded())) points")
        .accessibilityAdjustableAction { direction in
            let delta: CGFloat = 24
            switch direction {
            case .increment:
                height = snappedHeight(height + delta)
            case .decrement:
                height = snappedHeight(height - delta)
            @unknown default:
                break
            }
            onCommit(height)
        }
    }
}

private extension TerminalPaneResizeHandle {
    func snappedHeight(_ candidate: CGFloat) -> CGFloat {
        let lowerBound = CGFloat(bounds.lowerBound)
        let upperBound = CGFloat(bounds.upperBound)
        return min(max(candidate, lowerBound), upperBound)
    }
}
