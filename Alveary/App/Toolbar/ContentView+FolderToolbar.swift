import SwiftUI

extension ContentView {
    @ViewBuilder
    var workspaceFolderMenu: some View {
        if let context = selectedWorkspaceFolderContext, context.folders.count > 1,
           let selected = folderSelection.selected(in: context.folders, owner: context.owner) {
            WorkspaceFolderMenu(folders: context.folders, selected: selected) {
                folderSelection.select($0, owner: context.owner)
            }
        }
    }
}

/// The menu changes repository operations within a window, independently of the agent's working directory.
struct WorkspaceFolderMenu: View {
    let folders: [WorkspaceFolderTarget]
    let selected: WorkspaceFolderTarget
    let onSelect: (WorkspaceFolderTarget) -> Void

    var body: some View {
        Menu {
            Picker("Active folder", selection: Binding(
                get: { selected.id },
                set: { id in
                    if let folder = folders.first(where: { $0.id == id }) { onSelect(folder) }
                }
            )) {
                ForEach(folders.filter(\.isPrimary) + folders.filter { !$0.isPrimary }) { folder in
                    Text(folder.source.name + (folder.isPrimary ? " (Primary)" : "")
                         + "\n" + CanonicalPath.abbreviateHomeDirectory(folder.directory))
                        .tag(folder.id)
                        .help(folder.directory)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(selected.source.name, systemImage: "folder")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .frame(maxWidth: 160)
        }
        .help("Select a folder for settings, Git, actions, and new terminals")
        .accessibilityLabel("Active folder")
        .accessibilityValue(selected.directory)
    }
}
