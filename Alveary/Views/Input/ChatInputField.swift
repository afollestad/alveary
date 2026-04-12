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
    let workingDirectory: String?
    let loadFileCompletions: () async -> [String]
    let loadSkillCompletions: () async -> [Skill]

    private let knownModels = ["default", "opus", "sonnet", "haiku"]
    private let maxAutocompleteResults = 50
    private let autocompleteDebounceNanoseconds: UInt64 = 75_000_000

    @FocusState private var isInputFocused: Bool
    @State private var textSelection: TextSelection?
    @State private var activeAutocomplete: ComposerAutocompleteState?
    @State private var loadTask: Task<Void, Never>?
    @State private var filterTask: Task<Void, Never>?
    @State private var isDropTargeted = false

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTextEditorDisabled: Bool {
        if case .progressOnly = mode {
            return true
        }
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
        if knownModels.contains(selectedModel) {
            return knownModels
        }
        return knownModels + [selectedModel]
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

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                AppTextEditor(
                    text: $text,
                    selection: $textSelection,
                    minHeight: 96,
                    maxHeight: 144,
                    cornerRadius: 18,
                    borderColor: isDropTargeted ? .accentColor : Color.secondary.opacity(0.18),
                    borderWidth: isDropTargeted ? 1.5 : 1,
                    isDisabled: isTextEditorDisabled,
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
                refreshAutocomplete(forceReload: true)
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

                switch mode {
                case .idle:
                    Button(action: performSubmit) {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                    }
                    .primaryActionButtonStyle()
                    .disabled(trimmedText.isEmpty)

                case .busy(let canStop):
                    Button("Queue", action: performSubmit)
                        .primaryActionButtonStyle()
                        .disabled(trimmedText.isEmpty)

                    if canStop {
                        Button(role: .destructive) {
                            onStop?()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
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

            if case .busy(let canStop) = mode,
               canStop,
               supportsMidTurnSteering {
                Text("Press Shift+Enter to steer immediately, Enter to queue, and Option+Enter for a newline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Press Enter to send, or Option+Enter for a newline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.bar)
        )
    }
}

private extension ChatInputField {
    func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        if handleAutocompleteKeyPress(keyPress) {
            return .handled
        }

        guard keyPress.key == .return else {
            return .ignored
        }
        guard !keyPress.modifiers.contains(.option) else {
            return .ignored
        }

        switch mode {
        case .progressOnly:
            return .handled
        case .busy(let canStop):
            if canStop,
               supportsMidTurnSteering,
               keyPress.modifiers.contains(.shift) {
                performSteer()
            } else {
                performSubmit()
            }
            return .handled
        case .idle:
            performSubmit()
            return .handled
        }
    }

    func handleAutocompleteKeyPress(_ keyPress: KeyPress) -> Bool {
        guard var autocomplete = activeAutocomplete else {
            return false
        }

        switch keyPress.key {
        case .upArrow:
            guard !autocomplete.suggestions.isEmpty else {
                return true
            }
            autocomplete.highlightedIndex = max(0, autocomplete.highlightedIndex - 1)
            activeAutocomplete = autocomplete
            return true
        case .downArrow:
            guard !autocomplete.suggestions.isEmpty else {
                return true
            }
            autocomplete.highlightedIndex = min(
                autocomplete.suggestions.count - 1,
                autocomplete.highlightedIndex + 1
            )
            activeAutocomplete = autocomplete
            return true
        case .escape:
            dismissAutocomplete()
            return true
        case .tab:
            return applyHighlightedAutocompleteSuggestion()
        case .return:
            return applyHighlightedAutocompleteSuggestion()
        default:
            return false
        }
    }

    func performSubmit() {
        guard !trimmedText.isEmpty else {
            return
        }
        onSubmit()
    }

    func performSteer() {
        guard !trimmedText.isEmpty else {
            return
        }
        onSteer()
    }

    func refreshAutocomplete(forceReload: Bool = false) {
        guard isInputFocused, !isTextEditorDisabled else {
            dismissAutocomplete()
            return
        }
        guard let token = ChatInputFieldTextSupport.activeCompletionToken(
            text: text,
            textSelection: textSelection
        ) else {
            dismissAutocomplete()
            return
        }

        if forceReload || activeAutocomplete?.kind != token.kind {
            let session = ComposerAutocompleteState(
                sessionID: UUID(),
                kind: token.kind,
                replacementOffsets: token.replacementOffsets,
                query: token.query,
                isLoading: true
            )
            activeAutocomplete = session
            loadAutocompleteSource(for: session)
            return
        }

        guard var autocomplete = activeAutocomplete else {
            return
        }
        autocomplete.replacementOffsets = token.replacementOffsets
        autocomplete.query = token.query
        activeAutocomplete = autocomplete

        guard let source = autocomplete.source else {
            return
        }
        scheduleFiltering(for: autocomplete.sessionID, kind: autocomplete.kind, query: token.query, source: source)
    }

    func loadAutocompleteSource(for autocomplete: ComposerAutocompleteState) {
        loadTask?.cancel()
        filterTask?.cancel()

        loadTask = Task {
            let source: ComposerAutocompleteSource
            switch autocomplete.kind {
            case .file:
                source = .file(await loadFileCompletions())
            case .skill:
                source = .skill(await loadSkillCompletions())
            }

            await MainActor.run {
                guard var current = activeAutocomplete,
                      current.sessionID == autocomplete.sessionID else {
                    return
                }

                current.source = source
                current.isLoading = false
                activeAutocomplete = current

                scheduleFiltering(
                    for: current.sessionID,
                    kind: current.kind,
                    query: current.query,
                    source: source
                )
            }
        }
    }

    func scheduleFiltering(
        for sessionID: UUID,
        kind: ComposerAutocompleteKind,
        query: String,
        source: ComposerAutocompleteSource
    ) {
        filterTask?.cancel()

        filterTask = Task {
            try? await Task.sleep(nanoseconds: autocompleteDebounceNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            let matches = await Task.detached(priority: .userInitiated) {
                ComposerAutocompleteMatcher.matches(
                    for: kind,
                    query: query,
                    source: source,
                    limit: maxAutocompleteResults
                )
            }.value

            await MainActor.run {
                guard var autocomplete = activeAutocomplete,
                      autocomplete.sessionID == sessionID else {
                    return
                }

                autocomplete.suggestions = matches.suggestions
                autocomplete.totalMatches = matches.totalMatches

                if autocomplete.suggestions.isEmpty {
                    autocomplete.highlightedIndex = 0
                } else {
                    autocomplete.highlightedIndex = min(
                        autocomplete.highlightedIndex,
                        autocomplete.suggestions.count - 1
                    )
                }

                activeAutocomplete = autocomplete
            }
        }
    }

    func dismissAutocomplete() {
        loadTask?.cancel()
        filterTask?.cancel()
        activeAutocomplete = nil
    }

    func applyHighlightedAutocompleteSuggestion() -> Bool {
        guard let autocomplete = activeAutocomplete,
              let suggestion = autocomplete.suggestions[safe: autocomplete.highlightedIndex] else {
            return false
        }

        applyAutocompleteSuggestion(suggestion)
        return true
    }

    func applyAutocompleteSuggestion(_ suggestion: ComposerAutocompleteSuggestion) {
        guard let autocomplete = activeAutocomplete else {
            return
        }

        dismissAutocomplete()

        let replacement = suggestion.replacementText
        let (newText, insertionOffset) = ChatInputFieldTextSupport.replacingText(
            in: text,
            offsets: autocomplete.replacementOffsets,
            with: replacement,
            appendTrailingSpace: true
        )

        text = newText
        textSelection = TextSelection(
            insertionPoint: ChatInputFieldTextSupport.index(at: insertionOffset, in: newText)
        )
    }

    func handleDroppedFiles(_ items: [URL]) -> Bool {
        let droppedMentions = items
            .filter { $0.isFileURL }
            .map {
                "@\(ChatInputFieldTextSupport.normalizedMentionPath(for: $0.path, relativeTo: workingDirectory))"
            }

        guard !droppedMentions.isEmpty else {
            return false
        }

        dismissAutocomplete()

        let insertionOffsets: Range<Int>
        if let selection = ChatInputFieldTextSupport.editableSelectionOffsets(
            text: text,
            textSelection: textSelection
        ) {
            insertionOffsets = selection
        } else {
            let end = text.count
            insertionOffsets = end..<end
        }

        let insertion = droppedMentions.joined(separator: " ")
        let (newText, insertionOffset) = ChatInputFieldTextSupport.replacingText(
            in: text,
            offsets: insertionOffsets,
            with: insertion,
            appendTrailingSpace: true,
            ensureLeadingSpace: insertionOffsets.lowerBound > 0
        )

        text = newText
        textSelection = TextSelection(
            insertionPoint: ChatInputFieldTextSupport.index(at: insertionOffset, in: newText)
        )
        isInputFocused = true
        return true
    }
}
