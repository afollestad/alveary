import AgentCLIKit
import SwiftData
import SwiftUI

struct ComposerCapabilities: Sendable {
    let supportedPermissionModes: [PermissionModeOption]
    let supportsMidTurnSteering: Bool
    var supportsPlanMode = false
    var planModeDisabledTooltip: String?
}

struct ConversationView: View {
    let conversation: Conversation
    let agentsManager: any AgentsManager
    let runtimeStore: any ConversationRuntimeStore
    let keepAwakeService: KeepAwakeService
    let modelContext: ModelContext
    let settingsService: SettingsService
    let providerRegistry: ProviderRegistry
    let providerDiscovery: any AgentCLIKit.AgentProviderDiscoveryService
    let worktreeManager: WorktreeManager
    let providerSetup: ProviderSetupService
    let contextWindowCache: any ContextWindowCache
    let fileListManager: FileListManager
    let projectTrustPrompt: ProjectTrustPrompt?
    let isProjectTrustBlocked: Bool
    let onTrustProject: (ProjectTrustPrompt) -> Void
    let onDenyProjectTrust: (ProjectTrustPrompt) -> Void
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let diffViewModel: DiffViewerViewModel
    @Bindable var appState: AppState

    @State private var viewModel: ConversationViewModel
    @State private var composerProviderStatuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] = [:]
    @State private var composerProviderOrdering: [AgentCLIKit.AgentProviderID] = AgentCLIKit.AgentProviderID.allCases

    private var activeWorkingDirectory: String? {
        conversation.thread?.worktreePath ?? conversation.thread?.project?.path
    }

    private var providerDiscoveryProjectURL: URL? {
        conversation.thread?.project.map { URL(fileURLWithPath: CanonicalPath.normalize($0.path), isDirectory: true) }
    }

    private var activeProviderID: String {
        conversation.provider ?? settingsService.current.defaultProvider
    }

    private var activeAgentProviderID: AgentCLIKit.AgentProviderID? {
        AgentCLIKit.AgentProviderID(rawValue: activeProviderID)
    }

    private var activeProviderStatus: AgentCLIKit.AgentProviderStatus? {
        activeAgentProviderID.flatMap { composerProviderStatuses[$0] }
    }

    private var composerCapabilities: ComposerCapabilities {
        let provider = providerRegistry.provider(for: activeProviderID)

        let supportsPlanMode = activeProviderStatus?.definition?.capabilities.supportsPlanMode
            ?? Self.fallbackPlanModeProviderIDs.contains(activeProviderID)
        return ComposerCapabilities(
            supportedPermissionModes: providerPermissionModes(),
            supportsMidTurnSteering: activeProviderStatus?.definition?.capabilities.supportsMidTurnSteering
                ?? provider?.supportsMidTurnSteering
                ?? false,
            supportsPlanMode: supportsPlanMode,
            planModeDisabledTooltip: planModeDisabledTooltip(supportsPlanMode: supportsPlanMode)
        )
    }

    init(
        conversation: Conversation,
        agentsManager: any AgentsManager,
        runtimeStore: any ConversationRuntimeStore,
        keepAwakeService: KeepAwakeService,
        modelContext: ModelContext,
        settingsService: SettingsService,
        providerRegistry: ProviderRegistry,
        providerDiscovery: any AgentCLIKit.AgentProviderDiscoveryService,
        worktreeManager: WorktreeManager,
        providerSetup: ProviderSetupService,
        contextWindowCache: any ContextWindowCache,
        fileListManager: FileListManager,
        projectTrustPrompt: ProjectTrustPrompt? = nil,
        isProjectTrustBlocked: Bool = false,
        onTrustProject: @escaping (ProjectTrustPrompt) -> Void = { _ in },
        onDenyProjectTrust: @escaping (ProjectTrustPrompt) -> Void = { _ in },
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        diffViewModel: DiffViewerViewModel,
        appState: AppState
    ) {
        self.conversation = conversation
        self.agentsManager = agentsManager
        self.runtimeStore = runtimeStore
        self.keepAwakeService = keepAwakeService
        self.modelContext = modelContext
        self.settingsService = settingsService
        self.providerRegistry = providerRegistry
        self.providerDiscovery = providerDiscovery
        self.worktreeManager = worktreeManager
        self.providerSetup = providerSetup
        self.contextWindowCache = contextWindowCache
        self.fileListManager = fileListManager
        self.projectTrustPrompt = projectTrustPrompt
        self.isProjectTrustBlocked = isProjectTrustBlocked
        self.onTrustProject = onTrustProject
        self.onDenyProjectTrust = onDenyProjectTrust
        self.loadSkillCompletions = loadSkillCompletions
        self.diffViewModel = diffViewModel
        self.appState = appState
        _viewModel = State(initialValue: ConversationViewModel(
            conversation: conversation,
            agentsManager: agentsManager,
            runtimeStore: runtimeStore,
            keepAwakeService: keepAwakeService,
            modelContext: modelContext,
            settingsService: settingsService,
            worktreeManager: worktreeManager,
            providerSetup: providerSetup,
            contextWindowCache: contextWindowCache
        ))
    }

    var body: some View {
        let settings = settingsService.current
        let transcriptTypography = TranscriptTypography(settings: settings)

        ChatView(
            viewModel: viewModel,
            conversation: conversation,
            composerCapabilities: composerCapabilities,
            providerOptions: composerProviderOptions,
            modelOptions: composerModelOptions,
            selectedModelOptionID: selectedComposerModelOptionID,
            effortOptions: composerEffortOptions,
            onModelOptionChange: applyComposerModelOptionChange(_:),
            defaultEnterBehavior: settings.defaultEnterBehavior,
            providerID: activeProviderID,
            runtimeStatus: agentsManager.status(for: conversation.id),
            contextWindowCache: contextWindowCache,
            workingDirectory: activeWorkingDirectory,
            projectTrustPrompt: projectTrustPrompt,
            isProjectTrustBlocked: isProjectTrustBlocked,
            onTrustProject: onTrustProject,
            onDenyProjectTrust: onDenyProjectTrust,
            loadFileCompletions: Self.makeFileCompletionLoader(
                fileListManager: fileListManager,
                workingDirectory: activeWorkingDirectory
            ),
            loadSkillCompletions: loadSkillCompletions,
            transcriptTypography: transcriptTypography,
            appState: appState
        )
        .task {
            viewModel.activateViewLifecycle()
            if let path = activeWorkingDirectory {
                await fileListManager.warmCache(for: path)
            }
        }
        .task(id: composerProviderStatusTaskID) {
            await refreshComposerProviderStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsChanged)) { _ in
            Task {
                await refreshComposerProviderStatuses()
            }
        }
        .onDisappear {
            viewModel.deactivateViewLifecycle()
        }
        .onChange(of: activeWorkingDirectory) { _, newPath in
            guard let newPath,
                  case .thread(let selectedThread) = appState.selectedSidebarItem,
                  selectedThread.persistentModelID == conversation.thread?.persistentModelID,
                  let thread = conversation.thread else {
                return
            }

            let threadID = thread.persistentModelID
            let baseRef = thread.project?.baseRef ?? "main"
            let remoteName = thread.project?.remoteName
            let conversationIds = liveConversationIDs(for: threadID)

            Task {
                await fileListManager.warmCache(for: newPath)
                await diffViewModel.switchToDirectory(
                    newPath,
                    baseRef: baseRef,
                    remoteName: remoteName,
                    conversationIds: conversationIds
                )
            }
        }
        .onChange(of: appState.pendingDiffAction) { _, request in
            guard let request,
                  request.conversationID == conversation.persistentModelID else {
                return
            }

            Task {
                let priorDraft = viewModel.flushDraftFromEditor()
                defer {
                    if appState.pendingDiffAction?.id == request.id {
                        appState.pendingDiffAction = nil
                    }
                }

                guard appState.pendingDiffAction?.id == request.id,
                      case .thread(let selectedThread) = appState.selectedSidebarItem,
                      selectedThread.persistentModelID == conversation.thread?.persistentModelID,
                      selectedConversation(
                          in: selectedThread,
                          modelContext: modelContext,
                          appState: appState
                      )?.persistentModelID == conversation.persistentModelID else {
                    return
                }

                do {
                    try await viewModel.queueOrSend(request.message)
                } catch {
                    viewModel.replaceInputDraft(
                        priorDraft.isEffectivelyEmpty ? request.message : priorDraft.text,
                        source: priorDraft.source
                    )
                    if viewModel.lastTurnError == nil {
                        viewModel.lastTurnError = error.localizedDescription
                    }
                }
            }
        }
    }

    func liveConversationIDs(for threadID: PersistentIdentifier) -> Set<String> {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        return Set(((try? modelContext.fetch(descriptor)) ?? []).map(\.id))
    }
}

