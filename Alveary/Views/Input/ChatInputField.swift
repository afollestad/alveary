import Foundation
import SwiftUI

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
    let composerActionRowHeight: CGFloat = 30
    let contextIndicatorKeyboardSpacing: CGFloat = 6
    let queuedMessagesAnimation = Animation.easeInOut(duration: 0.18)

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
    @State private var autocompletePopupHeight: CGFloat = 0
    @State var isStopConfirmationArmed = false
    @State var stopConfirmationResetTask: Task<Void, Never>?

    init(
        text: Binding<String>,
        mode: ComposerMode,
        defaultEnterBehavior: ThreadEnterDefaultBehavior = AppSettings.defaultEnterBehavior,
        onSubmit: @escaping () -> Void,
        onSteer: @escaping () -> Void,
        onStop: (() -> Void)?,
        isStopConfirmationArmed: Bool = false,
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
        focusRequestToken: Binding<UUID?> = .constant(nil)
    ) {
        _text = text
        self.mode = mode
        self.defaultEnterBehavior = defaultEnterBehavior
        self.onSubmit = onSubmit
        self.onSteer = onSteer
        self.onStop = onStop
        _isStopConfirmationArmed = State(initialValue: isStopConfirmationArmed)
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

                AppTextEditor(
                    text: $text,
                    selection: $textSelection,
                    minHeight: composerBaseHeight,
                    idealHeight: composerBaseHeight,
                    maxHeight: 144,
                    placeholder: placeholder,
                    cornerRadius: 18,
                    cornerRadii: queuedMessages.isEmpty ? nil : RectangleCornerRadii(
                        topLeading: 0,
                        bottomLeading: 18,
                        bottomTrailing: 18,
                        topTrailing: 0
                    ),
                    horizontalPadding: composerHorizontalPadding,
                    verticalPadding: composerVerticalPadding,
                    borderColor: inputBorderColor,
                    borderWidth: inputBorderWidth,
                    isDisabled: isTextEditorDisabled,
                    showsDisabledCursor: isProjectTrustBlocked,
                    sizesToContent: true,
                    focus: $isInputFocused,
                    textChips: ChatInputFieldTextSupport.composerTextChips(in:),
                    codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
                    inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
                    inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
                    inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
                    inlineHint: inlineSlashCommandHint,
                    keyPressKeys: [.upArrow, .downArrow, .tab, .escape, .return],
                    onKeyPress: handleKeyPress,
                    requestFirstResponder: focusRequestToken,
                    onFocusRequestConsumed: { focusRequestToken = nil },
                    isAppKitFirstResponder: $isComposerFirstResponder,
                    disablesAppKitDragDestination: true
                )
                .overlay(alignment: .topLeading) {
                    if let autocomplete = activeAutocomplete {
                        ComposerAutocompletePopup(
                            autocomplete: autocomplete,
                            onSelect: applyAutocompleteSuggestion
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        autocompletePopupHeight = proxy.size.height
                                    }
                                    .onChange(of: proxy.size.height) { _, newHeight in
                                        autocompletePopupHeight = newHeight
                                    }
                            }
                        }
                        .opacity(autocompletePopupHeight == 0 ? 0 : 1)
                        .offset(y: -(autocompletePopupHeight + 8))
                        .zIndex(1)
                    }
                }
                .zIndex(activeAutocomplete == nil ? 0 : 1)
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
            HStack(spacing: 10) {
                Picker("Model", selection: $selectedModel) {
                    Section(header: Text("Model")) {
                        ForEach(modelOptions, id: \.self) { option in
                            Text(ChatInputFieldTextSupport.modelLabel(for: option)).tag(option)
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(areControlsDisabled)

                if !supportedEffortLevels.isEmpty {
                    Picker("Effort", selection: $selectedEffort) {
                        Section(header: Text("Effort")) {
                            ForEach(supportedEffortLevels, id: \.self) { option in
                                Text(ChatInputFieldTextSupport.effortLabel(for: option)).tag(option)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(areControlsDisabled)
                }

                if !supportedPermissionModes.isEmpty {
                    Picker("Permissions", selection: $selectedPermissionMode) {
                        Section(header: Text("Permissions")) {
                            ForEach(supportedPermissionModes, id: \.value) { option in
                                Text(ChatInputFieldTextSupport.permissionModeLabel(for: option)).tag(option.value)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(areControlsDisabled)
                }

                if showWorktreePicker {
                    Picker("Thread location", selection: $selectedUseWorktree) {
                        Text(ChatInputFieldTextSupport.worktreeLocationLabel(for: false)).tag(false)
                        Text(ChatInputFieldTextSupport.worktreeLocationLabel(for: true)).tag(true)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(areControlsDisabled)
                } else if let sessionLocationLabel {
                    Text(sessionLocationLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(sessionLocationLabel)
                }

                Spacer()

                if usageSummary != nil || !isTextEditorDisabled {
                    HStack(spacing: contextIndicatorKeyboardSpacing) {
                        if let usageSummary {
                            ContextWindowIndicator(summary: usageSummary)
                        }

                        if !isTextEditorDisabled {
                            Button {
                                isKeymapPresented = true
                            } label: {
                                Image(systemName: "keyboard")
                            }
                            .iconActionButtonStyle()
                            .accessibilityLabel("Show chat keyboard shortcuts")
                        }
                    }
                }
                switch mode {
                case .idle:
                    Button(action: performSubmit) {
                        ChatInputSendFootprintLabel {
                            ChatInputActionLabel(primaryActionTitle, systemImage: primaryActionSystemImage)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .primaryActionButtonStyle()
                    .disabled(isPrimaryActionDisabled)
                    .animation(.easeInOut(duration: 0.18), value: primaryActionTitle)

                case .busy(let canStop):
                    if canStop {
                        ChatInputStopButton(
                            isConfirmationArmed: isStopConfirmationArmed,
                            action: performStop
                        )
                    } else {
                        ChatInputSendFootprintSlot {
                            ProgressView()
                                .controlSize(.small)
                        }
                        .accessibilityLabel("Sending message")
                    }

                case .progressOnly(let reason):
                    if reason.canStop {
                        ChatInputStopButton(
                            isConfirmationArmed: isStopConfirmationArmed,
                            action: performStop
                        )
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(ChatInputFieldTextSupport.progressLabel(for: reason))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: composerActionRowHeight)
                    }
                }
            }
            .frame(minHeight: composerActionRowHeight)
        }
        .padding(outerPadding)
        .zIndex(activeAutocomplete == nil ? 0 : 1)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.bar)
        )
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
