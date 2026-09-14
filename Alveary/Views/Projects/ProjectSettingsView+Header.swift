import SwiftUI

/// Keep the heading outside the scroller so its trailing editor button clears the scrollbar.
struct ProjectSettingsHeader: View {
    let projectName: String
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(projectName)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(projectName)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button("Name and folders…", action: onEdit)
                .secondaryActionButtonStyle()
                .controlSize(.small)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
