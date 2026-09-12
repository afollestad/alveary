import AppKit
import SwiftUI

struct ScheduledTaskEditorWorkspaceSection: View {
    let projects: [ScheduledTaskProjectOption]
    let threads: [ScheduledTaskThreadOption]
    let sections: [ScheduledTaskSectionOption]
    @Binding var draft: ScheduledTaskEditorDraft
    let onOpenReusedThread: (String) -> Void
    @State private var folderResolutionTask: Task<Void, Never>?
    @State private var folderResolutionID: UUID?

    var body: some View {
        SettingsFormSection("Workspace") {
            // Last row in the section while the destination is unresolved, so it drops its
            // divider rather than trailing one under nothing.
            SettingsFormRow(showsDivider: !draft.hasUnresolvedDestination) {
                SettingsResponsiveControlRow("Runs in", horizontalControlSizing: .selectedContent) {
                    // Optional-valued so an unrecognized persisted destination reads as no
                    // selection and falls back to the placeholder, the same shape the Thread
                    // picker below uses. No `None` row is added: nothing may select back into
                    // the unresolved state.
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Runs in",
                        selection: $draft.destinationSelection,
                        options: [
                            .init(value: Optional(.reusedThread), label: "Same thread each time"),
                            .init(value: Optional(.newThreadPerRun), label: "New thread each time"),
                            .init(value: Optional(.existingThread), label: "Existing thread")
                        ],
                        placeholder: "Choose a destination"
                    )
                }
            }

            // Withheld while the persisted destination is unrecognized: each row below
            // describes a destination the user has not chosen yet, and the Thread row would
            // name the reuse link of a schedule that may not be a reuse schedule at all.
            if !draft.hasUnresolvedDestination {
                destinationDependentRows
            }
        }
        .disabled(draft.isResolvingFolders)
        .onDisappear {
            folderResolutionTask?.cancel()
            folderResolutionTask = nil
            folderResolutionID = nil
            draft.isResolvingFolders = false
        }
    }

    /// Every Workspace row that only makes sense once the destination is known.
    @ViewBuilder
    private var destinationDependentRows: some View {
        // Once a run has minted the reuse thread, "Same thread each time" names a thread that
        // already exists, so the row says which one. Above Project and Section deliberately:
        // those rows now only describe the replacement a self-heal would create.
        if draft.destination == .reusedThread, let reusedThread = draft.reusedThread {
            SettingsFormRow {
                SettingsResponsiveControlRow(
                    "Thread",
                    // Names both self-heal triggers: this row is the only place the user can
                    // see that a workspace or provider edit swaps the thread out from under
                    // the schedule (`ScheduledTaskMutationService.preservesReuseLink`).
                    helpText: """
                        Every run posts here. Archiving or deleting it, or changing the \
                        workspace or provider, makes the next run create a replacement.
                        """,
                    horizontalControlSizing: .selectedContent
                ) {
                    ScheduledTaskReusedThreadLinkButton(link: reusedThread, onOpen: onOpenReusedThread)
                }
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
                            .init(value: Optional($0.id), label: $0.name)
                        }
                    )
                }
            }

            // Sidebar placement is independent of execution kind; an unplaced source workspace
            // can use a custom section too. Hide the picker when Tasks would be its only choice.
            if draft.projectID == nil, !sections.isEmpty {
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

            if draft.workspaceSnapshot?.primarySource?.isGitRepository == true {
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

            primaryFolderRow
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

    private var projectSelection: Binding<String?> {
        Binding(
            get: {
                if draft.workspaceSnapshot != nil { return draft.projectID }
                return draft.projectID ?? projects.first { $0.path == draft.projectPath }?.id
            },
            set: { id in
                let workspace = projects.first { $0.id == id }?.workspaceSnapshot ?? WorkspaceSnapshot(primarySource: nil)
                draft.projectID = id
                draft.workspaceSnapshot = workspace
                draft.projectPath = workspace.primarySource?.path
                draft.grantedRoots = workspace.grants.map(\.path)
                draft.workspaceKind = workspace.primarySource == nil ? .privateWorkspace : .project
                if workspace.primarySource?.isGitRepository != true { draft.workspaceStrategy = .localCheckout }
                if id != nil { draft.sectionID = nil }
            }
        )
    }

    /// Grant controls edit the path list independently; a primary switch must use that current list.
    private var effectiveWorkspace: WorkspaceSnapshot? {
        guard let saved = draft.workspaceSnapshot else { return nil }
        return WorkspaceSnapshot(primarySource: saved.primarySource, grants: draft.grantedRoots.map { path in
            saved.grants.first { $0.path == path } ?? SourceFolderSnapshot(path: path)
        })
    }

    @ViewBuilder
    private var primaryFolderRow: some View {
        if let workspace = effectiveWorkspace, let source = workspace.primarySource {
            SettingsFormRow {
                SettingsResponsiveControlRow("Primary folder", horizontalControlSizing: .selectedContent) {
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Primary folder",
                        selection: Binding(
                            get: { source.path },
                            set: { draft.selectPrimaryFolder(path: $0) }
                        ),
                        options: workspace.sourceFolders.map { .init(value: $0.path, label: $0.name) }
                    )
                }
            }
        }
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
                            Text(draft.isResolvingFolders ? "Resolving folders…" : "Add folders")
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
        let captured = draft
        let paths = ScheduledTask.normalizedUniquePaths(panel.urls.map(\.path))
        let resolutionID = UUID()
        folderResolutionID = resolutionID
        draft.isResolvingFolders = true
        folderResolutionTask = Task { @MainActor in
            defer {
                if folderResolutionID == resolutionID, draft.id == captured.id { draft.isResolvingFolders = false }
            }
            var folders: [SourceFolderSnapshot] = []
            for path in paths {
                let folder: SourceFolderSnapshot
                if let saved = captured.workspaceSnapshot?.sourceFolders.first(where: { $0.path == path }) {
                    folder = saved
                } else {
                    folder = await SourceFolderMetadataResolver().resolve(path: path)
                }
                guard !Task.isCancelled else { return }
                folders.append(folder)
            }
            guard folderResolutionID == resolutionID, draft.id == captured.id, draft.destination == captured.destination,
                  draft.workspaceSnapshot == captured.workspaceSnapshot, draft.projectID == captured.projectID,
                  draft.grantedRoots == captured.grantedRoots, draft.projectPath == captured.projectPath else { return }
            draft.addFolderGrants(folders)
        }
    }
}

/// Names the thread a reuse schedule already created, and opens it.
///
/// Carries `ScheduledTaskMenuPicker`'s surface, padding, and height so it sits as a peer of the
/// Project and Section rows rather than as a foreign link, but swaps the up/down chevron for an
/// open glyph: `ScheduledTask.reusedThread` is service-owned, so this row reports the venue and
/// no editor surface may retarget it.
private struct ScheduledTaskReusedThreadLinkButton: View {
    let link: ScheduledTaskReusedThreadLink
    let onOpen: (String) -> Void

    var body: some View {
        Button {
            onOpen(link.conversationID)
        } label: {
            HStack(spacing: 8) {
                Text(link.name)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: AppInputStyle.menuChevronPointSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppInputStyle.menuHorizontalPadding)
            .frame(
                minHeight: SettingsScreenLayout.settingsControlSurfaceHeight,
                maxHeight: SettingsScreenLayout.settingsControlSurfaceHeight
            )
            .background(
                RoundedRectangle(cornerRadius: AppInputStyle.defaultCornerRadius, style: .continuous)
                    .fill(AppInputStyle.menuBackgroundColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(link.name)")
        .accessibilityLabel("Open thread \(link.name)")
    }
}
