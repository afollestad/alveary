import SwiftUI

struct SettingsScreenHeader: View {
    let title: String
    let description: String
    var refresh: SettingsScreenHeaderRefresh?
    let onClose: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))

                Text(description)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let refresh {
                if refresh.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 30, height: 30)
                        .accessibilityLabel("Refreshing")
                } else {
                    Button(action: refresh.action) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .iconActionButtonStyle()
                    .accessibilityLabel(refresh.accessibilityLabel)
                }
            }

            if let onClose {
                ModalCloseButton("Close settings", action: onClose)
            }
        }
    }
}

/// A page-conditional refresh affordance rendered beside the header's close button.
struct SettingsScreenHeaderRefresh {
    let accessibilityLabel: String
    let isRefreshing: Bool
    let action: () -> Void
}
