import SwiftUI

struct ProjectEditorSourceFolders: View {
    let folders: [SourceFolderSnapshot]
    let primaryFolderPath: String?
    let isImporting: Bool
    let onAdd: () -> Void
    let onMakePrimary: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        Group {
            if folders.isEmpty {
                addFolderControl
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(folders) { folder in
                            ProjectEditorFolderRow(
                                folder: folder, isPrimary: folder.path == primaryFolderPath,
                                makePrimary: { onMakePrimary(folder.path) },
                                remove: { onRemove(folder.path) }
                            )
                            .disabled(isImporting)
                            Divider()
                        }
                        addFolderControl.frame(height: 54)
                    }
                }
            }
        }
        .frame(minHeight: 96, maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary).allowsHitTesting(false))
    }

    @ViewBuilder
    private var addFolderControl: some View {
        if isImporting {
            HStack {
                StatusIndicatorSpinner(color: .secondary, diameter: 16, lineWidth: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Resolving folders")
        } else {
            ProjectEditorAddFolderButton(isEmpty: folders.isEmpty, action: onAdd)
        }
    }
}

struct ProjectEditorAddFolderButton: View {
    let isEmpty: Bool
    let action: () -> Void
    @State var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus").font(.title2).foregroundStyle(.secondary)
                        Text("Add folders your agent can read and edit")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus").foregroundStyle(.secondary)
                        Text("Add folder")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .font(.body)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProjectEditorAddFolderButtonStyle(isHovered: isHovered))
        .onHover { isHovered = $0 }
    }
}

private struct ProjectEditorAddFolderButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? AppSelectionRowFill.pressed : isHovered ? AppSelectionRowFill.hovered : .clear)
    }
}

private struct ProjectEditorFolderRow: View {
    let folder: SourceFolderSnapshot
    let isPrimary: Bool
    let makePrimary: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name).fontWeight(.medium)
                Text(CanonicalPath.abbreviateHomeDirectory(folder.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(folder.path)
            }
            Spacer()
            if isPrimary {
                Text("Primary").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            } else {
                Button("Make primary", action: makePrimary).inlineActionButtonStyle(foregroundColor: .secondary)
                    .accessibilityLabel("Make \(folder.path) primary")
            }
            Button(action: remove) { Image(systemName: "xmark") }
                .iconActionButtonStyle()
                .help("Remove \(folder.name)")
                .accessibilityLabel("Remove \(folder.path)")
        }
        .padding(12)
    }
}
