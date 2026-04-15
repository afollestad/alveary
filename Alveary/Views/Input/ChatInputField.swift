import Foundation
import SwiftUI

struct ChatInputField: View {
    @Binding var text: String
    let mode: ComposerMode
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
    let supportsMidTurnSteering: Bool
    let queuedMessages: [QueuedMessage]
    let isTurnActive: Bool
    let inFlightQueuedMessageID: UUID?
    let onSteerQueuedMessage: ((UUID) -> Void)?
    let onEditQueuedMessage: ((UUID) -> Void)?
    let onDismissQueuedMessage: ((UUID) -> Void)?
    let workingDirectory: String?
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]

    let knownModels = ["default", "opus", "sonnet", "haiku"]
    let maxAutocompleteResults = 50
    let autocompleteDebounceNanoseconds: UInt64 = 75_000_000
    let stopShortcutHintTimeoutNanoseconds: UInt64 = 1_000_000_000
    let composerHorizontalPadding: CGFloat = 10
    let composerVerticalPadding: CGFloat = 10
    let composerBaseHeight: CGFloat = 68

    @FocusState var isInputFocused: Bool
    @State var textSelection: TextSelection?
    @State var activeAutocomplete: ComposerAutocompleteState?
    @State var loadTask: Task<Void, Never>?
    @State var filterTask: Task<Void, Never>?
    @State var skillArgumentHints: [String: String] = [:]
    @State var hasLoadedSkillArgumentHints = false
    @State var skillHintLoadTask: Task<Void, Never>?
    @State private var isDropTargeted = false
    @State private var isKeymapPresented = false
    @State private var autocompletePopupHeight: CGFloat = 0
    @State var showsStopShortcutHint = false
    @State var stopShortcutResetTask: Task<Void, Never>?

    init(
        text: Binding<String>,
        mode: ComposerMode,
        onSubmit: @escaping () -> Void,
        onSteer: @escaping () -> Void,
        onStop: (() -> Void)?,
        showsStopShortcutHint: Bool = false,
        outerPadding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        selectedModel: Binding<String>,
        selectedEffort: Binding<String>,
        selectedPermissionMode: Binding<String>,
        selectedUseWorktree: Binding<Bool> = .constant(false),
        supportedPermissionModes: [PermissionModeOption],
        supportedEffortLevels: [String],
        showWorktreePicker: Bool = false,
        supportsMidTurnSteering: Bool,
        queuedMessages: [QueuedMessage] = [],
        isTurnActive: Bool = false,
        inFlightQueuedMessageID: UUID? = nil,
        onSteerQueuedMessage: ((UUID) -> Void)? = nil,
        onEditQueuedMessage: ((UUID) -> Void)? = nil,
        onDismissQueuedMessage: ((UUID) -> Void)? = nil,
        workingDirectory: String?,
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill]
    ) {
        _text = text
        self.mode = mode
        self.onSubmit = onSubmit
        self.onSteer = onSteer
        self.onStop = onStop
        _showsStopShortcutHint = State(initialValue: showsStopShortcutHint)
        self.outerPadding = outerPadding
        _selectedModel = selectedModel
        _selectedEffort = selectedEffort
        _selectedPermissionMode = selectedPermissionMode
        _selectedUseWorktree = selectedUseWorktree
        self.supportedPermissionModes = supportedPermissionModes
        self.supportedEffortLevels = supportedEffortLevels
        self.showWorktreePicker = showWorktreePicker
        self.supportsMidTurnSteering = supportsMidTurnSteering
        self.queuedMessages = queuedMessages
        self.isTurnActive = isTurnActive
        self.inFlightQueuedMessageID = inFlightQueuedMessageID
        self.onSteerQueuedMessage = onSteerQueuedMessage
        self.onEditQueuedMessage = onEditQueuedMessage
        self.onDismissQueuedMessage = onDismissQueuedMessage
        self.workingDirectory = workingDirectory
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isTextEditorDisabled: Bool {
        if case .progressOnly = mode { return true }
        return false
    }

    private var areControlsDisabled: Bool {
        switch mode {
        case .idle:
            return false
        case .busy, .progressOnly:
            return true
        }
    }

    var canUseEscapeToStop: Bool {
        guard case .busy(let canStop) = mode else {
            return false
        }

        return canStop
    }

    private var modelOptions: [String] {
        knownModels.contains(selectedModel) ? knownModels : knownModels + [selectedModel]
    }

    private var inputBorderColor: Color {
        isDropTargeted ? .accentColor : Color.secondary.opacity(0.18)
    }

    private var inputBorderWidth: CGFloat {
        isDropTargeted ? 1.5 : 1
    }

    private var placeholder: String {
        switch mode {
        case .idle:
            return "Ask anything, @ to add files, / for skills"
        case .busy(let canStop):
            if canStop, supportsMidTurnSteering {
                return "Enter to queue for the next turn, or Opt+Enter to steer..."
            }
            return "Type a message to queue for the next turn..."
        case .progressOnly(.initialSetup):
            return "Preparing the conversation for its first turn..."
        case .progressOnly(.reconfiguringSession):
            return "Applying session changes..."
        }
    }

    private var inlineSlashCommandHint: AppTextEditorInlineHint? {
        guard let hint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: text,
            textSelection: textSelection,
            isInputFocused: isInputFocused,
            commandHints: skillArgumentHints
        ) else {
            return nil
        }

        return AppTextEditorInlineHint(text: hint)
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
                    sizesToContent: true,
                    focus: $isInputFocused,
                    textHighlightRanges: ChatInputFieldTextSupport.highlightedTokenRanges,
                    inlineHint: inlineSlashCommandHint,
                    keyPressKeys: [.upArrow, .downArrow, .tab, .escape, .return],
                    onKeyPress: handleKeyPress
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
                if !canUseEscapeToStop {
                    clearStopShortcutHint(animated: false)
                }
            }
            .onDisappear {
                loadTask?.cancel()
                filterTask?.cancel()
                skillHintLoadTask?.cancel()
                stopShortcutResetTask?.cancel()
            }
            .task {
                loadSkillArgumentHintsIfNeeded()
            }
            HStack(spacing: 10) {
                Picker("Model", selection: $selectedModel) {
                    ForEach(modelOptions, id: \.self) { option in
                        Text(ChatInputFieldTextSupport.modelLabel(for: option)).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(areControlsDisabled)

                if !supportedEffortLevels.isEmpty {
                    Picker("Effort", selection: $selectedEffort) {
                        ForEach(supportedEffortLevels, id: \.self) { option in
                            Text(ChatInputFieldTextSupport.effortLabel(for: option)).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(areControlsDisabled)
                }

                if !supportedPermissionModes.isEmpty {
                    Picker("Permissions", selection: $selectedPermissionMode) {
                        ForEach(supportedPermissionModes, id: \.value) { option in
                            Text(ChatInputFieldTextSupport.permissionModeLabel(for: option)).tag(option.value)
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
                }

                Spacer()

                if !isTextEditorDisabled {
                    Button {
                        isKeymapPresented = true
                    } label: {
                        Image(systemName: "keyboard")
                    }
                    .iconActionButtonStyle()
                    .accessibilityLabel("Show chat keyboard shortcuts")
                }
                switch mode {
                case .idle:
                    Button(action: performSubmit) {
                        ChatInputActionLabel("Send", systemImage: "paperplane.fill")
                    }
                    .primaryActionButtonStyle()
                    .disabled(trimmedText.isEmpty)

                case .busy(let canStop):
                    Button(action: performSubmit) {
                        ChatInputActionLabel("Queue", systemImage: "clock")
                    }
                        .primaryActionButtonStyle()
                        .disabled(trimmedText.isEmpty)

                    if canStop {
                        ChatInputStopButton(
                            showsShortcutHint: showsStopShortcutHint,
                            action: performStop
                        )
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }

                case .progressOnly(let reason):
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(ChatInputFieldTextSupport.progressLabel(for: reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(outerPadding)
        .zIndex(activeAutocomplete == nil ? 0 : 1)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.bar)
        )
        .sheet(isPresented: $isKeymapPresented) {
            ChatInputKeymapSheet(supportsMidTurnSteering: supportsMidTurnSteering)
        }
    }
}

private struct ChatInputStopButton: View {
    let showsShortcutHint: Bool
    let action: () -> Void

    private let shortcutHintColor = Color(red: 0.74, green: 0.18, blue: 0.17)

    var body: some View {
        Button(action: action) {
            ChatInputActionLabel("Stop", systemImage: "stop.fill")
        }
        .destructiveActionButtonStyle()
        .overlay(alignment: .bottomTrailing) {
            if showsShortcutHint {
                Text("Press Esc again to stop")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(shortcutHintColor)
                    .fixedSize()
                    .offset(y: 18)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }
}
