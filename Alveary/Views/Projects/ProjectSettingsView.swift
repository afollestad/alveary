import SwiftData
import SwiftUI

struct ProjectSettingsActionDraft: Identifiable, Equatable {
    let id: UUID
    var icon: String?
    var name: String
    var command: String

    init(
        id: UUID = UUID(),
        icon: String? = "terminal",
        name: String = "",
        command: String = ""
    ) {
        self.id = id
        self.icon = icon
        self.name = name
        self.command = command
    }

    init(action: AlvearyProjectConfig.ProjectAction) {
        self.init(icon: Self.normalizedIconName(action.icon), name: action.name, command: action.command)
    }

    var resolvedAction: AlvearyProjectConfig.ProjectAction? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return .init(icon: Self.normalizedIconName(icon), name: name, command: command)
    }

    var displayedIconName: String {
        guard let icon,
              !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "terminal"
        }
        return Self.normalizedIconName(icon) ?? "terminal"
    }

    private static func normalizedIconName(_ icon: String?) -> String? {
        switch icon?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case nil, "":
            return nil
        case "play.square":
            return "play"
        default:
            return icon
        }
    }
}

struct ProjectSettingsView: View {
    let project: Project
    let sourceFolder: SourceFolderSnapshot?
    @Bindable var appState: AppState

    private let loadConfig: @MainActor (String) async -> AlvearyProjectConfig
    private let sidebarViewModel: SidebarViewModel

    @Environment(\.modelContext) private var modelContext
    @State private var editorState: ProjectSettingsEditorState
    @State private var saveRevision: UInt64 = 0
    @State private var pendingSaveTask: Task<Void, Never>?
    @State private var screenError: String?
    @State private var projectEditor: ProjectEditorPresentation?

    init(
        project: Project,
        appState: AppState,
        sidebarViewModel: SidebarViewModel,
        initialConfig: AlvearyProjectConfig = .empty,
        sourceFolder: SourceFolderSnapshot? = nil,
        // The editor is the surface that must see an edit made outside the app, so it
        // reloads rather than accepting whatever the store already holds.
        loadConfig: @escaping @MainActor (String) async -> AlvearyProjectConfig = { projectPath in
            await ProjectConfigStore.shared.reload(forProjectPath: projectPath)
        }
    ) {
        self.project = project
        self.sourceFolder = sourceFolder ?? project.primaryFolder?.snapshot
        self.appState = appState
        self.sidebarViewModel = sidebarViewModel
        self.loadConfig = loadConfig

        _editorState = State(initialValue: ProjectSettingsEditorState(config: initialConfig))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text(project.name).font(.largeTitle.weight(.semibold))
                    Spacer()
                    Button("Name and folders…") {
                        projectEditor = ProjectEditorPresentation(project: project)
                    }
                    .secondaryActionButtonStyle()
                }

                if let screenError {
                    InlineBanner(
                        message: screenError,
                        severity: .error,
                        autoDismissAfter: nil,
                        onDismiss: { self.screenError = nil }
                    )
                }

                if let sourceFolder {
                    if project.folders.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                sourceFolder.name + (sourceFolder.path == project.primaryFolder?.path ? " (Primary)" : ""),
                                systemImage: "folder"
                            )
                            .font(.headline)
                            Text(CanonicalPath.abbreviateHomeDirectory(sourceFolder.path))
                                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                .help(sourceFolder.path)
                        }
                    }
                    if sourceFolder.isGitRepository {
                        ProjectSettingsRepositoryCard(sourceFolder: sourceFolder)
                    }

                    ProjectSettingsScriptsCard(
                        setupScript: setupScriptBinding,
                        teardownScript: teardownScriptBinding
                    )

                    ProjectSettingsPreservePatternsCard(
                        patterns: editorState.preservePatterns,
                        bindingForPattern: bindingForPattern,
                        onRemovePattern: removePattern
                    )

                    ProjectSettingsActionsCard(
                        actions: editorState.actions,
                        onUpdateAction: updateAction,
                        onAddAction: addAction,
                        onRemoveAction: removeAction
                    )
                } else {
                    Text("This project has no source folders. New threads use a private workspace.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .task(id: sourceFolder?.path) {
            await loadState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .projectConfigDidChange)) { notification in
            guard let path = sourceFolder?.path,
                  ProjectConfigChangeNotifier.changedProjectPath(in: notification) == path,
                  pendingSaveTask == nil,
                  let loaded = ProjectConfigStore.shared.cached(forProjectPath: path) else { return }
            applyLoadedConfig(loaded)
        }
        .sheet(item: $projectEditor) { editor in
            ProjectEditorSheet(projectID: editor.id, configuration: editor.configuration, viewModel: sidebarViewModel)
        }
    }
}

/// Capture the destination and initial draft together so the first presentation cannot use an empty or stale configuration.
private struct ProjectEditorPresentation: Identifiable {
    let id: String
    let configuration: ProjectConfiguration

