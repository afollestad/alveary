import SwiftUI

struct SettingsScreenHeader: View {
    let title: String
    let description: String
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

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
