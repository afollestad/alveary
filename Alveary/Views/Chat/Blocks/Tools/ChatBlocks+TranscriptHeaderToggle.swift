import AppKit
import SwiftUI

struct TranscriptHeaderToggle<Label: View>: View {
    let action: () -> Void
    let label: Label
    @State private var isPressed = false

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .opacity(isPressed ? transcriptToolPressedOpacity : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            TranscriptHeaderMouseTarget(
                action: action,
                pressedChanged: { isPressed = $0 }
            )
                .accessibilityHidden(true)
        }
        .zIndex(1)
        .accessibilityElement(children: .combine)
    }
}

/// Header-local mouse target used because expanded selectable output can leave a
/// SwiftUI `Button` reachable through accessibility while mouse clicks fall through
/// or land on child views. Keeping this overlay scoped to the header preserves text
/// selection and scrolling in expanded details.
private struct TranscriptHeaderMouseTarget: NSViewRepresentable {
    let action: () -> Void
    let pressedChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TranscriptHeaderMouseTargetView {
        let view = TranscriptHeaderMouseTargetView()
        view.action = action
        view.pressedChanged = pressedChanged
        return view
    }

    func updateNSView(_ nsView: TranscriptHeaderMouseTargetView, context: Context) {
        nsView.action = action
        nsView.pressedChanged = pressedChanged
    }

    static func dismantleNSView(_ nsView: TranscriptHeaderMouseTargetView, coordinator: ()) {
        nsView.resetPressedState()
    }
}

private final class TranscriptHeaderMouseTargetView: NSView {
    var action: (() -> Void)?
    var pressedChanged: ((Bool) -> Void)?
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            resetPressedState()
        }
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setPressed(bounds.contains(point))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shouldTriggerAction = bounds.contains(point)
        setPressed(false)
        if shouldTriggerAction {
            action?()
        }
    }

    func resetPressedState() {
        setPressed(false)
    }

    private func setPressed(_ newValue: Bool) {
        guard isPressed != newValue else {
            return
        }
        isPressed = newValue
        pressedChanged?(newValue)
    }
}
