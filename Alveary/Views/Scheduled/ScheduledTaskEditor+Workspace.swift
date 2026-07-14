import AppKit
import SwiftUI

struct ScheduledTaskEditorWorkspaceSection: View {
    let projects: [ScheduledTaskProjectOption]
    @Binding var draft: ScheduledTaskEditorDraft

    var body: some View {
        SettingsFormSection("Workspace") {
            SettingsFormRow {
                SettingsResponsiveControlRow("Primary workspace", horizontalControlSizing: .intrinsic) {
                    Picker("Primary workspace", selection: $draft.workspaceKind) {
                        Text("Private").tag(ScheduledTaskWorkspaceKind.privateWorkspace)
                        Text("Project").tag(ScheduledTaskWorkspaceKind.project)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if draft.workspaceKind == .project {
                SettingsFormRow {
                    SettingsResponsiveControlRow("Project") {
                        Picker("Project", selection: $draft.projectPath) {
                            Text("Select a project").tag(String?.none)
                            ForEach(projects) { project in
                                Text(project.name).tag(Optional(project.path))
                            }
                        }
                        .labelsHidden()
                    }
                }

                SettingsFormRow {
                    SettingsResponsiveControlRow("Run location", horizontalControlSizing: .intrinsic) {
                        Picker("Run location", selection: $draft.workspaceStrategy) {
                            Text("Worktree").tag(ScheduledTaskWorkspaceStrategy.worktree)
                            Text("Local checkout").tag(ScheduledTaskWorkspaceStrategy.localCheckout)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }

            SettingsFormRow(showsDivider: false) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Folder grants")
                            Text("Give this task access to additional folders.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(action: chooseFolders) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.badge.plus")
                                Text("Add folders")
                            }
                        }
                        .secondaryActionButtonStyle()
                    }

                    if draft.grantedRoots.isEmpty {
                        Text("No additional folders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(draft.grantedRoots, id: \.self) { path in
                                HStack(spacing: 10) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        draft.grantedRoots.removeAll { $0 == path }
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove folder grant")
                                    .accessibilityLabel("Remove \(path)")
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityHint(path)
                            }
                        }
                    }
                }
            }
        }
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.title = "Choose folders"
        panel.prompt = "Add"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK else {
            return
        }
        draft.grantedRoots = ScheduledTask.normalizedUniquePaths(
            draft.grantedRoots + panel.urls.map(\.path)
        )
    }
}
