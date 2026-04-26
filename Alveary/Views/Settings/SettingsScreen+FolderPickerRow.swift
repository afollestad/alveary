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
        SettingsResponsiveControlRow(title) {
            HStack(spacing: 10) {
                Text(path)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .help(path)
                    .accessibilityLabel(title)
                    .accessibilityValue(path)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)

                Button(action: chooseFolder) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Choose…")
                    }
                }
                .secondaryActionButtonStyle()
                .accessibilityLabel("Choose \(title)")
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
        }
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
