import AgentCLIKit
import SwiftData
import SwiftUI

struct ConversationView: View {
    let conversation: Conversation
    let modelContext: ModelContext
    let settingsService: SettingsService
    let harnessRegistry: HarnessRegistry
    let harnessDiscovery: any AgentCLIKit.AgentHarnessDiscoveryService
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
    let availableSections: [SidebarSection]
    let onSelectDraftDestination: (ThreadDraftDestination) -> Void
    @Bindable var appState: AppState
    @Environment(PullRequestReviewTeamCoordinator.self) var reviewTeamCoordinator: PullRequestReviewTeamCoordinator?

    @State var controllerLease: ConversationControllerLease
    @State var composerHarnessStatuses: [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus]
    @State var composerHarnessOrdering: [AgentCLIKit.AgentHarnessID]
    @State var hasLoadedComposerHarnessStatuses: Bool

    var composerCapabilities: ComposerCapabilities {
        let policy = HarnessFeaturePolicy(
            harnessID: activeHarnessID,
            status: activeHarnessStatus,
            selectedModel: conversation.thread?.model
        )
        return ComposerCapabilities(
            supportedPermissionModes: harnessPermissionModes(),
            supportsMidTurnSteering: policy.supportsMidTurnSteering,
            hasConfirmedHarnessDefinition: policy.hasCapabilities,
            supportsGoalMode: policy.supportsGoalMode,
            supportsExistingSessionGoalStart: policy.supportsExistingSessionGoalStart,
            supportsPlanMode: policy.supportsPlanMode,
            supportsSpeedMode: policy.supportsSpeedMode,
            supportsLocalImageInput: policy.supportsLocalImageInput,
            supportsAppShots: policy.supportsAppShots,
            supportsContextCompaction: policy.supportsContextCompaction,
            goalModeDisabledTooltip: goalModeDisabledTooltip(
                supportsGoalMode: policy.supportsGoalMode,
                supportsExistingSessionGoalStart: policy.supportsExistingSessionGoalStart
            ),
            planModeDisabledTooltip: planModeDisabledTooltip(supportsPlanMode: policy.supportsPlanMode)
        )
    }

    init(
        conversation: Conversation,
        conversationControllerRegistry: any ConversationControllerRegistry,
        modelContext: ModelContext,
        settingsService: SettingsService,
        harnessRegistry: HarnessRegistry,
        harnessDiscovery: any AgentCLIKit.AgentHarnessDiscoveryService,
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
        availableSections: [SidebarSection] = [],
        onSelectDraftDestination: @escaping (ThreadDraftDestination) -> Void = { _ in },
        appState: AppState
    ) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.settingsService = settingsService
        self.harnessRegistry = harnessRegistry
        self.harnessDiscovery = harnessDiscovery
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
        self.availableSections = availableSections
        self.onSelectDraftDestination = onSelectDraftDestination
        self.appState = appState
        let harnessStatusCacheKey = Self.composerHarnessStatusCacheKey(
            projectURL: Self.harnessDiscoveryURL(
                for: conversation.thread,
                harnessID: conversation.harness ?? conversation.harnessSessionHarnessId ?? settingsService.current.defaultHarness
            ),
            activeHarnessID: conversation.harness ?? conversation.harnessSessionHarnessId ?? settingsService.current.defaultHarness,
            settings: settingsService.current
        )
        let harnessStatusSnapshot = ComposerHarnessStatusCache.snapshot(for: harnessStatusCacheKey)
        _composerHarnessStatuses = State(initialValue: harnessStatusSnapshot?.statuses ?? [:])
        _composerHarnessOrdering = State(initialValue: harnessStatusSnapshot?.ordering ?? AgentCLIKit.AgentHarnessID.allCases)
        _hasLoadedComposerHarnessStatuses = State(initialValue: harnessStatusSnapshot != nil)
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
        let reviewRun = reviewTeamCoordinator?.runs[viewModel.conversationID]

