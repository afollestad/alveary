import AgentCLIKit
import SwiftData
import SwiftUI

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
    let runtimeStatus: ActivitySignal
    let projectTrustPrompt: ProjectTrustPrompt?
    let isProjectTrustBlocked: Bool
    let onTrustProject: (ProjectTrustPrompt) -> Void
    let onDenyProjectTrust: (ProjectTrustPrompt) -> Void
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let diffViewModel: DiffViewerViewModel
    @Bindable var appState: AppState

    @State var viewModel: ConversationViewModel
    @State var composerProviderStatuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus]
    @State var composerProviderOrdering: [AgentCLIKit.AgentProviderID]

    var composerCapabilities: ComposerCapabilities {
        let provider = providerRegistry.provider(for: activeProviderID)

        let supportsPlanMode = activeProviderStatus?.definition?.capabilities.supportsPlanMode
            ?? Self.fallbackPlanModeProviderIDs.contains(activeProviderID)
        return ComposerCapabilities(
            supportedPermissionModes: providerPermissionModes(),
            supportsMidTurnSteering: activeProviderStatus?.definition?.capabilities.supportsMidTurnSteering
                ?? provider?.supportsMidTurnSteering
                ?? false,
            supportsPlanMode: supportsPlanMode,
            supportsSpeedMode: activeProviderStatus?.definition?.capabilities.supportsSpeedMode ?? false,
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
        runtimeStatus: ActivitySignal,
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
        self.runtimeStatus = runtimeStatus
        self.projectTrustPrompt = projectTrustPrompt
        self.isProjectTrustBlocked = isProjectTrustBlocked
        self.onTrustProject = onTrustProject
        self.onDenyProjectTrust = onDenyProjectTrust
        self.loadSkillCompletions = loadSkillCompletions
        self.diffViewModel = diffViewModel
        self.appState = appState
        let providerStatusCacheKey = Self.composerProviderStatusCacheKey(
            projectURL: conversation.thread?.project.map {
                URL(fileURLWithPath: CanonicalPath.normalize($0.path), isDirectory: true)
            },
            activeProviderID: conversation.provider ?? settingsService.current.defaultProvider,
            settings: settingsService.current
        )
        let providerStatusSnapshot = ComposerProviderStatusCache.snapshot(for: providerStatusCacheKey)
        _composerProviderStatuses = State(initialValue: providerStatusSnapshot?.statuses ?? [:])
        _composerProviderOrdering = State(initialValue: providerStatusSnapshot?.ordering ?? AgentCLIKit.AgentProviderID.allCases)
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
            reasoningConfiguration: composerReasoningConfiguration,
            defaultEnterBehavior: settings.defaultEnterBehavior,
            providerID: activeProviderID,
            runtimeStatus: runtimeStatus,
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
        .onChange(of: runtimeStatus) { _, newStatus in
            guard newStatus == .idle else {
                return
            }
            viewModel.scheduleQueueDrainIfNeeded()
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
                    conversationIds: conversationIds,
                    scope: appState.isRightPaneVisible ? .full : .toolbarStatsOnly
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
                    viewModel.normalizeUnsupportedSpeedModeIfNeeded(supportsSpeedMode: composerCapabilities.supportsSpeedMode)
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
        Self.composerProviderStatusCacheKey(
            projectURL: providerDiscoveryProjectURL,
            activeProviderID: activeProviderID,
            settings: settingsService.current
        )
    }

    var composerReasoningConfiguration: ChatComposerActionRowView.ReasoningConfiguration {
        ChatComposerActionRowView.ReasoningConfiguration(
            selection: composerReasoningSelection,
            modelGroups: composerReasoningModelGroups,
            hasStartedThread: conversation.thread?.hasCompletedInitialSetup == true,
            onEffortChange: applyComposerReasoningEffortChange(_:),
            onSpeedChange: applyComposerReasoningSpeedChange(_:),
            onModelChange: applyComposerReasoningModelChange(_:)
        )
    }

    var composerReasoningSelection: ChatComposerActionRowView.ReasoningSelection {
        let selectedModel = selectedComposerModelOptionID(for: activeAgentProviderID)
        let options = modelOptions(for: activeAgentProviderID)
        let modelTitle = AgentModelOptionSelection.menuItems(
            in: options,
            selectedModel: selectedModel,
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        ).first { $0.value == selectedModel }?.title ?? ChatComposerTextSupport.modelLabel(for: selectedModel)
        let effortOptions = reasoningEffortOptions(for: activeAgentProviderID, selectedModel: selectedModel)
        let effortValue = conversation.thread?.effort ?? AppSettings.defaultEffortLevel
        let effortTitle = effortOptions.first { $0.value == effortValue }?.title
            ?? ChatComposerTextSupport.effortLabel(for: effortValue)
        let speedMode = composerCapabilities.supportsSpeedMode ? conversation.thread?.normalizedSpeedMode ?? .standard : .standard

        return ChatComposerActionRowView.ReasoningSelection(
            providerID: activeProviderID,
            providerTitle: activeAgentProviderID.map(providerDisplayName(for:)) ?? activeProviderID.capitalized,
            modelID: selectedModel,
            modelTitle: modelTitle,
            effortValue: effortValue,
            effortTitle: effortTitle,
            effortOptions: effortOptions,
            speedMode: speedMode,
            supportsSpeedMode: composerCapabilities.supportsSpeedMode
        )
    }

    var composerReasoningModelGroups: [ChatComposerActionRowView.ReasoningModelGroup] {
        let hasStartedThread = conversation.thread?.hasCompletedInitialSetup == true
        if hasStartedThread {
            guard let providerID = activeAgentProviderID else {
                return []
            }
            return [reasoningModelGroup(for: providerID, providerTitle: nil)]
        }

        return composerProviderOrdering.compactMap { providerID in
            let rawValue = providerID.rawValue
            guard AppSettings.supportedProviderIDs.contains(rawValue) else {
                return nil
            }
            let status = composerProviderStatuses[providerID]
            let isSelectable = status.map(isSelectableComposerProvider(_:))
                ?? settingsService.current.isProviderEnabled(rawValue)
            guard isSelectable else {
                return nil
            }
            return reasoningModelGroup(for: providerID, providerTitle: providerDisplayName(for: providerID))
        }
    }

    func refreshComposerProviderStatuses() async {
        async let ordering = providerDiscovery.stableProviderOrdering()
        async let statuses = providerDiscovery.providerStatuses(projectURL: providerDiscoveryProjectURL)
        let resolvedOrdering = await ordering
        let resolvedStatuses = await statuses
        composerProviderOrdering = resolvedOrdering
        composerProviderStatuses = resolvedStatuses
        // Thread switches create a fresh `ConversationView`; seed it from the
        // last successful discovery result so model-scoped effort labels do not
        // temporarily disappear while async provider discovery warms back up.
        ComposerProviderStatusCache.store(
            .init(ordering: resolvedOrdering, statuses: resolvedStatuses),
            for: composerProviderStatusTaskID
        )
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

    func reasoningModelGroup(
        for providerID: AgentCLIKit.AgentProviderID,
        providerTitle: String?
    ) -> ChatComposerActionRowView.ReasoningModelGroup {
        let selectedModel = providerID.rawValue == activeProviderID
            ? conversation.thread?.model ?? AppSettings.defaultModelValue
            : AppSettings.defaultModelValue
        let options = AgentModelOptionSelection.menuItems(
            in: modelOptions(for: providerID),
            selectedModel: selectedModel,
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        ).map { item in
            ChatComposerActionRowView.ReasoningModelOption(
                providerID: providerID.rawValue,
                value: item.value,
                title: item.title
            )
        }
        return ChatComposerActionRowView.ReasoningModelGroup(
            providerID: providerID.rawValue,
            providerTitle: providerTitle,
            options: options
        )
    }

    func selectedComposerModelOptionID(for providerID: AgentCLIKit.AgentProviderID?) -> String {
        AgentModelOptionSelection.pickerValue(
            in: modelOptions(for: providerID),
            matching: conversation.thread?.model ?? AppSettings.defaultModelValue
        )
    }

    func reasoningEffortOptions(
        for providerID: AgentCLIKit.AgentProviderID?,
        selectedModel: String
    ) -> [ChatComposerActionRowView.MenuOption] {
        AgentModelOptionSelection.effortOptions(
            in: modelOptions(for: providerID),
            selectedModel: selectedModel
        ).map { option in
            ChatComposerActionRowView.MenuOption(value: option.value, title: option.label)
        }
    }

    func applyComposerReasoningEffortChange(_ effort: String) -> Bool {
        guard viewModel.canApplySettingsChange else {
            return false
        }
        let currentEffort = conversation.thread?.effort ?? AppSettings.defaultEffortLevel
        guard currentEffort != effort else {
            return true
        }
        _ = viewModel.applyEffortChange(effort)
        return (conversation.thread?.effort ?? AppSettings.defaultEffortLevel) == effort
    }

    func applyComposerReasoningModelChange(
        _ request: ChatComposerActionRowView.ReasoningModelSelectionRequest
    ) -> ChatComposerActionRowView.ReasoningModelSelectionOutcome {
        guard composerReasoningModelGroups.contains(where: { group in
            group.providerID == request.providerID && group.options.contains { $0.value == request.modelID }
        }),
        let requestProviderID = AgentCLIKit.AgentProviderID(rawValue: request.providerID) else {
            return .rejected
        }

        let previousProviderID = activeProviderID
        let previousModelID = selectedComposerModelOptionID(for: activeAgentProviderID)
        guard previousProviderID != request.providerID || previousModelID != request.modelID else {
            return .unchanged(composerReasoningSelection)
        }

        let requestOptions = modelOptions(for: requestProviderID)
        let storedModel = AgentModelOptionSelection.storedModelValue(in: requestOptions, matching: request.modelID)
        let requestEffortOptions = AgentModelOptionSelection.effortOptions(in: requestOptions, selectedModel: storedModel)
        let defaultEffort = AgentModelOptionSelection.defaultEffortValue(in: requestOptions, selectedModel: storedModel)
        let requestSupportsSpeedMode = composerProviderStatuses[requestProviderID]?.definition?.capabilities.supportsSpeedMode ?? false
        let didApply: Bool

        if previousProviderID == request.providerID {
            guard viewModel.canApplySettingsChange else {
                return .rejected
            }
            _ = viewModel.applyModelChange(
                storedModel,
                effortOptions: requestEffortOptions,
                defaultEffort: defaultEffort,
                supportsSpeedMode: requestSupportsSpeedMode
            )
            didApply = activeProviderID == request.providerID &&
                selectedComposerModelOptionID(for: activeAgentProviderID) == request.modelID
        } else {
            guard conversation.thread?.hasCompletedInitialSetup != true else {
                return .rejected
            }
            didApply = viewModel.applyPreStartupProviderModelChange(
                providerID: request.providerID,
                model: storedModel,
                effortOptions: requestEffortOptions,
                defaultEffort: defaultEffort,
                supportsSpeedMode: requestSupportsSpeedMode
            ) && activeProviderID == request.providerID &&
                selectedComposerModelOptionID(for: requestProviderID) == request.modelID
        }

        guard didApply else {
            return .rejected
        }

        return .applied(selection: composerReasoningSelection)
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