private extension ConversationView {
    static let fallbackPlanModeProviderIDs: Set<String> = ["claude", "codex"]

    var composerProviderStatusTaskID: String {
        [
            providerDiscoveryProjectURL?.path ?? "",
            activeProviderID,
            settingsService.current.defaultProvider,
            settingsService.current.disabledProviderIDs.sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

    var composerProviderOptions: [ChatComposerActionRowView.MenuOption] {
        let options = composerProviderOrdering.compactMap { providerId -> ChatComposerActionRowView.MenuOption? in
            let rawValue = providerId.rawValue
            guard AppSettings.supportedProviderIDs.contains(rawValue) else {
                return nil
            }
            let status = composerProviderStatuses[providerId]
            let isActiveProvider = rawValue == activeProviderID
            let isSelectable = status.map(isSelectableComposerProvider(_:))
                ?? settingsService.current.isProviderEnabled(rawValue)
            guard isActiveProvider || isSelectable else {
                return nil
            }
            return .init(value: rawValue, title: providerDisplayName(for: providerId))
        }

        if !options.isEmpty {
            return options
        }
        return [.init(value: activeProviderID, title: activeProviderID.capitalized)]
    }

    var composerModelOptions: [ChatComposerActionRowView.MenuOption] {
        let selectedModel = conversation.thread?.model ?? AppSettings.defaultModelValue
        let agentModelOptions = modelOptions(for: activeAgentProviderID)
        return AgentModelOptionSelection.menuItems(
            in: agentModelOptions,
            selectedModel: selectedModel,
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        ).map { item in
            ChatComposerActionRowView.MenuOption(value: item.value, title: item.title)
        }
    }

    var selectedComposerModelOptionID: String {
        AgentModelOptionSelection.pickerValue(
            in: modelOptions(for: activeAgentProviderID),
            matching: conversation.thread?.model ?? AppSettings.defaultModelValue
        )
    }

    var composerEffortOptions: [ChatComposerActionRowView.MenuOption] {
        let selectedModel = conversation.thread?.model ?? AppSettings.defaultModelValue
        return AgentModelOptionSelection.effortOptions(
            in: modelOptions(for: activeAgentProviderID),
            selectedModel: selectedModel
        ).map { option in
            ChatComposerActionRowView.MenuOption(value: option.value, title: option.label)
        }
    }

    func refreshComposerProviderStatuses() async {
        async let ordering = providerDiscovery.stableProviderOrdering()
        async let statuses = providerDiscovery.providerStatuses(projectURL: providerDiscoveryProjectURL)
        composerProviderOrdering = await ordering
        composerProviderStatuses = await statuses
    }

    func isSelectableComposerProvider(_ status: AgentCLIKit.AgentProviderStatus) -> Bool {
        status.isEnabled && status.isInstalled && status.isSetupReady
    }

    func providerDisplayName(for providerId: AgentCLIKit.AgentProviderID) -> String {
        composerProviderStatuses[providerId]?.definition?.displayName ?? providerId.rawValue.capitalized
    }

    func modelOptions(for providerId: AgentCLIKit.AgentProviderID?) -> [AgentCLIKit.AgentModelOption] {
        guard let providerId else {
            return []
        }
        if let options = composerProviderStatuses[providerId]?.modelOptions, !options.isEmpty {
            return options
        }
        return AgentCLIKit.AgentDefaultModelOptions.providerDefault(for: providerId)
    }

    func applyComposerModelOptionChange(_ optionID: String) {
        let options = modelOptions(for: activeAgentProviderID)
        let storedModel = AgentModelOptionSelection.storedModelValue(in: options, matching: optionID)
        _ = viewModel.applyModelChange(
            storedModel,
            effortOptions: AgentModelOptionSelection.effortOptions(in: options, selectedModel: storedModel),
            defaultEffort: AgentModelOptionSelection.defaultEffortValue(in: options, selectedModel: storedModel)
        )
    }

    func providerPermissionModes() -> [PermissionModeOption] {
        if let modes = activeProviderStatus?.definition?.supportedPermissionModes {
            return modes.filter { $0.value != "plan" }.map { option in
                PermissionModeOption(value: option.value, label: option.label, description: option.description)
            }
        }
        return (providerRegistry.provider(for: activeProviderID)?.supportedPermissionModes ?? [])
            .filter { $0.value != "plan" }
    }

    func planModeDisabledTooltip(supportsPlanMode: Bool) -> String? {
        guard supportsPlanMode else {
            return "Plan mode is not supported by this agent."
        }
        guard activeProviderID == "codex" else {
            return nil
        }
        return hasConcreteCodexModelSelection() ? nil : "Choose a concrete Codex model to use plan mode."
    }

    func hasConcreteCodexModelSelection() -> Bool {
        if let storedModel = conversation.thread?.model?.trimmingCharacters(in: .whitespacesAndNewlines),
           !storedModel.isEmpty,
           storedModel != AppSettings.defaultModelValue {
            return true
        }
        let options = modelOptions(for: activeAgentProviderID)
        let selectedModel = conversation.thread?.model ?? AppSettings.defaultModelValue
        guard let model = AgentModelOptionSelection.option(in: options, matching: selectedModel)?.model else {
            return false
        }
        return !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private extension ConversationView {
    static func makeFileCompletionLoader(
        fileListManager: FileListManager,
        workingDirectory: String?
    ) -> @Sendable () async -> [String] {
        {
            guard let workingDirectory else {
                return []
            }
            return await fileListManager.files(for: workingDirectory)
        }
    }
}
