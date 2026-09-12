import AppKit
import SwiftUI

struct ProjectEditorForm: View {
    let viewModel: SidebarViewModel
    let projectID: String?
    let onCancel: () -> Void
    let onSaved: (Project) -> Void

    @State private var draft: ProjectConfiguration
    @State private var importTask: Task<Void, Never>?
    @State private var isImporting = false
    @State private var errorMessage: String?

    init(
        viewModel: SidebarViewModel,
        projectID: String? = nil,
        configuration: ProjectConfiguration = ProjectConfiguration(),
        onCancel: @escaping () -> Void,
        onSaved: @escaping (Project) -> Void
    ) {
        self.viewModel = viewModel
        self.projectID = projectID
        self.onCancel = onCancel
        self.onSaved = onSaved
        _draft = State(initialValue: configuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppTextField("Project name", text: $draft.name).disabled(isImporting)
            VStack(alignment: .leading, spacing: 8) {
                Text("Source folders").font(.headline)
                ProjectEditorSourceFolders(
                    folders: foldersWithPrimaryFirst,
                    primaryFolderPath: draft.primaryFolderPath,
                    isImporting: isImporting,
                    onAdd: chooseFolders,
                    onMakePrimary: { draft.primaryFolderPath = $0 },
                    onRemove: { draft.remove(path: $0) }
                )
            }
            .padding(.top, 10)

            Text(draft.folders.isEmpty
                 ? "Threads in this project use a private workspace."
                 : "New threads start in the primary folder and can access every listed folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let errorMessage {
                InlineBanner(message: errorMessage, severity: .error, autoDismissAfter: nil, onDismiss: { self.errorMessage = nil })
            }
            HStack {
                Spacer()
                Button("Cancel") { importTask?.cancel(); onCancel() }
                    .secondaryActionButtonStyle()
                    .keyboardShortcut(.cancelAction)
                Button(projectID == nil ? "Create" : "Save", action: save)
                    .primaryActionButtonStyle()
                    .keyboardShortcut(.defaultAction)
                    .disabled(isImporting || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onDisappear { importTask?.cancel() }
    }

    private var foldersWithPrimaryFirst: [SourceFolderSnapshot] {
        let primary = draft.folders.filter { $0.path == draft.primaryFolderPath }
        return primary + draft.folders.filter { $0.path != draft.primaryFolderPath }
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.map(\.path)
        isImporting = true
        errorMessage = nil
        importTask = Task { @MainActor in
            defer { isImporting = false }
            do {
                var updated = draft
                for path in paths {
                    let details = try await viewModel.resolveProjectDetails(for: path)
                    try Task.checkCancellation()
                    try updated.add(details.sourceFolder)
                }
                if updated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { updated.name = updated.folders.first?.name ?? "" }
                draft = updated
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        do { onSaved(try viewModel.saveProjectConfiguration(draft, projectID: projectID)) } catch { errorMessage = error.localizedDescription }
    }
}

struct ProjectEditorSheet: View {
    let projectID: String
    let configuration: ProjectConfiguration
    let viewModel: SidebarViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Project name and folders").font(.title2.weight(.semibold))
                Spacer()
                ModalCloseButton("Close project name and folders") { dismiss() }
            }
            ProjectEditorForm(
                viewModel: viewModel, projectID: projectID, configuration: configuration,
                onCancel: { dismiss() }, onSaved: { _ in dismiss() }
            )
        }
        .padding(24)
        .frame(width: 580)
    }
}
