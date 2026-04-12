import SwiftUI

struct ProjectSettingsScriptsCard: View {
    let setupScript: String?
    let teardownScript: String?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Setup script")
                        .font(.headline)
                    ProjectSettingsScriptBlock(
                        script: setupScript,
                        placeholder: "No setup script configured."
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cleanup script")
                        .font(.headline)
                    ProjectSettingsScriptBlock(
                        script: teardownScript,
                        placeholder: "No cleanup script configured."
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Lifecycle Scripts", systemImage: "terminal")
        }
    }
}

private struct ProjectSettingsScriptBlock: View {
    let script: String?
    let placeholder: String

    var body: some View {
        Group {
            if let script, !script.isEmpty {
                Text(script)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text(placeholder)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
