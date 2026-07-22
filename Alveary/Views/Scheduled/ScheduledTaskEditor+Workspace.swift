import AppKit
import SwiftUI

struct ScheduledTaskEditorWorkspaceSection: View {
    let projects: [ScheduledTaskProjectOption]
    let threads: [ScheduledTaskThreadOption]
    @Binding var draft: ScheduledTaskEditorDraft

    var body: some View {
        SettingsFormSection("Workspace") {
            SettingsFormRow {
                SettingsResponsiveControlRow("Runs in", horizontalControlSizing: .selectedContent) {
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Runs in",
                        selection: $draft.destination,
                        options: [
                            .init(value: .newThread, label: "New thread"),
                            .init(value: .existingThread, label: "Existing thread")
                        ]
                    )
                }
            }

            switch draft.destination {
            case .newThread:
                SettingsFormRow {
                    SettingsResponsiveControlRow("Project", horizontalControlSizing: .selectedContent) {
                        ScheduledTaskMenuPicker(
                            accessibilityLabel: "Project",
                            selection: projectSelection,
                            options: [.init(value: String?.none, label: "None")] + projects.map {
                                .init(value: Optional($0.path), label: $0.name)
                            }
                        )
                    }
                }

                if draft.projectPath != nil {
                    SettingsFormRow {
                        SettingsResponsiveControlRow("Run location", horizontalControlSizing: .intrinsic) {
                            Picker("Run location", selection: $draft.workspaceStrategy) {
                                Text("Worktree").tag(ScheduledTaskWorkspaceStrategy.worktree)
                                Text("Local").tag(ScheduledTaskWorkspaceStrategy.localCheckout)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                }

                folderGrantsRow
            case .existingThread:
                if threads.isEmpty {
                    SettingsFormRow(showsDivider: false) {
                        SettingsResponsiveControlRow("Thread", horizontalControlSizing: .selectedContent) {
                            Text("Pin a local thread first")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                } else {
                    SettingsFormRow(showsDivider: false) {
                        SettingsResponsiveControlRow("Thread", horizontalControlSizing: .selectedContent) {
                            ScheduledTaskMenuPicker(
                                accessibilityLabel: "Existing thread",
                                selection: $draft.targetConversationID,
                                options: [.init(value: String?.none, label: "Select a thread")] + threads.map {
                                    .init(value: Optional($0.conversationID), label: $0.label)
                                },
                                placeholder: "Select a thread"
                            )
                        }
                    }
                }
            }
        }
    }

    private var projectSelection: Binding<String?> {
        Binding(
            get: { draft.projectPath },
            set: { path in
                draft.projectPath = path
                draft.workspaceKind = path == nil ? .privateWorkspace : .project
            }
        )
    }

    private var folderGrantsRow: some View {
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
