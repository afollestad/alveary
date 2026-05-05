import Foundation
import SwiftUI

/// SwiftUI composer shell that hosts the native AppKit text editor.
struct ChatInputField: View {
    @Binding var text: String
    let mode: ComposerMode
    let defaultEnterBehavior: ThreadEnterDefaultBehavior
    let onSubmit: () -> Void
    let onSteer: () -> Void
    let onStop: (() -> Void)?
    let outerPadding: EdgeInsets
    @Binding var selectedModel: String
    @Binding var selectedEffort: String
    @Binding var selectedPermissionMode: String
    @Binding var selectedUseWorktree: Bool
    let supportedPermissionModes: [PermissionModeOption]
    let supportedEffortLevels: [String]
    let showWorktreePicker: Bool
    let sessionLocationLabel: String?
    let usageSummary: ConversationUsageSummary?
    let supportsMidTurnSteering: Bool
    let queuedMessages: [QueuedMessage]
    let isTurnActive: Bool
    let isProjectTrustBlocked: Bool
    let inFlightQueuedMessageID: UUID?
    let isHandoffSteeringPromptActive: Bool
    let isHandoffOutputPromptActive: Bool
    let handoffSteeringCountdown: Int?
    let sendCountdown: Int?
    let onSteerQueuedMessage: ((UUID) -> Void)?
    let onEditQueuedMessage: ((UUID) -> Void)?
    let onDismissQueuedMessage: ((UUID) -> Void)?
    let workingDirectory: String?
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]
    @Binding var focusRequestToken: UUID?

    var knownModels: [String] { AppSettings.supportedModels }
    let maxAutocompleteResults = 50
    let autocompleteDebounceNanoseconds: UInt64 = 75_000_000
    let stopConfirmationTimeoutNanoseconds: UInt64 = 1_000_000_000
    let composerHorizontalPadding: CGFloat = 10
    let composerVerticalPadding: CGFloat = 10
    let composerBaseHeight: CGFloat = 68
    let composerActionRowHeight: CGFloat = ChatComposerActionRowView.defaultHeight
    let contextIndicatorKeyboardSpacing: CGFloat = ChatComposerActionRowView.defaultContextIndicatorKeyboardSpacing
    let queuedMessagesAnimation = Animation.easeInOut(duration: 0.18)
    let showsActionRow: Bool

    @FocusState var isInputFocused: Bool
    // Mirrors the NSTextView's first-responder state, synced via
    // `AppKitTextEditorView.isAppKitFirstResponder`. Plain `@State` writes propagate
    // through SwiftUI's normal invalidation path — unlike `@FocusState`, which relies on
    // a `.focused($state)` anchor we deliberately don't install here (the editor is an
    // NSViewRepresentable, not a SwiftUI focusable). Features that need to read "is the
    // composer actively focused?" during body eval (e.g. `inlineSlashCommandHint`) must
    // drive off this binding.
    @State var isComposerFirstResponder: Bool = false
    @State var textSelection: TextSelection?
    @State var activeAutocomplete: ComposerAutocompleteState?
    @State var loadTask: Task<Void, Never>?
    @State var filterTask: Task<Void, Never>?
    @State var skillArgumentHints: [String: String] = [:]
    @State var hasLoadedSkillArgumentHints = false
    @State var skillHintLoadTask: Task<Void, Never>?
    @State var isDropTargeted = false
    @State private var isKeymapPresented = false
    @State var autocompletePopupHeight: CGFloat = 0
    @Binding var isStopConfirmationArmed: Bool
    @State var stopConfirmationResetTask: Task<Void, Never>?

    init(
        text: Binding<String>,
        mode: ComposerMode,
        defaultEnterBehavior: ThreadEnterDefaultBehavior = AppSettings.defaultEnterBehavior,
        onSubmit: @escaping () -> Void,
        onSteer: @escaping () -> Void,
        onStop: (() -> Void)?,
        isStopConfirmationArmed: Binding<Bool> = .constant(false),
        outerPadding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        selectedModel: Binding<String>,
        selectedEffort: Binding<String>,
        selectedPermissionMode: Binding<String>,
        selectedUseWorktree: Binding<Bool> = .constant(false),
        supportedPermissionModes: [PermissionModeOption],
        supportedEffortLevels: [String],
        showWorktreePicker: Bool = false,
        sessionLocationLabel: String? = nil,
        usageSummary: ConversationUsageSummary? = nil,
        supportsMidTurnSteering: Bool,
        queuedMessages: [QueuedMessage] = [],
        isTurnActive: Bool = false,
        isProjectTrustBlocked: Bool = false,
        inFlightQueuedMessageID: UUID? = nil,
        isHandoffSteeringPromptActive: Bool = false,
        isHandoffOutputPromptActive: Bool = false,
        handoffSteeringCountdown: Int? = nil,
        sendCountdown: Int? = nil,
        onSteerQueuedMessage: ((UUID) -> Void)? = nil,
        onEditQueuedMessage: ((UUID) -> Void)? = nil,
        onDismissQueuedMessage: ((UUID) -> Void)? = nil,
        workingDirectory: String?,
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        focusRequestToken: Binding<UUID?> = .constant(nil),
        showsActionRow: Bool = true
    ) {
        _text = text
        self.mode = mode
        self.defaultEnterBehavior = defaultEnterBehavior
        self.onSubmit = onSubmit
        self.onSteer = onSteer
        self.onStop = onStop
        _isStopConfirmationArmed = isStopConfirmationArmed
        self.outerPadding = outerPadding
        _selectedModel = selectedModel
        _selectedEffort = selectedEffort
        _selectedPermissionMode = selectedPermissionMode
        _selectedUseWorktree = selectedUseWorktree
        self.supportedPermissionModes = supportedPermissionModes
        self.supportedEffortLevels = supportedEffortLevels
        self.showWorktreePicker = showWorktreePicker
        self.sessionLocationLabel = sessionLocationLabel
        self.usageSummary = usageSummary
        self.supportsMidTurnSteering = supportsMidTurnSteering
        self.queuedMessages = queuedMessages
        self.isTurnActive = isTurnActive
        self.isProjectTrustBlocked = isProjectTrustBlocked
        self.inFlightQueuedMessageID = inFlightQueuedMessageID
        self.isHandoffSteeringPromptActive = isHandoffSteeringPromptActive
        self.isHandoffOutputPromptActive = isHandoffOutputPromptActive
        self.handoffSteeringCountdown = handoffSteeringCountdown
        self.sendCountdown = sendCountdown
        self.onSteerQueuedMessage = onSteerQueuedMessage
        self.onEditQueuedMessage = onEditQueuedMessage
        self.onDismissQueuedMessage = onDismissQueuedMessage
        self.workingDirectory = workingDirectory
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
        _focusRequestToken = focusRequestToken
        self.showsActionRow = showsActionRow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                if !queuedMessages.isEmpty,
                   let onSteerQueuedMessage,
                   let onEditQueuedMessage,
                   let onDismissQueuedMessage {
                    ChatInputQueuedMessagesSection(
                        queuedMessages: queuedMessages,
                        supportsMidTurnSteering: supportsMidTurnSteering,
                        isTurnActive: isTurnActive,
                        inFlightQueuedMessageID: inFlightQueuedMessageID,
                        borderColor: inputBorderColor,
                        borderWidth: inputBorderWidth,
                        onSteerQueuedMessage: onSteerQueuedMessage,
                        onEditQueuedMessage: onEditQueuedMessage,
                        onDismissQueuedMessage: onDismissQueuedMessage
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                composerTextEditor
            }
            .animation(queuedMessagesAnimation, value: queuedMessages.map(\.id))
            .dropDestination(for: URL.self) { items, _ in
                handleDroppedFiles(items)
            } isTargeted: { isTargeted in
                isDropTargeted = isTargeted
            }
            .onChange(of: text) {
                if text.hasPrefix("/") {
                    loadSkillArgumentHintsIfNeeded()
                }
                refreshAutocomplete()
            }
            .onChange(of: textSelection) {
                refreshAutocomplete()
            }
            .onChange(of: isInputFocused) { _, isFocused in
                if isFocused {
                    refreshAutocomplete()
                } else {
                    dismissAutocomplete()
                }
            }
            .onChange(of: workingDirectory) {
                if isInputFocused {
                    refreshAutocomplete(forceReload: true)
                }
            }
            .onChange(of: activeAutocomplete?.sessionID) {
                autocompletePopupHeight = 0
            }
            .onChange(of: canUseEscapeToStop) { _, canUseEscapeToStop in
                if ChatInputStopConfirmationDecision.shouldClearWhenStopUnavailable(canUseEscapeToStop) {
                    clearStopConfirmation(animated: false)
                }
            }
            .onDisappear {
                loadTask?.cancel()
                filterTask?.cancel()
                skillHintLoadTask?.cancel()
                stopConfirmationResetTask?.cancel()
            }
            .task {
                loadSkillArgumentHintsIfNeeded()
            }
            if showsActionRow {
                ChatComposerActionRow(
                    modelOptions: modelOptions,
                    selectedModel: $selectedModel,
                    supportedEffortLevels: supportedEffortLevels,
                    selectedEffort: $selectedEffort,
                    supportedPermissionModes: supportedPermissionModes,
                    selectedPermissionMode: $selectedPermissionMode,
                    showWorktreePicker: showWorktreePicker,
                    selectedUseWorktree: $selectedUseWorktree,
                    sessionLocationLabel: sessionLocationLabel,
                    usageSummary: usageSummary,
                    isTextEditorDisabled: isTextEditorDisabled,
                    areControlsDisabled: areControlsDisabled,
                    mode: mode,
                    primaryActionTitle: primaryActionTitle,
                    primaryActionSystemImage: primaryActionSystemImage,
                    isPrimaryActionDisabled: isPrimaryActionDisabled,
                    isStopConfirmationArmed: isStopConfirmationArmed,
                    composerActionRowHeight: composerActionRowHeight,
                    contextIndicatorKeyboardSpacing: contextIndicatorKeyboardSpacing,
                    onSubmit: performSubmit,
                    onStop: performStop,
                    onShowKeymap: {
                        isKeymapPresented = true
                    }
                )
                .frame(height: composerActionRowHeight)
            }
        }
        .padding(outerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zIndex(activeAutocomplete == nil ? 0 : 1)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.bar)
        )
        // Legacy snapshots still mount this SwiftUI shell. Keep it content-height
        // so those callers cannot stretch the native action row away from the editor.
        .fixedSize(horizontal: false, vertical: true)
        .blockedComposerCursorOverlay(when: isProjectTrustBlocked)
        .sheet(isPresented: $isKeymapPresented) {
            ChatInputKeymapSheet(
                supportsMidTurnSteering: supportsMidTurnSteering,
                defaultEnterBehavior: defaultEnterBehavior
            )
        }
        .focusedSceneValue(\.chatComposerFocus, $isInputFocused)
    }
}
