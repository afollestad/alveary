import AppKit
import SwiftUI

struct AppTextField: View {
    @Binding private var text: String
    @FocusState private var isFocused: Bool

    private let title: String
    private let showsPrompt: Bool
    private let textAlignment: TextAlignment
    private let cornerRadius: CGFloat
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let backgroundColor: Color
    private let cornerRadii: RectangleCornerRadii?
    private let borderColor: Color
    private let borderWidth: CGFloat
    private let showsClearButton: Bool
    private let focusesOnAppear: Bool

    init(
        _ title: String,
        text: Binding<String>,
        showsPrompt: Bool = true,
        textAlignment: TextAlignment = .leading,
        cornerRadius: CGFloat = AppInputStyle.defaultCornerRadius,
        cornerRadii: RectangleCornerRadii? = nil,
        horizontalPadding: CGFloat = AppInputStyle.defaultHorizontalPadding,
        verticalPadding: CGFloat = AppInputStyle.defaultVerticalPadding,
        backgroundColor: Color = AppInputStyle.backgroundColor,
        borderColor: Color = AppInputStyle.borderColor,
        borderWidth: CGFloat = AppInputStyle.borderWidth,
        showsClearButton: Bool = false,
        focusesOnAppear: Bool = false
    ) {
        self._text = text
        self.title = title
        self.showsPrompt = showsPrompt
        self.textAlignment = textAlignment
        self.cornerRadius = cornerRadius
        self.cornerRadii = cornerRadii
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.showsClearButton = showsClearButton
        self.focusesOnAppear = focusesOnAppear
    }

    var body: some View {
        AppTextInputContainer(
            cornerRadius: cornerRadius,
            cornerRadii: cornerRadii,
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            borderWidth: borderWidth
        ) {
            HStack(spacing: 0) {
                textField
                    .textFieldStyle(.plain)
                    .accessibilityLabel(Text(title))
                    .multilineTextAlignment(textAlignment)
                    .focused($isFocused)
                    .padding(.leading, horizontalPadding)
                    // The clear button owns the trailing inset when it is showing, so
                    // scrolled text and the caret cannot run underneath it.
                    .padding(.trailing, isClearButtonVisible ? 4 : horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isClearButtonVisible {
                    clearButton
                        .padding(.trailing, horizontalPadding)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
        .background {
            // A fresh `.popover`'s window is not key at mount — the presenting
            // window keeps key status, SwiftUI drops focus requests for non-key
            // windows, and ⌘V keeps routing to the presenting window's first
            // responder (the composer). Claim key at the AppKit level first.
            if focusesOnAppear {
                WindowKeyClaimingView()
            }
        }
        .animation(.easeOut(duration: 0.12), value: isClearButtonVisible)
        .task {
            guard focusesOnAppear else {
                return
            }
            // Claim focus on mount, then once more a beat later in case the
            // first request raced the window-key claim above.
            isFocused = true
            try? await Task.sleep(for: .milliseconds(80))
            isFocused = true
        }
    }

    private var isClearButtonVisible: Bool {
        showsClearButton && !text.isEmpty
    }

    /// Clearing keeps focus in the field, matching `NSSearchField`: the gesture is
    /// "start over", not "stop typing".
    private var clearButton: some View {
        Button {
            text = ""
            isFocused = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Clear")
        .accessibilityLabel("Clear \(title)")
    }
}

/// Makes its hosting window key when mounted. Zero-sized, hit-test inert.
private struct WindowKeyClaimingView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        KeyClaimView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class KeyClaimView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            claimKeyWindow(retriesRemaining: 12)
        }

        /// A popover window is not yet visible when its content mounts, and
        /// `makeKey()` on an invisible window is a no-op — so the first attempt
        /// always fails and `NSApp.keyWindow` stays on the presenting window,
        /// which is where ⌘V would land. Retry across runloop turns until AppKit
        /// agrees this window is key, matching the retry shape
        /// `AppTextEditor+AppKit.swift` uses to claim first responder.
        private func claimKeyWindow(retriesRemaining: Int) {
            guard let window, self.window === window else {
                return
            }
            if window.isVisible, window.canBecomeKey {
                window.makeKey()
            }
            guard NSApp.keyWindow !== window, retriesRemaining > 0 else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.claimKeyWindow(retriesRemaining: retriesRemaining - 1)
            }
        }
    }
}

private extension AppTextField {
    @ViewBuilder
    var textField: some View {
        if showsPrompt {
            TextField(title, text: $text)
        } else {
            TextField("", text: $text)
        }
    }
}
