import SwiftUI

private let destructiveActionTint = Color(red: 0.74, green: 0.18, blue: 0.17)
private let secondaryActionTint = Color.primary.opacity(0.12)
private let iconActionButtonTint = Color.secondary.opacity(0.16)
private let destructiveIconActionButtonTint = destructiveActionTint.opacity(0.16)

struct DestructiveConfirmationRequest {
    let title: String
    let message: String
    let confirmTitle: String
    let confirm: () -> Void
}

struct ModalCloseButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    init(_ accessibilityLabel: String, action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
        }
        .iconActionButtonStyle()
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    func destructiveConfirmation(
        _ request: Binding<DestructiveConfirmationRequest?>
    ) -> some View {
        modifier(DestructiveConfirmationModifier(request: request))
    }

    func primaryActionButtonStyle(expandsHorizontally: Bool = false) -> some View {
        // Use `AppAccentFill.primary` (the muted accent token shared with
        // selected sidebar rows, conversation tabs, user bubbles, and the
        // scroll-to-latest button) so every prominent affordance in the app
        // speaks with one accent voice. `.primary` as foreground adapts to
        // both schemes against the muted fill.
        buttonStyle(ProminentActionButtonStyle(
            fillColor: AppAccentFill.primary,
            foregroundColor: .primary,
            expandsHorizontally: expandsHorizontally
        ))
    }

    func secondaryActionButtonStyle(expandsHorizontally: Bool = false) -> some View {
        buttonStyle(
            ProminentActionButtonStyle(
                fillColor: secondaryActionTint,
                foregroundColor: .primary,
                borderColor: .primary,
                expandsHorizontally: expandsHorizontally
            )
        )
    }

    func destructiveActionButtonStyle(expandsHorizontally: Bool = false) -> some View {
        buttonStyle(ProminentActionButtonStyle(
            fillColor: destructiveActionTint,
            foregroundColor: .white,
            expandsHorizontally: expandsHorizontally
        ))
    }

    func iconActionButtonStyle() -> some View {
        buttonStyle(IconActionButtonStyle())
    }

    func destructiveIconActionButtonStyle() -> some View {
        buttonStyle(
            IconActionButtonStyle(
                foregroundColor: destructiveActionTint,
                backgroundColor: destructiveIconActionButtonTint
            )
        )
    }
}

private struct ProminentActionButtonStyle: ButtonStyle {
    let fillColor: Color
    let foregroundColor: Color
    let borderColor: Color?
    let expandsHorizontally: Bool

    init(
        fillColor: Color,
        foregroundColor: Color,
        borderColor: Color? = nil,
        expandsHorizontally: Bool = false
    ) {
        self.fillColor = fillColor
        self.foregroundColor = foregroundColor
        self.borderColor = borderColor
        self.expandsHorizontally = expandsHorizontally
    }

    func makeBody(configuration: Configuration) -> some View {
        ProminentActionButtonBody(
            configuration: configuration,
            fillColor: fillColor,
            foregroundColor: foregroundColor,
            borderColor: borderColor,
            expandsHorizontally: expandsHorizontally
        )
    }
}

/// Extracted from the `ButtonStyle` so it can own an `@State` hover flag. The
/// hover overlay is a translucent fill in the style's own `foregroundColor` on
/// top of the resolved background, so it always leans toward the label color:
/// `.primary` for the primary/secondary variants (darkens in light mode,
/// lightens in dark) and `.white` for the destructive variant (slight lift on
/// the dark red). That's the opposite direction of the pressed state (which
/// uses `.opacity(0.84)` to fade the fill toward the window background), so
/// hover reads as "emphasize toward label" and press reads as "soften toward
/// window" on every theme without needing per-variant branches.
private struct ProminentActionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let fillColor: Color
    let foregroundColor: Color
    let borderColor: Color?
    let expandsHorizontally: Bool

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(foregroundColor.opacity(isEnabled ? 1 : 0.78))
            .imageScale(.small)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: expandsHorizontally ? .infinity : nil)
            .frame(height: controlHeight)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(backgroundColor(isPressed: configuration.isPressed))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(foregroundColor.opacity(0.06))
                        .opacity(showsHoverOverlay ? 1 : 0)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(resolvedBorderColor.opacity(borderOpacity), lineWidth: borderWidth)
            )
            .opacity(configuration.isPressed && isEnabled ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private var showsHoverOverlay: Bool {
        isHovering && isEnabled && !configuration.isPressed
    }

    private var resolvedBorderColor: Color {
        borderColor ?? fillColor
    }

    private var borderOpacity: Double {
        guard borderColor != nil else {
            return 0
        }

        return isEnabled ? 0.12 : 0.06
    }

    private var borderWidth: CGFloat {
        borderColor == nil ? 0 : 1
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini:
            return 8
        case .small:
            return 10
        case .regular:
            return 12
        case .extraLarge:
            return 16
        case .large:
            return 14
        @unknown default:
            return 12
        }
    }

    private var controlHeight: CGFloat {
        switch controlSize {
        case .mini:
            return 22
        case .small:
            return 24
        case .regular:
            return 30
        case .extraLarge:
            return 38
        case .large:
            return 34
        @unknown default:
            return 30
        }
    }

    private var cornerRadius: CGFloat {
        AppCornerRadius.standard
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return fillColor.opacity(0.38)
        }

        return isPressed ? fillColor.opacity(0.84) : fillColor
    }
}

private struct IconActionButtonStyle: ButtonStyle {
    let foregroundColor: Color
    let backgroundColor: Color

    init(
        foregroundColor: Color = .primary,
        backgroundColor: Color = iconActionButtonTint
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        IconActionButtonBody(
            configuration: configuration,
            isEnabled: isEnabled,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor
        )
    }
}

private struct IconActionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    let foregroundColor: Color
    let backgroundColor: Color

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(foregroundColor.opacity(foregroundOpacity))
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .background(
                Circle()
                    .fill(backgroundColor.opacity(backgroundOpacity))
            )
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
    }

    private var foregroundOpacity: Double {
        guard isEnabled else {
            return 0.6
        }

        return isHovering ? 0.95 : 0.8
    }

    private var backgroundOpacity: Double {
        guard isEnabled, isHovering else {
            return 0
        }

        return 1
    }
}

private struct DestructiveConfirmationModifier: ViewModifier {
    @Binding var request: DestructiveConfirmationRequest?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            request?.title ?? "",
            isPresented: Binding(
                get: { request != nil },
                set: { isPresented in
                    if !isPresented {
                        request = nil
                    }
                }
            ),
            presenting: request
        ) { confirmation in
            Button(confirmation.confirmTitle, role: .destructive) {
                let confirm = confirmation.confirm
                self.request = nil
                confirm()
            }

            Button("Cancel", role: .cancel) {
                self.request = nil
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }
}
