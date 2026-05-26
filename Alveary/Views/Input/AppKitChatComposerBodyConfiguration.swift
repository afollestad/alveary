import BlockInputKit
import SwiftUI

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
    let isProjectTrustBlocked: Bool
    let isHandoffSteeringPromptActive: Bool
    let isHandoffOutputPromptActive: Bool
    let handoffSteeringCountdown: Int?
    let sendCountdown: Int?
    let hasQueuedMessages: Bool
    let hasTopContent: Bool
    let workingDirectory: String?
    let requestFirstResponder: UUID?
    let colorScheme: ColorScheme
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let onTextChange: (String) -> Void
    let onBlockInputMutation: (Bool) -> Void
    let onBlockInputDocumentChange: (BlockInputDocument) -> Void
    let onDraftSnapshotProviderChange: (ComposerDraftSnapshotProvider?) -> Void
    let onSubmit: () -> Void
    let onSteer: () -> Void
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
        isProjectTrustBlocked: Bool,
        isHandoffSteeringPromptActive: Bool,
        isHandoffOutputPromptActive: Bool,
        handoffSteeringCountdown: Int?,
        sendCountdown: Int?,
        hasQueuedMessages: Bool,
        hasTopContent: Bool,
        workingDirectory: String?,
        requestFirstResponder: UUID?,
        colorScheme: ColorScheme,
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        onTextChange: @escaping (String) -> Void,
        onBlockInputMutation: @escaping (Bool) -> Void = { _ in },
        onBlockInputDocumentChange: @escaping (BlockInputDocument) -> Void = { _ in },
        onDraftSnapshotProviderChange: @escaping (ComposerDraftSnapshotProvider?) -> Void = { _ in },
        onSubmit: @escaping () -> Void,
        onSteer: @escaping () -> Void,
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
        self.isProjectTrustBlocked = isProjectTrustBlocked
        self.isHandoffSteeringPromptActive = isHandoffSteeringPromptActive
        self.isHandoffOutputPromptActive = isHandoffOutputPromptActive
        self.handoffSteeringCountdown = handoffSteeringCountdown
        self.sendCountdown = sendCountdown
        self.hasQueuedMessages = hasQueuedMessages
        self.hasTopContent = hasTopContent
        self.workingDirectory = workingDirectory
        self.requestFirstResponder = requestFirstResponder
        self.colorScheme = colorScheme
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
        self.onTextChange = onTextChange
        self.onBlockInputMutation = onBlockInputMutation
        self.onBlockInputDocumentChange = onBlockInputDocumentChange
        self.onDraftSnapshotProviderChange = onDraftSnapshotProviderChange
        self.onSubmit = onSubmit
        self.onSteer = onSteer
        self.onStop = onStop
        self.onStopConfirmationChange = onStopConfirmationChange
        self.onFocusRequestConsumed = onFocusRequestConsumed
    }
}
