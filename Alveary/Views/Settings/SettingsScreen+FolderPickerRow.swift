import AppKit
import SwiftUI

struct SettingsFolderPickerRow: View {
    let title: String
    @Binding var path: String
    let prompt: String

    init(_ title: String, path: Binding<String>, prompt: String = "Choose Folder") {
        self.title = title
        _path = path
        self.prompt = prompt
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .accessibilityHidden(true)

            Spacer(minLength: 16)

            Text(path)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .help(path)
                .frame(maxWidth: 220, alignment: .trailing)

            Button(action: chooseFolder) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("Choose…")
                }
            }
            .secondaryActionButtonStyle()
        }
        .frame(maxWidth: .infinity, minHeight: SettingsScreenLayout.settingsRowHeight, alignment: .leading)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let expanded = (path as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            panel.directoryURL = URL(fileURLWithPath: expanded)
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        path = (url.path as NSString).abbreviatingWithTildeInPath
    }
}
