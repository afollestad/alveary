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

    private let loadConfig: @Sendable (String) async -> AlvearyProjectConfig

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
        initialConfig: AlvearyProjectConfig = .empty,
        loadConfig: @escaping @Sendable (String) async -> AlvearyProjectConfig = { projectPath in
            await AlvearyProjectConfig(projectPath: projectPath)
        }
    ) {
        self.project = project
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
                    InlineBanner(message: screenError, severity: .error, autoDismissAfter: nil) {
                        self.screenError = nil
                    }
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
