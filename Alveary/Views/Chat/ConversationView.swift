import AgentCLIKit
import SwiftData
import SwiftUI

struct ConversationView: View {
    let conversation: Conversation
    let modelContext: ModelContext
    let settingsService: SettingsService
    let providerRegistry: ProviderRegistry
    let providerDiscovery: any AgentCLIKit.AgentProviderDiscoveryService
    let contextWindowCache: any ContextWindowCache
    let fileListManager: FileListManager
    let voiceInputService: any VoiceInputService
    let voiceInputLifecycleController: VoiceInputLifecycleController
    let runtimeStatus: ActivitySignal
    let projectTrustPrompt: ProjectTrustPrompt?
    let isProjectTrustBlocked: Bool
    let onTrustProject: (ProjectTrustPrompt) -> Void
    let onDenyProjectTrust: (ProjectTrustPrompt) -> Void
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let diffViewModel: DiffViewerViewModel
    let diffViewerSwitchScope: @MainActor () -> DiffViewerSwitchScope
    let availableProjects: [Project]
    let onSelectDraftProject: (String) -> Void
    @Bindable var appState: AppState

    @State var controllerLease: ConversationControllerLease
    @State var composerProviderStatuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus]
    @State var composerProviderOrdering: [AgentCLIKit.AgentProviderID]
    @State var hasLoadedComposerProviderStatuses: Bool

    var composerCapabilities: ComposerCapabilities {
        let provider = providerRegistry.provider(for: activeProviderID)

        let supportsPlanMode = activeProviderStatus?.definition?.capabilities.supportsPlanMode
            ?? Self.fallbackPlanModeProviderIDs.contains(activeProviderID)
        let activeCapabilities = activeProviderStatus?.definition?.capabilities
        let supportsGoalMode = activeCapabilities?.supportsGoalMode ?? false
        let supportsExistingSessionGoalStart = activeCapabilities?.supportsExistingSessionGoalStart ?? false
        return ComposerCapabilities(
            supportedPermissionModes: providerPermissionModes(),
            supportsMidTurnSteering: activeCapabilities?.supportsMidTurnSteering
                ?? provider?.supportsMidTurnSteering
                ?? false,
            supportsGoalMode: supportsGoalMode,
            supportsExistingSessionGoalStart: supportsExistingSessionGoalStart,
            supportsPlanMode: supportsPlanMode,
            supportsSpeedMode: activeCapabilities?.supportsSpeedMode ?? false,
            supportsLocalImageInput: activeCapabilities?.supportsLocalImageInput ?? false,
            goalModeDisabledTooltip: goalModeDisabledTooltip(
                supportsGoalMode: supportsGoalMode,
                supportsExistingSessionGoalStart: supportsExistingSessionGoalStart
            ),
            planModeDisabledTooltip: planModeDisabledTooltip(supportsPlanMode: supportsPlanMode)
        )
    }

    init(
        conversation: Conversation,
        conversationControllerRegistry: any ConversationControllerRegistry,
        modelContext: ModelContext,
        settingsService: SettingsService,
        providerRegistry: ProviderRegistry,
        providerDiscovery: any AgentCLIKit.AgentProviderDiscoveryService,
        contextWindowCache: any ContextWindowCache,
        fileListManager: FileListManager,
        voiceInputService: any VoiceInputService,
        voiceInputLifecycleController: VoiceInputLifecycleController,
        runtimeStatus: ActivitySignal,
        projectTrustPrompt: ProjectTrustPrompt? = nil,
        isProjectTrustBlocked: Bool = false,
        onTrustProject: @escaping (ProjectTrustPrompt) -> Void = { _ in },
        onDenyProjectTrust: @escaping (ProjectTrustPrompt) -> Void = { _ in },
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        diffViewModel: DiffViewerViewModel,
        diffViewerSwitchScope: @escaping @MainActor () -> DiffViewerSwitchScope,
        availableProjects: [Project] = [],
        onSelectDraftProject: @escaping (String) -> Void = { _ in },
        appState: AppState
    ) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.settingsService = settingsService
        self.providerRegistry = providerRegistry
        self.providerDiscovery = providerDiscovery
        self.contextWindowCache = contextWindowCache
        self.fileListManager = fileListManager
        self.voiceInputService = voiceInputService
        self.voiceInputLifecycleController = voiceInputLifecycleController
        self.runtimeStatus = runtimeStatus
        self.projectTrustPrompt = projectTrustPrompt
        self.isProjectTrustBlocked = isProjectTrustBlocked
        self.onTrustProject = onTrustProject
        self.onDenyProjectTrust = onDenyProjectTrust
        self.loadSkillCompletions = loadSkillCompletions
        self.diffViewModel = diffViewModel
        self.diffViewerSwitchScope = diffViewerSwitchScope
        self.availableProjects = availableProjects
        self.onSelectDraftProject = onSelectDraftProject
        self.appState = appState
        let providerStatusCacheKey = Self.composerProviderStatusCacheKey(
            projectURL: Self.providerDiscoveryURL(for: conversation.thread),
            activeProviderID: conversation.provider ?? settingsService.current.defaultProvider,
            settings: settingsService.current
        )
        let providerStatusSnapshot = ComposerProviderStatusCache.snapshot(for: providerStatusCacheKey)
        _composerProviderStatuses = State(initialValue: providerStatusSnapshot?.statuses ?? [:])
        _composerProviderOrdering = State(initialValue: providerStatusSnapshot?.ordering ?? AgentCLIKit.AgentProviderID.allCases)
        _hasLoadedComposerProviderStatuses = State(initialValue: providerStatusSnapshot != nil)
        _controllerLease = State(
            initialValue: conversationControllerRegistry.makeViewLease(for: conversation)
        )
    }

    var viewModel: ConversationViewModel {
        controllerLease.viewModel
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
            settingsService: settingsService,
            voiceInputService: voiceInputService,
            voiceInputLifecycleController: voiceInputLifecycleController,
            transcriptTypography: transcriptTypography,
            availableProjects: availableProjects,
            onSelectDraftProject: onSelectDraftProject,
            appState: appState
        )
        .task {
            controllerLease.activate()
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
            controllerLease.deactivate()
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
            let allowsThreadScopedDiffSwitch = !thread.isDraft
            let conversationIds = allowsThreadScopedDiffSwitch ? liveConversationIDs(for: threadID) : []
            guard let diffTarget = DiffViewerSwitchTarget.forThread(
                thread,
                candidateConversationIDs: conversationIds
            ), diffTarget.directory == newPath else {
                return
            }

            Task {
                await ConversationAsyncRouting.warmFileCacheForDiffSwitch(
                    request: .init(
                        threadID: threadID,
                        workingDirectory: newPath,
                        allowsThreadScopedSwitch: allowsThreadScopedDiffSwitch
                    ),
                    fileListManager: fileListManager,
                    liveState: .init(
                        selectedSidebarItem: { appState.selectedSidebarItem },
                        currentWorkingDirectory: { activeWorkingDirectory },
                        resolveScope: diffViewerSwitchScope
                    ),
                    performSwitch: { scope in
                        await diffViewModel.switchToTarget(diffTarget, scope: scope)
                    }
                )
            }
        }
        .task(id: appState.pendingCommitMessageGenerationRequest?.id) {
            await handlePendingCommitMessageGenerationRequest()
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

    var composerReasoningConfiguration: ChatComposerActionRowView.ReasoningConfiguration {
        ChatComposerActionRowView.ReasoningConfiguration(
            selection: composerReasoningSelection,
            modelGroups: composerReasoningModelGroups,
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
        let defaultEffort = AgentModelOptionSelection.defaultEffortValue(in: options, selectedModel: selectedModel)
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
            defaultEffortValue: effortOptions.contains { $0.value == defaultEffort } ? defaultEffort : effortOptions.first?.value,
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
        guard hasLoadedComposerProviderStatuses else {
            return []
        }

        return composerProviderOrdering.compactMap { providerID in
            let rawValue = providerID.rawValue
            guard AppSettings.supportedProviderIDs.contains(rawValue) else {
                return nil
            }
            guard let status = composerProviderStatuses[providerID],
                  isSelectableComposerProvider(status, providerID: rawValue) else {
                return nil
            }
            return reasoningModelGroup(for: providerID, providerTitle: providerDisplayName(for: providerID))
        }
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

    func goalModeDisabledTooltip(
        supportsGoalMode: Bool,
        supportsExistingSessionGoalStart: Bool
    ) -> String? {
        guard hasLoadedComposerProviderStatuses else {
            return "Checking Goal mode support..."
        }
        guard supportsGoalMode else {
            return "Goal mode is not supported by this agent."
        }
        if viewModel.hasVisibleUserMessageHistory,
           !supportsExistingSessionGoalStart {
            return "This agent can only start Goal mode before the first visible user message."
        }
        return nil
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
