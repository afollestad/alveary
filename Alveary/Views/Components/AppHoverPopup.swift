import SwiftUI

struct AppHoverPopup<Content: View>: View {
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let textAlignment: TextAlignment
    private let content: Content

    init(
        horizontalPadding: CGFloat = 18,
        verticalPadding: CGFloat = 14,
        textAlignment: TextAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.textAlignment = textAlignment
        self.content = content()
    }

    var body: some View {
        content
            .multilineTextAlignment(textAlignment)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                    }
            }
    }
}

struct AppHoverInfoIcon: View {
    let text: String

    @State private var isHovered = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .contentShape(Circle())
            .accessibilityLabel("More information")
            .accessibilityValue(text)
            .onHover { hovering in
                isHovered = hovering
            }
            .popover(isPresented: $isHovered, arrowEdge: .top) {
                AppHoverPopup(horizontalPadding: 12, verticalPadding: 10, textAlignment: .leading) {
                    Text(text)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 280)
                }
                .padding(2)
            }
    }
}
