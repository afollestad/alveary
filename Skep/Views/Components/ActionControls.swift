import SwiftUI

private let destructiveActionTint = Color(red: 0.74, green: 0.18, blue: 0.17)

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
        buttonStyle(ProminentActionButtonStyle(fillColor: .accentColor))
    }

    func destructiveActionButtonStyle() -> some View {
        buttonStyle(ProminentActionButtonStyle(fillColor: destructiveActionTint))
    }
}

private struct ProminentActionButtonStyle: ButtonStyle {
    let fillColor: Color

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.78))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .opacity(configuration.isPressed && isEnabled ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini:
            return 8
        case .small:
            return 10
        case .regular:
            return 12
        case .large:
            return 14
        @unknown default:
            return 12
        }
    }

    private var verticalPadding: CGFloat {
        switch controlSize {
        case .mini:
            return 4
        case .small:
            return 5
        case .regular:
            return 6
        case .large:
            return 8
        @unknown default:
            return 6
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
