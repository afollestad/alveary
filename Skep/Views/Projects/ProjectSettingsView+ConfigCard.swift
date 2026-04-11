import SwiftUI

struct ProjectSettingsConfigCard: View {
    let configExists: Bool
    let onEditLocalEnvironment: () -> Void
    let onCreateConfig: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("The local `.skep.json` file controls setup scripts, preserved files, and project actions.")
                    .foregroundStyle(.secondary)

                HStack {
                    if configExists {
                        Button("Edit Local Environment", action: onEditLocalEnvironment)
                            .secondaryActionButtonStyle()
                    } else {
                        Button("Create Config", action: onCreateConfig)
                            .primaryActionButtonStyle()
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Environment Config", systemImage: "doc.text")
        }
    }
}