        ChatView(
            viewModel: viewModel,
            conversation: conversation,
            composerCapabilities: composerCapabilities,
            reasoningConfiguration: composerReasoningConfiguration,
            defaultEnterBehavior: settings.defaultEnterBehavior,
            harnessID: activeHarnessID,
            runtimeStatus: runtimeStatus,
            isReviewTeamWorking: reviewRun?.phase.isWorking == true,
            onCancelReviewTeam: {
                guard let reviewRun else { return }
                reviewTeamCoordinator?.cancel(conversationID: reviewRun.conversationID, runID: reviewRun.id, generation: reviewRun.generation)
            },
            contextWindowCache: contextWindowCache,
            workingDirectory: activeWorkingDirectory,
            projectTrustPrompt: projectTrustPrompt,
            isProjectTrustBlocked: isProjectTrustBlocked,
            onTrustProject: onTrustProject,
            onDenyProjectTrust: onDenyProjectTrust,
            loadFileCompletions: Self.makeFileCompletionLoader(
                fileListManager: fileListManager,
                workingDirectory: activeWorkingDirectory,
                additionalRoots: conversation.thread?.workspaceSnapshot?.grants.map(\.path) ?? []
            ),
            loadSkillCompletions: loadSkillCompletions,
            settingsService: settingsService,
            voiceInputService: voiceInputService,
            voiceInputLifecycleController: voiceInputLifecycleController,
            transcriptTypography: transcriptTypography,
            availableProjects: availableProjects,
            availableSections: availableSections,
            onSelectDraftDestination: onSelectDraftDestination,
            appState: appState
        )
        .task {
            controllerLease.activate()
            if let path = activeWorkingDirectory {
                await fileListManager.warmCache(for: path)
            }
        }
        .task(id: composerHarnessStatusTaskID) {
            await refreshComposerHarnessStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsChanged)) { _ in
            Task {
                await refreshComposerHarnessStatuses()
            }
        }
        .onDisappear {
            controllerLease.deactivate()
        }
        .onChange(of: runtimeStatus) { _, newStatus in
            guard newStatus.settlesQueueDrain else {
                return
            }
            viewModel.scheduleQueueDrainIfNeeded()
        }
        .onChange(of: activeWorkingDirectory) { _, newPath in
            NotificationCenter.default.post(name: .workspaceConfigurationChanged, object: nil)
            if let newPath { Task { await fileListManager.warmCache(for: newPath) } }
        }
        .onChange(of: conversation.thread?.workspaceSnapshotJSON) { _, _ in
            NotificationCenter.default.post(name: .workspaceConfigurationChanged, object: nil)
        }
        .task(id: appState.pendingCommitMessageGenerationRequest?.id) {
            await handlePendingCommitMessageGenerationRequest()
        }
    }
}

private extension ConversationView {
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
        let selectedModel = selectedComposerModelOptionID(for: activeAgentHarnessID)
        let options = modelOptions(for: activeAgentHarnessID)
        let modelTitle = AgentModelOptionSelection.menuItems(
            in: options,
            selectedModel: selectedModel,
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        ).first { $0.value == selectedModel }?.title ?? ChatComposerTextSupport.modelLabel(for: selectedModel)
        let effortOptions = reasoningEffortOptions(for: activeAgentHarnessID, selectedModel: selectedModel)
        let defaultEffort = AgentModelOptionSelection.defaultEffortValue(in: options, selectedModel: selectedModel)
        let effortValue = conversation.thread?.effort ?? AppSettings.defaultEffortLevel
        let effortTitle = effortOptions.first { $0.value == effortValue }?.title
            ?? ChatComposerTextSupport.effortLabel(for: effortValue)
        let speedMode = composerCapabilities.supportsSpeedMode ? conversation.thread?.normalizedSpeedMode ?? .standard : .standard

        return ChatComposerActionRowView.ReasoningSelection(
            harnessID: activeHarnessID,
            harnessTitle: activeAgentHarnessID.map(harnessDisplayName(for:)) ?? activeHarnessID.capitalized,
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
            guard let harnessID = activeAgentHarnessID else {
                return []
            }
            return [reasoningModelGroup(for: harnessID, harnessTitle: nil)]
        }
        guard hasLoadedComposerHarnessStatuses else {
            return []
        }

