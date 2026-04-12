import SwiftUI

struct SidebarProjectsHeaderRow: View {
    let onAddProject: () -> Void

    var body: some View {
        HStack {
            Text("Projects")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button(action: onAddProject) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add Project")
            .help("Add Project")
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}
