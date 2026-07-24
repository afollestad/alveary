import AppKit

extension ChatComposerActionRowView {
    /// Value-only projection of `Configuration` used to skip re-applying
    /// visually identical configurations. SwiftUI re-evaluates the composer
    /// body at frame rate during animations and focus changes, and each
    /// `applyConfiguration` pass reconfigures every button and relayouts the
    /// row; comparing this snapshot keeps those passes to real value changes.
    /// Closures are excluded on purpose: handlers read `self.configuration`
    /// at fire time, so storing the fresh configuration keeps behavior
    /// current without any AppKit work.
    struct AppliedConfigurationSnapshot: Equatable {
        let reasoningSelection: ReasoningSelection
        let reasoningModelGroups: [ReasoningModelGroup]
        let supportedPermissionModes: [PermissionOptionPresentation]
        let selectedPermissionMode: String
        let showWorktreePicker: Bool
        let selectedUseWorktree: Bool
        let isPlanModeEnabled: Bool
        let isPlanModeToggleEnabled: Bool
        let planModeDisabledTooltip: String?
        let isGoalModeArmed: Bool
        let isGoalModeToggleEnabled: Bool
        let goalModeDisabledTooltip: String?
        let isGoalModeChipVisible: Bool
        let isGoalModeChipEnabled: Bool
        let usageSummary: ConversationUsageSummary?
        let areControlsDisabled: Bool
        let mode: ComposerMode
        let primaryActionTitle: String
        let primaryActionSystemImage: String
        let isPrimaryActionDisabled: Bool
        let isStopConfirmationArmed: Bool
        let composerActionRowHeight: CGFloat
        let taskWorkspacePrimaryRoot: String?
        let taskWorkspaceGrantedRoots: [String]?
        let taskWorkspaceOwnershipStrategy: TaskWorkspaceOwnershipStrategy?
        let taskWorkspaceCanEdit: Bool?
        let taskWorkspaceDisabledTooltip: String?
        let voiceInputPhase: ChatVoiceInputPhase?
        let voiceInputIsEnabled: Bool?
        let voiceInputShortcutDisplay: String?
        let voiceInputUnavailableHelp: String?
        let voiceInputReducesMotion: Bool?
        let voiceInputIncreasesContrast: Bool?
        let reasoningMenuPresentationRequest: UUID?

        init(_ configuration: Configuration) {
            reasoningSelection = configuration.reasoning.selection
            reasoningModelGroups = configuration.reasoning.modelGroups
            supportedPermissionModes = configuration.supportedPermissionModes
            selectedPermissionMode = configuration.selectedPermissionMode
            showWorktreePicker = configuration.showWorktreePicker
            selectedUseWorktree = configuration.selectedUseWorktree
            isPlanModeEnabled = configuration.isPlanModeEnabled
            isPlanModeToggleEnabled = configuration.isPlanModeToggleEnabled
            planModeDisabledTooltip = configuration.planModeDisabledTooltip
            isGoalModeArmed = configuration.isGoalModeArmed
            isGoalModeToggleEnabled = configuration.isGoalModeToggleEnabled
            goalModeDisabledTooltip = configuration.goalModeDisabledTooltip
            isGoalModeChipVisible = configuration.isGoalModeChipVisible
            isGoalModeChipEnabled = configuration.isGoalModeChipEnabled
            usageSummary = configuration.usageSummary
            areControlsDisabled = configuration.areControlsDisabled
            mode = configuration.mode
            primaryActionTitle = configuration.primaryActionTitle
            primaryActionSystemImage = configuration.primaryActionSystemImage
            isPrimaryActionDisabled = configuration.isPrimaryActionDisabled
            isStopConfirmationArmed = configuration.isStopConfirmationArmed
            composerActionRowHeight = configuration.composerActionRowHeight
            taskWorkspacePrimaryRoot = configuration.taskWorkspace?.primaryRoot
            taskWorkspaceGrantedRoots = configuration.taskWorkspace?.grantedRoots
            taskWorkspaceOwnershipStrategy = configuration.taskWorkspace?.ownershipStrategy
            taskWorkspaceCanEdit = configuration.taskWorkspace?.canEdit
            taskWorkspaceDisabledTooltip = configuration.taskWorkspace?.disabledTooltip
            voiceInputPhase = configuration.voiceInput?.phase
            voiceInputIsEnabled = configuration.voiceInput?.isEnabled
            voiceInputShortcutDisplay = configuration.voiceInput?.shortcutDisplay
            voiceInputUnavailableHelp = configuration.voiceInput?.unavailableHelp
            voiceInputReducesMotion = configuration.voiceInput?.reducesMotion
            voiceInputIncreasesContrast = configuration.voiceInput?.increasesContrast
            reasoningMenuPresentationRequest = configuration.reasoningMenuPresentationRequest
        }
    }
}