        return composerHarnessOrdering.compactMap { harnessID in
            let rawValue = harnessID.rawValue
            guard AppSettings.supportedHarnessIDs.contains(rawValue) else {
                return nil
            }
            guard let status = composerHarnessStatuses[harnessID],
                  isSelectableComposerHarness(status, harnessID: rawValue) else {
                return nil
            }
            return reasoningModelGroup(for: harnessID, harnessTitle: harnessDisplayName(for: harnessID))
        }
    }

    func harnessDisplayName(for harnessId: AgentCLIKit.AgentHarnessID) -> String {
        composerHarnessStatuses[harnessId]?.definition?.displayName ?? harnessId.rawValue.capitalized
    }

    func modelOptions(for harnessId: AgentCLIKit.AgentHarnessID?) -> [AgentCLIKit.AgentModelOption] {
        guard let harnessId else {
            return []
        }
        if let options = composerHarnessStatuses[harnessId]?.modelOptions, !options.isEmpty {
            return options
        }
        return AgentCLIKit.AgentDefaultModelOptions.staticOptions(for: harnessId)
    }

    func reasoningModelGroup(
        for harnessID: AgentCLIKit.AgentHarnessID,
        harnessTitle: String?
    ) -> ChatComposerActionRowView.ReasoningModelGroup {
        let selectedModel = harnessID.rawValue == activeHarnessID
            ? conversation.thread?.model ?? AppSettings.defaultModelValue
            : AppSettings.defaultModelValue
        let options = AgentModelOptionSelection.menuItems(
            in: modelOptions(for: harnessID),
            selectedModel: selectedModel,
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        ).map { item in
            ChatComposerActionRowView.ReasoningModelOption(
                harnessID: harnessID.rawValue,
                value: item.value,
                title: item.title,
                shortName: item.shortName
            )
        }
        return ChatComposerActionRowView.ReasoningModelGroup(
            harnessID: harnessID.rawValue,
            harnessTitle: harnessTitle,
            options: options
        )
    }

    func selectedComposerModelOptionID(for harnessID: AgentCLIKit.AgentHarnessID?) -> String {
        AgentModelOptionSelection.pickerValue(
            in: modelOptions(for: harnessID),
            matching: conversation.thread?.model ?? AppSettings.defaultModelValue
        )
    }

    func reasoningEffortOptions(
        for harnessID: AgentCLIKit.AgentHarnessID?,
        selectedModel: String
    ) -> [ChatComposerActionRowView.MenuOption] {
        guard let harnessID,
              HarnessFeaturePolicy(
                harnessID: harnessID.rawValue,
                status: composerHarnessStatuses[harnessID],
                selectedModel: selectedModel
              ).supportsReasoning else { return [] }
        return AgentModelOptionSelection.effortOptions(
            in: modelOptions(for: harnessID),
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
            group.harnessID == request.harnessID && group.options.contains { $0.value == request.modelID }
        }),
        let requestHarnessID = AgentCLIKit.AgentHarnessID(rawValue: request.harnessID) else {
            return .rejected
        }

        let previousHarnessID = activeHarnessID
        let previousModelID = selectedComposerModelOptionID(for: activeAgentHarnessID)
        guard previousHarnessID != request.harnessID || previousModelID != request.modelID else {
            return .unchanged(composerReasoningSelection)
        }

        let requestOptions = modelOptions(for: requestHarnessID)
        let storedModel = AgentModelOptionSelection.storedModelValue(in: requestOptions, matching: request.modelID)
        let requestEffortOptions = AgentModelOptionSelection.effortOptions(in: requestOptions, selectedModel: storedModel)
        let defaultEffort = requestHarnessID == .opencode && requestEffortOptions.isEmpty
            ? AppSettings.openCodeDefaultEffort
            : AgentModelOptionSelection.defaultEffortValue(in: requestOptions, selectedModel: storedModel)
        let requestSupportsSpeedMode = composerHarnessStatuses[requestHarnessID]?.definition?.capabilities.supportsSpeedMode ?? false
        let didApply: Bool

        if previousHarnessID == request.harnessID {
            guard viewModel.canApplySettingsChange else {
                return .rejected
            }
            _ = viewModel.applyModelChange(
                storedModel,
                effortOptions: requestEffortOptions,
                defaultEffort: defaultEffort,
                supportsSpeedMode: requestSupportsSpeedMode
            )
            didApply = activeHarnessID == request.harnessID &&
                selectedComposerModelOptionID(for: activeAgentHarnessID) == request.modelID
        } else {
            guard conversation.thread?.hasCompletedInitialSetup != true else {
                return .rejected
            }
            didApply = viewModel.applyPreStartupHarnessModelChange(
                harnessID: request.harnessID,
                model: storedModel,
                effortOptions: requestEffortOptions,
                defaultEffort: defaultEffort,
                supportsSpeedMode: requestSupportsSpeedMode
            ) && activeHarnessID == request.harnessID &&
                selectedComposerModelOptionID(for: requestHarnessID) == request.modelID
        }

        guard didApply else {
            return .rejected
        }

        return .applied(selection: composerReasoningSelection)
    }

    func harnessPermissionModes() -> [PermissionModeOption] {
        if let modes = activeHarnessStatus?.definition?.supportedPermissionModes {
            return modes.filter { $0.value != "plan" }.map { option in
                PermissionModeOption(value: option.value, label: option.label, description: option.description)
            }
        }
        return (harnessRegistry.harness(for: activeHarnessID)?.supportedPermissionModes ?? [])
            .filter { $0.value != "plan" }
    }

    func planModeDisabledTooltip(supportsPlanMode: Bool) -> String? {
        guard supportsPlanMode else {
            return "Plan mode is not supported by this harness."
        }
        guard activeHarnessID == "codex" else {
            return nil
        }
        return hasConcreteCodexModelSelection() ? nil : "Choose a concrete Codex model to use plan mode."
    }

    func goalModeDisabledTooltip(
        supportsGoalMode: Bool,
        supportsExistingSessionGoalStart: Bool
    ) -> String? {
        guard hasLoadedComposerHarnessStatuses else {
            return "Checking Goal mode support..."
        }
        guard supportsGoalMode else {
            return "Goal mode is not supported by this harness."
        }
        if viewModel.hasVisibleUserMessageHistory,
           !supportsExistingSessionGoalStart {
            return "This harness can only start Goal mode before the first visible user message."
        }
        return nil
    }

    func hasConcreteCodexModelSelection() -> Bool {
        if let storedModel = conversation.thread?.model?.trimmingCharacters(in: .whitespacesAndNewlines),
           !storedModel.isEmpty,
           storedModel != AppSettings.defaultModelValue {
            return true
        }
        let options = modelOptions(for: activeAgentHarnessID)
        let selectedModel = conversation.thread?.model ?? AppSettings.defaultModelValue
        guard let model = AgentModelOptionSelection.option(in: options, matching: selectedModel)?.model else {
            return false
        }
        return !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
