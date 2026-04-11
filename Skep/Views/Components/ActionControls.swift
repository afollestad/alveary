import SwiftUI

private let destructiveActionTint = Color(red: 0.74, green: 0.18, blue: 0.17)
private let secondaryActionTint = Color.primary.opacity(0.12)

struct DestructiveConfirmationRequest {
    let title: String
    let message: String
    let confirmTitle: String
    let confirm: () -> Void
}

extension View {
    func destructiveConfirmation(
        _ request: Binding<DestructiveConfirmationRequest?>
    ) -> some View {
        modifier(DestructiveConfirmationModifier(request: request))
    }

    func primaryActionButtonStyle() -> some View {
        buttonStyle(ProminentActionButtonStyle(fillColor: .accentColor, foregroundColor: .white))
    }

    func secondaryActionButtonStyle() -> some View {
        buttonStyle(
            ProminentActionButtonStyle(
                fillColor: secondaryActionTint,
                foregroundColor: .primary,
                borderColor: .primary
            )
        )
    }

    func destructiveActionButtonStyle() -> some View {
        buttonStyle(ProminentActionButtonStyle(fillColor: destructiveActionTint, foregroundColor: .white))
    }
}

private struct ProminentActionButtonStyle: ButtonStyle {
    let fillColor: Color
    let foregroundColor: Color
    let borderColor: Color?

    init(fillColor: Color, foregroundColor: Color, borderColor: Color? = nil) {
        self.fillColor = fillColor
        self.foregroundColor = foregroundColor
        self.borderColor = borderColor
    }

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(foregroundColor.opacity(isEnabled ? 1 : 0.78))
            .imageScale(.small)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(height: controlHeight)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(resolvedBorderColor.opacity(borderOpacity), lineWidth: borderWidth)
            )
            .opacity(configuration.isPressed && isEnabled ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
        switch controlSize {
        case .mini:
            return 8
        case .small:
            return 9
        case .regular:
            return 10
        case .extraLarge:
            return 14
        case .large:
            return 12
        @unknown default:
            return 10
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return fillColor.opacity(0.38)
        }

        return isPressed ? fillColor.opacity(0.84) : fillColor
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