    @MainActor
    init(project: Project) {
        id = project.id
        configuration = ProjectConfiguration(project: project)
    }
}

private extension ProjectSettingsView {
    var setupScriptBinding: Binding<String> {
        Binding(
            get: { editorState.setupScript },
            set: { newValue in
                editorState.setupScript = newValue
                scheduleConfigSave()
            }
        )
    }

    var teardownScriptBinding: Binding<String> {
        Binding(
            get: { editorState.teardownScript },
            set: { newValue in
                editorState.teardownScript = newValue
                scheduleConfigSave()
            }
        )
    }

    func loadState() async {
        let projectID = project.id
        let revision = saveRevision
        guard let path = sourceFolder?.path else { return }
        let loadedConfig = await loadConfig(path)
        guard !Task.isCancelled, saveRevision == revision,
              modelContext.resolveProject(projectID: projectID)?.orderedFolders.contains(where: { $0.path == path }) == true else { return }
        applyLoadedConfig(loadedConfig)
    }

    func applyLoadedConfig(_ loadedConfig: AlvearyProjectConfig) {
        editorState.applyLoadedConfig(loadedConfig)
    }

    func bindingForPattern(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard editorState.preservePatterns.indices.contains(index) else {
                    return ""
                }
                return editorState.preservePatterns[index]
            },
            set: { newValue in
                guard editorState.preservePatterns.indices.contains(index) else {
                    return
                }

                editorState.preservePatterns[index] = newValue
                ensureTrailingBlankPatternRow()
                scheduleConfigSave()
            }
        )
    }

    func removePattern(_ index: Int) {
        guard editorState.preservePatterns.indices.contains(index) else {
            return
        }

        editorState.preservePatterns.remove(at: index)
        ensureTrailingBlankPatternRow()
        scheduleConfigSave()
    }

    func updateAction(_ index: Int, _ updatedAction: ProjectSettingsActionDraft) {
        guard editorState.actions.indices.contains(index) else {
            return
        }

        editorState.actions[index] = updatedAction
        scheduleConfigSave()
    }

    func addAction() {
        editorState.actions.append(ProjectSettingsActionDraft())
    }

    func removeAction(_ index: Int) {
        guard editorState.actions.indices.contains(index) else {
            return
        }

        editorState.actions.remove(at: index)
        scheduleConfigSave()
    }

    func ensureTrailingBlankPatternRow() {
        if editorState.preservePatterns.isEmpty {
            editorState.preservePatterns = [""]
            return
        }

        guard editorState.preservePatterns.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        editorState.preservePatterns.append("")
    }

    func scheduleConfigSave() {
        guard let path = sourceFolder?.path else { return }
        let updatedConfig = editorState.prepareConfigForSave()
        pendingSaveTask?.cancel()
        saveRevision &+= 1
        let revision = saveRevision
        pendingSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(300))
                try await ProjectConfigStore.shared.write(updatedConfig, forProjectPath: path)
                guard saveRevision == revision else { return }
                pendingSaveTask = nil
                if let latest = ProjectConfigStore.shared.cached(forProjectPath: path) { applyLoadedConfig(latest) }
            } catch is CancellationError {
                return
            } catch {
                guard saveRevision == revision else { return }
                pendingSaveTask = nil
                screenError = error.localizedDescription
            }
        }
    }

    func persistConfigImmediately() async throws {
        guard let path = sourceFolder?.path else { return }
        let updatedConfig = editorState.prepareConfigForSave()
        pendingSaveTask?.cancel()
        saveRevision &+= 1
        pendingSaveTask = nil
        try await ProjectConfigStore.shared.write(updatedConfig, forProjectPath: path)
    }

}

/// Keep incomplete rows and their identity separate from the normalized configuration written to disk.
struct ProjectSettingsEditorState {
    private var config: AlvearyProjectConfig
    var setupScript: String
    var teardownScript: String
    var preservePatterns: [String]
    var actions: [ProjectSettingsActionDraft]

    init(config: AlvearyProjectConfig) {
        self.config = config
        setupScript = config.setupScript ?? ""
        teardownScript = config.teardownScript ?? ""
        preservePatterns = (config.preservePatterns ?? []) + [""]
        actions = (config.actions ?? []).map(ProjectSettingsActionDraft.init)
    }

    mutating func prepareConfigForSave() -> AlvearyProjectConfig {
        config = config.updatingEditableFields(
            setupScript: setupScript, teardownScript: teardownScript,
            preservePatterns: preservePatterns, actions: actions.compactMap(\.resolvedAction)
        )
        return config
    }

    mutating func applyLoadedConfig(_ loadedConfig: AlvearyProjectConfig) {
        // Both write completion and the store's notification can echo our own save. Rebuilding
        // from that value would erase unfinished actions and replace every focused row's identity.
        guard loadedConfig != config else { return }
        self = Self(config: loadedConfig)
    }
}
