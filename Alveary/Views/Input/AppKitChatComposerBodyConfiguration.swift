import AppKit
import BlockInputKit
import Foundation

enum LocalFileSelectionResult: Equatable {
    case useDefault
    case handled
    case insertDefault([URL])
}

/// Composer state and callbacks consumed by the native AppKit body.
///
/// Keep this as a value boundary between `ChatView` state and AppKit rendering:
/// the view may measure, focus, and draw locally, but source-of-truth composer
/// state should still flow through these fields and closures.
struct AppKitChatComposerBodyConfiguration {
    let text: String
    let draftIdentity: String
    let inputDraftRevision: Int
    let isTextEffectivelyEmpty: Bool
    let mode: ComposerMode
    let defaultEnterBehavior: ThreadEnterDefaultBehavior
    let isStopConfirmationArmed: Bool
    let supportsMidTurnSteering: Bool
    let canSteerCurrentTurn: Bool
    let isProjectTrustBlocked: Bool
    let isHandoffSteeringPromptActive: Bool
    let isHandoffOutputPromptActive: Bool
    let handoffSteeringCountdown: Int?
    let sendCountdown: Int?
    let isGoalModeArmed: Bool
    let hasQueuedMessages: Bool
    let hasTopContent: Bool
    let workingDirectory: String?
    let attachments: [ComposerAttachment]
    let urlOpener: BlockInputURLOpener
    let localCommands: ComposerLocalCommandAvailability
    let passthroughSlashCommands: [ComposerPassthroughSlashCommand]
    let requestFirstResponder: UUID?
    let isVoiceInteractionLocked: Bool
    let voiceEditorHandle: AppKitChatComposerEditorHandle?
    let onVoiceEscape: () -> Bool
    let onVoiceInputAvailabilityChange: () -> Void
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let onOpenAttachment: (ComposerAttachment) -> Void
    let onRemoveAttachment: (ComposerAttachment) -> Void
    let onBlockInputMutation: (Bool) -> Void
    let onBlockInputDocumentChange: (BlockInputDocument) -> Void
    let onLocalFileURLsSelected: @MainActor ([URL]) async -> LocalFileSelectionResult
    let onDraftSnapshotProviderChange: (ComposerDraftSnapshotProvider?) -> Void
    let onSubmit: () -> Void
    let onSteer: () -> Void
    let onAlternateSteer: () -> Void
    let onStop: () -> Void
    let onStopConfirmationChange: (Bool) -> Void
    let onFocusRequestConsumed: (UUID?) -> Void

    init(
        text: String,
        draftIdentity: String = "",
        inputDraftRevision: Int = 0,
        isTextEffectivelyEmpty: Bool = true,
        mode: ComposerMode,
        defaultEnterBehavior: ThreadEnterDefaultBehavior,
        isStopConfirmationArmed: Bool,
        supportsMidTurnSteering: Bool,
        canSteerCurrentTurn: Bool = true,
        isProjectTrustBlocked: Bool,
        isHandoffSteeringPromptActive: Bool,
        isHandoffOutputPromptActive: Bool,
        handoffSteeringCountdown: Int?,
        sendCountdown: Int?,
        isGoalModeArmed: Bool = false,
        hasQueuedMessages: Bool,
        hasTopContent: Bool,
        workingDirectory: String?,
        attachments: [ComposerAttachment] = [],
        urlOpener: @escaping BlockInputURLOpener = { NSWorkspace.shared.open($0) },
        localCommands: ComposerLocalCommandAvailability = ComposerLocalCommandAvailability(),
        passthroughSlashCommands: [ComposerPassthroughSlashCommand] = [],
        requestFirstResponder: UUID?,
        isVoiceInteractionLocked: Bool = false,
        voiceEditorHandle: AppKitChatComposerEditorHandle? = nil,
        onVoiceEscape: @escaping () -> Bool = { false },
        onVoiceInputAvailabilityChange: @escaping () -> Void = {},
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        onOpenAttachment: @escaping (ComposerAttachment) -> Void = { _ in },
        onRemoveAttachment: @escaping (ComposerAttachment) -> Void = { _ in },
        onBlockInputMutation: @escaping (Bool) -> Void = { _ in },
        onBlockInputDocumentChange: @escaping (BlockInputDocument) -> Void = { _ in },
        onLocalFileURLsSelected: @escaping @MainActor ([URL]) async -> LocalFileSelectionResult = { _ in .useDefault },
        onDraftSnapshotProviderChange: @escaping (ComposerDraftSnapshotProvider?) -> Void = { _ in },
        onSubmit: @escaping () -> Void,
        onSteer: @escaping () -> Void,
        onAlternateSteer: @escaping () -> Void = {},
        onStop: @escaping () -> Void,
        onStopConfirmationChange: @escaping (Bool) -> Void,
        onFocusRequestConsumed: @escaping (UUID?) -> Void
    ) {
        self.text = text
        self.draftIdentity = draftIdentity
        self.inputDraftRevision = inputDraftRevision
        self.isTextEffectivelyEmpty = isTextEffectivelyEmpty
        self.mode = mode
        self.defaultEnterBehavior = defaultEnterBehavior
        self.isStopConfirmationArmed = isStopConfirmationArmed
        self.supportsMidTurnSteering = supportsMidTurnSteering
        self.canSteerCurrentTurn = canSteerCurrentTurn
        self.isProjectTrustBlocked = isProjectTrustBlocked
        self.isHandoffSteeringPromptActive = isHandoffSteeringPromptActive
        self.isHandoffOutputPromptActive = isHandoffOutputPromptActive
        self.handoffSteeringCountdown = handoffSteeringCountdown
        self.sendCountdown = sendCountdown
        self.isGoalModeArmed = isGoalModeArmed
        self.hasQueuedMessages = hasQueuedMessages
        self.hasTopContent = hasTopContent
        self.workingDirectory = workingDirectory
        self.attachments = attachments
        self.urlOpener = urlOpener
        self.localCommands = localCommands
        self.passthroughSlashCommands = passthroughSlashCommands
        self.requestFirstResponder = requestFirstResponder
        self.isVoiceInteractionLocked = isVoiceInteractionLocked
        self.voiceEditorHandle = voiceEditorHandle
        self.onVoiceEscape = onVoiceEscape
        self.onVoiceInputAvailabilityChange = onVoiceInputAvailabilityChange
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
        self.onOpenAttachment = onOpenAttachment
        self.onRemoveAttachment = onRemoveAttachment
        self.onBlockInputMutation = onBlockInputMutation
        self.onBlockInputDocumentChange = onBlockInputDocumentChange
        self.onLocalFileURLsSelected = onLocalFileURLsSelected
        self.onDraftSnapshotProviderChange = onDraftSnapshotProviderChange
        self.onSubmit = onSubmit
        self.onSteer = onSteer
        self.onAlternateSteer = onAlternateSteer
        self.onStop = onStop
        self.onStopConfirmationChange = onStopConfirmationChange
        self.onFocusRequestConsumed = onFocusRequestConsumed
    }
}
