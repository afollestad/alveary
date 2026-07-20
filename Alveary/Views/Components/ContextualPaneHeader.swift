import SwiftUI

struct ContextualPaneHeader: View {
    let title: String
    let subtitle: String?
    let closeAccessibilityLabel: String
    let onClose: () -> Void

    init(
        _ title: String,
        subtitle: String? = nil,
        closeAccessibilityLabel: String,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.closeAccessibilityLabel = closeAccessibilityLabel
        self.onClose = onClose
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            ModalCloseButton(closeAccessibilityLabel, action: onClose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .bottom) {
            AppSeparatorHairline(surface: .paneHeader)
        }
    }
}
