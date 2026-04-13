import SwiftUI

struct ProjectSettingsScriptsCard: View {
    @Binding var setupScript: String
    @Binding var teardownScript: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                SettingsTextFieldRow(
                    "Setup script",
                    text: $setupScript,
                    width: 520,
                    textAlignment: .leading
                )

                SettingsTextFieldRow(
                    "Cleanup script",
                    text: $teardownScript,
                    width: 520,
                    textAlignment: .leading
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
        } label: {
            Label("Lifecycle Scripts", systemImage: "terminal")
        }
    }
}
