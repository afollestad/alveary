import AppKit
import SwiftUI

struct ScheduledTaskEditorWorkspaceSection: View {
    let projects: [ScheduledTaskProjectOption]
    let threads: [ScheduledTaskThreadOption]
    let sections: [ScheduledTaskSectionOption]
    @Binding var draft: ScheduledTaskEditorDraft

    var body: some View {
        SettingsFormSection("Workspace") {
            SettingsFormRow {
                SettingsResponsiveControlRow("Runs in", horizontalControlSizing: .selectedContent) {
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Runs in",
                        selection: $draft.destination,
                        options: [
                            .init(value: .reusedThread, label: "New thread"),
                            .init(value: .newThreadPerRun, label: "New thread each time"),
                            .init(value: .existingThread, label: "Existing thread")
                        ]
                    )
                }
            }

            switch draft.destination {
            case .reusedThread, .newThreadPerRun:
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

                // Gated on the kind, not `projectPath == nil`: a legacy `.project` row whose
                // Project vanished must hide this alongside Run location rather than offer a
                // section its `.project`-mode thread could never render in. Hidden entirely
                // without custom sections — a picker whose only option is `Tasks` is no choice.
                if draft.workspaceKind == .privateWorkspace, !sections.isEmpty {
                    SettingsFormRow {
                        SettingsResponsiveControlRow("Section", horizontalControlSizing: .selectedContent) {
                            ScheduledTaskMenuPicker(
                                accessibilityLabel: "Sidebar section",
                                selection: $draft.sectionID,
                                options: [.init(value: String?.none, label: "Tasks")] + sections.map {
                                    .init(value: Optional($0.id), label: $0.name)
                                }
                            )
                        }
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
                            Text("No eligible threads")
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
                // A Project placement makes the created thread `.project` mode, which nests
                // under the Project and never renders in a section; clearing here keeps a
                // now-hidden pick from round-tripping invisibly.
                if path != nil {
                    draft.sectionID = nil
                }
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
