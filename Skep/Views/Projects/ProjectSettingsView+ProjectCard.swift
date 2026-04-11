import SwiftUI

struct ProjectSettingsProjectCard: View {
    let projectPath: String
    @Binding var projectName: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text(projectPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Divider()

                AppTextField("Project name", text: $projectName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Project", systemImage: "folder")
        }
    }
}
