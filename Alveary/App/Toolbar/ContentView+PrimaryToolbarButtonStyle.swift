import SwiftUI

/// Shared chrome for the primary toolbar group's icon buttons: the hover
/// selector, enabled/hover tinting, and press feedback. Split out of
/// `ContentView+PrimaryToolbarButtonGroup.swift` to keep that file under the
/// length limit.
extension View {
    func primaryToolbarIconButtonStyle(
        selector: PrimaryToolbarSelectorShape = .iconCircle,
        imageScale: Image.Scale = .medium
    ) -> some View {
        buttonStyle(PrimaryToolbarIconButtonStyle(selector: selector, imageScale: imageScale))
    }
}

enum PrimaryToolbarSelectorShape {
    case iconCircle
    case fullCapsule
}

private struct PrimaryToolbarIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let selector: PrimaryToolbarSelectorShape
    let imageScale: Image.Scale

    func makeBody(configuration: Configuration) -> some View {
        PrimaryToolbarIconButtonBody(
            configuration: configuration,
            isEnabled: isEnabled,
            selector: selector,
            imageScale: imageScale
        )
    }
}

private struct PrimaryToolbarIconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    let selector: PrimaryToolbarSelectorShape
    let imageScale: Image.Scale

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(PrimaryToolbarMetrics.iconFont)
            .imageScale(imageScale)
            .foregroundStyle(.primary.opacity(foregroundOpacity))
            .frame(
                minWidth: PrimaryToolbarMetrics.iconButtonSize,
                minHeight: PrimaryToolbarMetrics.iconButtonSize
            )
            .contentShape(Rectangle())
            .background(alignment: .leading) {
                selectorBackground
            }
            .opacity(configuration.isPressed && isEnabled ? 0.88 : 1)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(PrimaryToolbarMetrics.interactionAnimation, value: isHovering)
            .animation(PrimaryToolbarMetrics.interactionAnimation, value: configuration.isPressed)
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private var foregroundOpacity: Double {
        guard isEnabled else {
            return 0.45
        }

        return isHovering ? 0.95 : 0.82
    }

    @ViewBuilder
    private var selectorBackground: some View {
        switch selector {
        case .iconCircle:
            Circle()
                .fill(selectorFill)
                .frame(
                    width: PrimaryToolbarMetrics.iconButtonSize,
                    height: PrimaryToolbarMetrics.iconButtonSize
                )
        case .fullCapsule:
            // The diff button grows to show stats; its selector should cover
            // that full interactive label, not only the leading icon.
            Capsule(style: .continuous)
                .fill(selectorFill)
        }
    }

    private var selectorFill: Color {
        Color.primary.opacity(isHovering && isEnabled ? 0.1 : 0)
    }
}
