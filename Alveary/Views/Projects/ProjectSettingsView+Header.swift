import SwiftUI

struct ProjectSettingsHeader: View {
    let projectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project")
                .font(.largeTitle.weight(.semibold))

            Text(projectName)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}
