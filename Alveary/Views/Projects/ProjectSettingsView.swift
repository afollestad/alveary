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
    @Bindable var appState: AppState

    private let loadConfig: @MainActor (String) async -> AlvearyProjectConfig
    private let sidebarViewModel: SidebarViewModel

    @Environment(\.modelContext) private var modelContext
    @State private var config: AlvearyProjectConfig
    @State private var setupScript: String
    @State private var teardownScript: String
    @State private var preservePatterns: [String]
    @State private var actions: [ProjectSettingsActionDraft]
    @State private var pendingSaveTask: Task<Void, Never>?
    @State private var screenError: String?

    init(
        project: Project,
        appState: AppState,
        sidebarViewModel: SidebarViewModel,
        initialConfig: AlvearyProjectConfig = .empty,
        // The editor is the surface that must see an edit made outside the app, so it
        // reloads rather than accepting whatever the store already holds.
        loadConfig: @escaping @MainActor (String) async -> AlvearyProjectConfig = { projectPath in
            await ProjectConfigStore.shared.reload(forProjectPath: projectPath)
        }
    ) {
        self.project = project
        self.appState = appState
        self.sidebarViewModel = sidebarViewModel
        self.loadConfig = loadConfig

        let editorState = ProjectSettingsEditorState(config: initialConfig)
        _config = State(initialValue: initialConfig)
        _setupScript = State(initialValue: editorState.setupScript)
        _teardownScript = State(initialValue: editorState.teardownScript)
        _preservePatterns = State(initialValue: editorState.preservePatterns)
        _actions = State(initialValue: editorState.actions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ProjectSettingsHeader(
                    projectPath: project.path,
                    projectName: Binding(
                        get: { project.name },
                        set: { newValue in
                            project.name = newValue
                            saveProject()
                        }
                    )
                )

                if let screenError {
                    InlineBanner(
                        message: screenError,
                        severity: .error,
                        autoDismissAfter: nil,
                        onDismiss: { self.screenError = nil }
                    )
                }

                if project.isGitRepository {
                    ProjectSettingsRepositoryCard(project: project)
                }

                ProjectSettingsScriptsCard(
                    setupScript: setupScriptBinding,
                    teardownScript: teardownScriptBinding
                )

                ProjectSettingsPreservePatternsCard(
                    patterns: preservePatterns,
                    bindingForPattern: bindingForPattern,
                    onRemovePattern: removePattern
                )

                ProjectSettingsActionsCard(
                    actions: actions,
                    onUpdateAction: updateAction,
                    onAddAction: addAction,
                    onRemoveAction: removeAction
                )
            }
            .padding(28)
        }
        .task(id: project.path) {
            await loadState()
        }
    }
}

private extension ProjectSettingsView {
    var setupScriptBinding: Binding<String> {
        Binding(
            get: { setupScript },
            set: { newValue in
                setupScript = newValue
                scheduleConfigSave()
            }
        )
    }

    var teardownScriptBinding: Binding<String> {
        Binding(
            get: { teardownScript },
            set: { newValue in
                teardownScript = newValue
                scheduleConfigSave()
            }
        )
    }

    func loadState() async {
        let loadedConfig = await loadConfig(project.path)
        let editorState = ProjectSettingsEditorState(config: loadedConfig)

        config = loadedConfig
        setupScript = editorState.setupScript
        teardownScript = editorState.teardownScript
        preservePatterns = editorState.preservePatterns
        actions = editorState.actions
    }

    func bindingForPattern(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard preservePatterns.indices.contains(index) else {
                    return ""
                }
                return preservePatterns[index]
            },
            set: { newValue in
                guard preservePatterns.indices.contains(index) else {
                    return
                }

                preservePatterns[index] = newValue
                ensureTrailingBlankPatternRow()
                scheduleConfigSave()
            }
        )
    }

    func removePattern(_ index: Int) {
        guard preservePatterns.indices.contains(index) else {
            return
        }

        preservePatterns.remove(at: index)
        ensureTrailingBlankPatternRow()
        scheduleConfigSave()
    }

    func updateAction(_ index: Int, _ updatedAction: ProjectSettingsActionDraft) {
        guard actions.indices.contains(index) else {
            return
        }

        actions[index] = updatedAction
        scheduleConfigSave()
    }

    func addAction() {
        actions.append(ProjectSettingsActionDraft())
    }

    func removeAction(_ index: Int) {
        guard actions.indices.contains(index) else {
            return
        }

        actions.remove(at: index)
        scheduleConfigSave()
    }

    func ensureTrailingBlankPatternRow() {
        if preservePatterns.isEmpty {
            preservePatterns = [""]
            return
        }

        guard preservePatterns.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        preservePatterns.append("")
    }

    func scheduleConfigSave() {
        let updatedConfig = currentEditableConfig()
        config = updatedConfig
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(300))
                try await updatedConfig.write(projectPath: project.path)
                recordWrittenConfig(updatedConfig)
            } catch is CancellationError {
                return
            } catch {
                screenError = error.localizedDescription
            }
        }
    }

    func persistConfigImmediately() async throws {
        let updatedConfig = currentEditableConfig()
        config = updatedConfig
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        try await updatedConfig.write(projectPath: project.path)
        recordWrittenConfig(updatedConfig)
    }

    /// Handing the written config to the store rather than only announcing the write
    /// keeps other surfaces from re-reading a file this view already has, and the store
    /// posts the change notification for us. Takes what was written rather than
    /// re-deriving it, because the editor's state can move while the write runs.
    func recordWrittenConfig(_ config: AlvearyProjectConfig) {
        ProjectConfigStore.shared.store(config, forProjectPath: project.path)
    }

    func currentEditableConfig() -> AlvearyProjectConfig {
        config.updatingEditableFields(
            setupScript: setupScript,
            teardownScript: teardownScript,
            preservePatterns: preservePatterns,
            actions: actions.compactMap(\.resolvedAction)
        )
    }

    func saveProject() {
        do {
            try modelContext.save()
        } catch {
            screenError = error.localizedDescription
        }
    }

}

private struct ProjectSettingsEditorState {
    let setupScript: String
    let teardownScript: String
    let preservePatterns: [String]
    let actions: [ProjectSettingsActionDraft]

    init(config: AlvearyProjectConfig) {
        setupScript = config.setupScript ?? ""
        teardownScript = config.teardownScript ?? ""
        preservePatterns = (config.preservePatterns ?? []) + [""]
        actions = (config.actions ?? []).map(ProjectSettingsActionDraft.init)
    }
}
