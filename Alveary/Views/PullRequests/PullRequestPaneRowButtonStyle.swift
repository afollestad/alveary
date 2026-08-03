import SwiftUI

/// Full-width row button with the shared selectable-row hover and pressed fills,
/// used by the Overview's linked-owner and check rows. The rows sit in a plain
/// `VStack`, so the fill renders as a direct background instead of going through
/// `listRowBackground`.
struct PullRequestPaneRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PullRequestPaneRowButtonBody(configuration: configuration)
    }
}

private struct PullRequestPaneRowButtonBody: View {
    let configuration: ButtonStyle.Configuration

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppSelectionRowBackground(
                    isSelected: false,
                    isPressed: configuration.isPressed,
                    isHovered: isHovering,
                    leadingInset: 0,
                    trailingInset: 0,
                    topInset: 0,
                    bottomInset: 0
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
    }
}
