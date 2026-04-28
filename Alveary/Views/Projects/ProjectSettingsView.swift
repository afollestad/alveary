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
    private let notificationManager: any NotificationManager

    @Environment(\.modelContext) private var modelContext
    @State private var config: AlvearyProjectConfig
    @State private var setupScript: String
    @State private var teardownScript: String
    @State private var preservePatterns: [String]
    @State private var actions: [ProjectSettingsActionDraft]
    @State private var pendingSaveTask: Task<Void, Never>?
    @State private var screenError: String?
    @State private var pendingRestoreThread: AgentThread?

    init(
        project: Project,
        notificationManager: any NotificationManager,
        initialConfig: AlvearyProjectConfig = .empty,
        loadConfig: @escaping @Sendable (String) async -> AlvearyProjectConfig = { projectPath in
            await AlvearyProjectConfig(projectPath: projectPath)
        }
    ) {
        self.project = project
        self.notificationManager = notificationManager
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

                ProjectSettingsArchivedThreadsCard(
                    threads: archivedThreads,
                    onRequestRestoreThread: { pendingRestoreThread = $0 }
                )
            }
            .padding(28)
        }
        .task(id: project.path) {
            await loadState()
        }
        .confirmationDialog(
            "Restore archived thread?",
            isPresented: Binding(
                get: { pendingRestoreThread != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRestoreThread = nil
                    }
                }
            ),
            presenting: pendingRestoreThread
        ) { thread in
            Button("Restore") {
                pendingRestoreThread = nil
                restoreArchivedThread(thread)
            }

            Button("Cancel", role: .cancel) {
                pendingRestoreThread = nil
            }
        } message: { thread in
            Text(restoreConfirmationMessage(for: thread))
        }
    }
}

@MainActor
func restoreProjectSettingsArchivedThread(
    _ thread: AgentThread,
    modelContext: ModelContext,
    notificationManager: any NotificationManager
) throws {
    guard let dbThread = modelContext.resolveThread(id: thread.persistentModelID) else {
        return
    }

    dbThread.prepareForRestore()
    try modelContext.save()
    // SwiftData does not emit `.agentStatusChanged` on restore, so the dock badge would miss the
    // newly-unarchived unread conversations without this explicit refresh.
    notificationManager.refreshBadgeCount()
}

func projectSettingsRestoreConfirmationMessage(for thread: AgentThread) -> String {
    "Restoring \"\(thread.displayName())\" puts it back in the project list. Local transcript and worktree metadata stay in Alveary. "
        + "The next run starts a fresh provider session, and Alveary attaches a restore summary to your next message."
}

private extension ProjectSettingsView {
    var archivedThreads: [AgentThread] {
        let projectPath = project.path
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt != nil && thread.project?.path == projectPath
            }
        )
        let threads = (try? modelContext.fetch(descriptor)) ?? []
        return threads.sorted { lhs, rhs in
            let leftDate = lhs.archivedAt ?? .distantPast
            let rightDate = rhs.archivedAt ?? .distantPast
            return leftDate > rightDate
        }
    }

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

    func restoreArchivedThread(_ thread: AgentThread) {
        do {
            try restoreProjectSettingsArchivedThread(
                thread,
                modelContext: modelContext,
                notificationManager: notificationManager
            )
        } catch {
            screenError = error.localizedDescription
        }
    }

    func restoreConfirmationMessage(for thread: AgentThread) -> String {
        projectSettingsRestoreConfirmationMessage(for: thread)
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
