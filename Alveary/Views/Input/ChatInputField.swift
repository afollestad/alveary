import Foundation
import SwiftUI

struct ChatInputField: View {
    @Binding var text: String
    let mode: ComposerMode
    let onSubmit: () -> Void
    let onSteer: () -> Void
    let onStop: (() -> Void)?
    @Binding var selectedModel: String
    @Binding var selectedEffort: String
    @Binding var selectedPermissionMode: String
    let supportedPermissionModes: [PermissionModeOption]
    let supportedEffortLevels: [String]
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
    let composerHorizontalPadding: CGFloat = 10
    let composerVerticalPadding: CGFloat = 10
    let composerBaseHeight: CGFloat = 68

    @FocusState var isInputFocused: Bool
    @State var textSelection: TextSelection?
    @State var activeAutocomplete: ComposerAutocompleteState?
    @State var loadTask: Task<Void, Never>?
    @State var filterTask: Task<Void, Never>?
    @State private var isDropTargeted = false
    @State private var isKeymapPresented = false

    init(
        text: Binding<String>,
        mode: ComposerMode,
        onSubmit: @escaping () -> Void,
        onSteer: @escaping () -> Void,
        onStop: (() -> Void)?,
        selectedModel: Binding<String>,
        selectedEffort: Binding<String>,
        selectedPermissionMode: Binding<String>,
        supportedPermissionModes: [PermissionModeOption],
        supportedEffortLevels: [String],
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
        _selectedModel = selectedModel
        _selectedEffort = selectedEffort
        _selectedPermissionMode = selectedPermissionMode
        self.supportedPermissionModes = supportedPermissionModes
        self.supportedEffortLevels = supportedEffortLevels
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
                return "Send a message to steer, or queue for next turn..."
            }
            return "Type a message to queue for the next turn..."
        case .progressOnly(.initialSetup):
            return "Preparing the conversation for its first turn..."
        case .progressOnly(.reconfiguringSession):
            return "Applying session changes..."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let autocomplete = activeAutocomplete {
                ComposerAutocompletePopup(
                    autocomplete: autocomplete,
                    onSelect: applyAutocompleteSuggestion
                )
            }

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
                    keyPressKeys: [.upArrow, .downArrow, .tab, .escape, .return],
                    onKeyPress: handleKeyPress
                )
            }
            .dropDestination(for: URL.self) { items, _ in
                handleDroppedFiles(items)
            } isTargeted: { isTargeted in
                isDropTargeted = isTargeted
            }
            .onChange(of: text) {
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
            .onDisappear {
                loadTask?.cancel()
                filterTask?.cancel()
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
                            Text(option.label).tag(option.value)
                        }
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
                        Button {
                            onStop?()
                        } label: {
                            ChatInputActionLabel("Stop", systemImage: "stop.fill")
                        }
                        .destructiveActionButtonStyle()
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.bar)
        )
        .sheet(isPresented: $isKeymapPresented) {
            ChatInputKeymapSheet(supportsMidTurnSteering: supportsMidTurnSteering)
        }
    }
}
