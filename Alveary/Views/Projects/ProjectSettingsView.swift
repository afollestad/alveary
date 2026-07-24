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

    private let loadConfig: @Sendable (String) async -> AlvearyProjectConfig
    private let sidebarViewModel: SidebarViewModel
    private let voiceInputLifecycleController: VoiceInputLifecycleController?

    @Environment(\.modelContext) private var modelContext
    @State private var config: AlvearyProjectConfig
    @State private var setupScript: String
    @State private var teardownScript: String
    @State private var preservePatterns: [String]
    @State private var actions: [ProjectSettingsActionDraft]
    @State private var pendingSaveTask: Task<Void, Never>?
    @State private var screenError: String?
    @State private var pendingRestoreThread: AgentThread?
    @State private var pendingDeleteThread: AgentThread?
    // Non-nil once the archived-threads query is allowed to run for that project path.
    @State private var archivedThreadsProjectPath: String?

    init(
        project: Project,
        appState: AppState,
        sidebarViewModel: SidebarViewModel,
        voiceInputLifecycleController: VoiceInputLifecycleController? = nil,
        initialConfig: AlvearyProjectConfig = .empty,
        // Snapshot-only seed; production always mounts the archived card after the first yield.
        initialArchivedThreadsSectionMounted: Bool = false,
        loadConfig: @escaping @Sendable (String) async -> AlvearyProjectConfig = { projectPath in
            await AlvearyProjectConfig(projectPath: projectPath)
        }
    ) {
        self.project = project
        self.appState = appState
        self.sidebarViewModel = sidebarViewModel
        self.voiceInputLifecycleController = voiceInputLifecycleController
        self.loadConfig = loadConfig

        let editorState = ProjectSettingsEditorState(config: initialConfig)
        _config = State(initialValue: initialConfig)
        _setupScript = State(initialValue: editorState.setupScript)
        _teardownScript = State(initialValue: editorState.teardownScript)
        _preservePatterns = State(initialValue: editorState.preservePatterns)
        _actions = State(initialValue: editorState.actions)
        _archivedThreadsProjectPath = State(initialValue: initialArchivedThreadsSectionMounted ? project.path : nil)
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

                if archivedThreadsProjectPath == project.path {
                    ProjectSettingsArchivedThreadsSection(
                        projectPath: project.path,
                        onRequestRestoreThread: { pendingRestoreThread = $0 },
                        onRequestDeleteThread: { pendingDeleteThread = $0 }
                    )
                }
            }
            .padding(28)
        }
        // Keep the archived-thread query off the frame that paints the selected project.
        // Path-keyed rather than a Bool so a reused view identity cannot show the
        // previous project's archived rows for a frame.
        .task(id: project.path) {
            await Task.yield()
            archivedThreadsProjectPath = project.path
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
                Task { await restoreArchivedThread(thread) }
            }

            Button("Cancel", role: .cancel) {
                pendingRestoreThread = nil
            }
        } message: { thread in
            Text(restoreConfirmationMessage(for: thread))
        }
        .confirmationDialog(
            "Delete thread?",
            isPresented: Binding(
                get: { pendingDeleteThread != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteThread = nil
                    }
                }
            ),
            presenting: pendingDeleteThread
        ) { thread in
            Button("Delete", role: .destructive) {
                Task { await deleteArchivedThread(thread) }
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteThread = nil
            }
        } message: { thread in
            Text(deleteConfirmationMessage(for: thread))
        }
    }
}

func projectSettingsRestoreConfirmationMessage(for thread: AgentThread) -> String {
    "Restoring \"\(thread.displayName())\" puts it back in the project list. Local transcript and worktree metadata stay in Alveary. "
        + "The next run starts a fresh provider session, and Alveary attaches a restore summary to your next message."
}

@MainActor
func deleteProjectSettingsArchivedThread(
    _ thread: AgentThread,
    appState: AppState,
    sidebarViewModel: SidebarViewModel,
    voiceInputLifecycleController: VoiceInputLifecycleController? = nil
) async throws {
    let threadID = thread.persistentModelID
    let previousSelectedItem = appState.selectedSidebarItem
    let previousBookmark = appState.previousSelection
    let previousConversationIDs = appState.selectedConversationIDs
    let replacementItem = thread.project.map(SidebarItem.project)

    // Archived rows are usually not selected, but stale selection/bookmark state can still
    // point at them after external routing or restore fallback.
    if case .thread(let selectedThread) = appState.selectedSidebarItem,
       selectedThread.persistentModelID == threadID {
        appState.selectedSidebarItem = replacementItem
    }

    if case .threadId(let bookmarkedID) = appState.previousSelection,
       bookmarkedID == threadID {
        appState.previousSelection = replacementItem.flatMap(AppState.SidebarBookmark.init)
    }

    appState.selectedConversationIDs.removeValue(forKey: threadID)

    do {
        try await sidebarViewModel.deleteThread(thread)
    } catch let error as SidebarViewModelError where error.isPostCommitCleanupFailure {
        throw error
    } catch {
        if voiceInputLifecycleController?.isModelPreparationModalPresented != true {
            appState.selectedSidebarItem = previousSelectedItem
            appState.previousSelection = previousBookmark
            appState.selectedConversationIDs = previousConversationIDs
        }
        throw error
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

    func restoreArchivedThread(_ thread: AgentThread) async {
        do {
            try await sidebarViewModel.restoreThread(thread)
        } catch {
            screenError = error.localizedDescription
        }
    }

    func deleteArchivedThread(_ thread: AgentThread) async {
        pendingDeleteThread = nil
        do {
            try await deleteProjectSettingsArchivedThread(
                thread,
                appState: appState,
                sidebarViewModel: sidebarViewModel,
                voiceInputLifecycleController: voiceInputLifecycleController
            )
        } catch {
            screenError = error.localizedDescription
        }
    }

    func restoreConfirmationMessage(for thread: AgentThread) -> String {
        projectSettingsRestoreConfirmationMessage(for: thread)
    }

    func deleteConfirmationMessage(for thread: AgentThread) -> String {
        threadDeleteConfirmationMessage(for: thread)
    }
}

/// Project-mode archived rows, newest archive first.
///
/// Split from the query so the ordering and the fallback-mode filter stay testable
/// without mounting the view.
@MainActor
func projectSettingsArchivedThreads(_ threads: [AgentThread]) -> [AgentThread] {
    threads
        .filter { $0.effectiveMode == .project }
        .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
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
