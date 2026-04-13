import SwiftUI

struct ProjectSettingsHeader: View {
    let projectPath: String
    @Binding var projectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project")
                .font(.largeTitle.weight(.semibold))

            Text(CanonicalPath.abbreviateHomeDirectory(projectPath))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            AppTextField("Project name", text: $projectName)

            Divider().padding(.top, 8)
        }
    }
}
