import Foundation
import SwiftUI

extension ChatInputField {
    func loadSkillArgumentHintsIfNeeded() {
        guard !hasLoadedSkillArgumentHints,
              skillHintLoadTask == nil else {
            return
        }

        let loadSkillCompletions = self.loadSkillCompletions

        skillHintLoadTask = Task.detached(priority: .userInitiated) {
            let skills = await loadSkillCompletions()
            let hints = Self.argumentHintsByCommandKey(from: skills)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                skillArgumentHints = hints
                hasLoadedSkillArgumentHints = true
                skillHintLoadTask = nil
            }
        }
    }

    func handleKeyPress(_ keyPress: AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result {
        if handleAutocompleteKeyPress(keyPress) {
            return .handled
        }

        if handleStopShortcutKeyPress(keyPress) {
            return .handled
        }

        guard keyPress.key == .return else {
            return .ignored
        }
        if keyPress.modifiers.contains(.shift) {
            return .ignored
        }

        switch mode {
        case .progressOnly:
            return .handled
        case .busy(let canStop):
            performBusyReturnAction(
                canStop: canStop,
                usesAlternateBehavior: keyPress.modifiers.contains(.option)
            )
            return .handled
        case .idle:
            performSubmit()
            return .handled
        }
    }

    func performBusyReturnAction(canStop: Bool, usesAlternateBehavior: Bool) {
        guard canStop,
              supportsMidTurnSteering else {
            performSubmit()
            return
        }

        switch presentation.busyReturnAction(usesAlternateBehavior: usesAlternateBehavior) {
        case .submit:
            performSubmit()
        case .steer:
            performSteer()
        }
    }

    func handleStopShortcutKeyPress(_ keyPress: AppTextEditorKeyPress) -> Bool {
        switch ChatInputStopConfirmationDecision.resolve(
            keyPress: keyPress,
            canUseEscapeToStop: canUseEscapeToStop,
            isConfirmationArmed: isStopConfirmationArmed
        ) {
        case .ignored:
            return false
        case .confirmStop:
            performStop()
        case .armConfirmation:
            armStopConfirmation()
        }

        return true
    }

    func handleAutocompleteKeyPress(_ keyPress: AppTextEditorKeyPress) -> Bool {
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
            guard !keyPress.modifiers.contains(.shift) else {
                return false
            }
            if Self.shouldSubmitExactSkillAutocomplete(
                text: text,
                autocomplete: autocomplete
            ) {
                return false
            }
            return applyHighlightedAutocompleteSuggestion()
        }
    }

    func performSubmit() {
        guard presentation.canSubmit else {
            return
        }
        onSubmit()
    }

    func performSteer() {
        guard presentation.canSteer else {
            return
        }
        onSteer()
    }

    func performStop() {
        clearStopConfirmation()
        onStop?()
    }

    func armStopConfirmation() {
        stopConfirmationResetTask?.cancel()

        withAnimation(.easeInOut(duration: 0.18)) {
            isStopConfirmationArmed = true
        }

        stopConfirmationResetTask = Task {
            try? await Task.sleep(nanoseconds: stopConfirmationTimeoutNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                if ChatInputStopConfirmationDecision.shouldClearAfterConfirmationTimeout(isStopConfirmationArmed) {
                    clearStopConfirmation()
                }
            }
        }
    }

    func clearStopConfirmation(animated: Bool = true) {
        stopConfirmationResetTask?.cancel()
        stopConfirmationResetTask = nil

        guard isStopConfirmationArmed else {
            return
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                isStopConfirmationArmed = false
            }
        } else {
            isStopConfirmationArmed = false
        }
    }

    func refreshAutocomplete(forceReload: Bool = false) {
        guard !isTextEditorDisabled else {
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
            if loadTask == nil || loadTask?.isCancelled == true {
                autocomplete.isLoading = true
                activeAutocomplete = autocomplete
                loadAutocompleteSource(for: autocomplete)
            }
            return
        }
        scheduleFiltering(for: autocomplete.sessionID, kind: autocomplete.kind, query: token.query, source: source)
    }

    func loadAutocompleteSource(for autocomplete: ComposerAutocompleteState) {
        loadTask?.cancel()
        filterTask?.cancel()

        let loadFileCompletions = self.loadFileCompletions
        let loadSkillCompletions = self.loadSkillCompletions

        // Keep source loading off the main actor so streaming turns do not starve autocomplete.
        loadTask = Task.detached(priority: .userInitiated) {
            let source: ComposerAutocompleteSource
            switch autocomplete.kind {
            case .file:
                source = .file(await loadFileCompletions(), workingDirectory: workingDirectory)
            case .skill:
                let skills = await loadSkillCompletions()
                source = .skill(skills)
                let hints = Self.argumentHintsByCommandKey(from: skills)

                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard activeAutocomplete?.sessionID == autocomplete.sessionID else {
                        return
                    }
                    skillArgumentHints = hints
                    hasLoadedSkillArgumentHints = true
                }
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard var current = activeAutocomplete,
                      current.sessionID == autocomplete.sessionID else {
                    return
                }

                current.source = source
                current.isLoading = false
                activeAutocomplete = current
                loadTask = nil

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

        let autocompleteDebounceNanoseconds = self.autocompleteDebounceNanoseconds
        let maxAutocompleteResults = self.maxAutocompleteResults

        filterTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: autocompleteDebounceNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            let matches = ComposerAutocompleteMatcher.matches(
                for: kind,
                query: query,
                source: source,
                limit: maxAutocompleteResults
            )

            guard !Task.isCancelled else {
                return
            }

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
                filterTask = nil
            }
        }
    }

    func dismissAutocomplete() {
        loadTask?.cancel()
        filterTask?.cancel()
        loadTask = nil
        filterTask = nil
        activeAutocomplete = nil
    }

    func applyHighlightedAutocompleteSuggestion() -> Bool {
        guard let autocomplete = activeAutocomplete,
              let suggestion = autocomplete.suggestions[safe: autocomplete.highlightedIndex] else {
            return false
        }

        applyAutocompleteSuggestion(suggestion, using: autocomplete)
        return true
    }

    func highlightAutocompleteSuggestion(at index: Int) {
        guard var autocomplete = activeAutocomplete,
              autocomplete.suggestions.indices.contains(index),
              autocomplete.highlightedIndex != index else {
            return
        }

        autocomplete.highlightedIndex = index
        activeAutocomplete = autocomplete
    }

    func applyAutocompleteSuggestion(_ suggestion: ComposerAutocompleteSuggestion, using snapshot: ComposerAutocompleteState? = nil) {
        guard let autocomplete = snapshot ?? activeAutocomplete else {
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
                let normalized = ChatInputFieldTextSupport.normalizedMentionPath(
                    for: $0.path,
                    relativeTo: workingDirectory
                )
                return "@\(CanonicalPath.encodeStoredMentionPath(normalized))"
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
            let end = text.utf16.count
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

    nonisolated static func argumentHintsByCommandKey(from skills: [Skill]) -> [String: String] {
        skills.reduce(into: [:]) { hints, skill in
            guard let argumentHint = skill.argumentHint?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !argumentHint.isEmpty else {
                return
            }

            if hints[skill.name] == nil {
                hints[skill.name] = argumentHint
            }
            if hints[skill.id] == nil {
                hints[skill.id] = argumentHint
            }
        }
    }

    nonisolated static func shouldSubmitExactSkillAutocomplete(
        text: String,
        autocomplete: ComposerAutocompleteState
    ) -> Bool {
        guard autocomplete.kind == .skill,
              let suggestion = autocomplete.suggestions[safe: autocomplete.highlightedIndex],
              autocomplete.replacementOffsets.lowerBound >= 0,
              autocomplete.replacementOffsets.upperBound <= text.utf16.count else {
            return false
        }

        let lowerIndex = ChatInputFieldTextSupport.index(
            at: autocomplete.replacementOffsets.lowerBound,
            in: text
        )
        let upperIndex = ChatInputFieldTextSupport.index(
            at: autocomplete.replacementOffsets.upperBound,
            in: text
        )
        return String(text[lowerIndex..<upperIndex]) == suggestion.replacementText
    }
}

// Keep the Escape confirmation state machine pure so unit tests can cover the
// critical stop/cancel decisions without mounting SwiftUI `@State`.
enum ChatInputStopConfirmationDecision: Equatable {
    case ignored
    case armConfirmation
    case confirmStop

    static func resolve(
        keyPress: AppTextEditorKeyPress,
        canUseEscapeToStop: Bool,
        isConfirmationArmed: Bool
    ) -> Self {
        guard keyPress.key == .escape,
              keyPress.modifiers.isEmpty,
              canUseEscapeToStop else {
            return .ignored
        }

        return isConfirmationArmed ? .confirmStop : .armConfirmation
    }

    static func shouldClearWhenStopUnavailable(_ canUseEscapeToStop: Bool) -> Bool {
        !canUseEscapeToStop
    }

    static func shouldClearAfterConfirmationTimeout(_ isConfirmationArmed: Bool) -> Bool {
        isConfirmationArmed
    }
}
