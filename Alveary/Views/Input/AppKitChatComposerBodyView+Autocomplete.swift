@preconcurrency import AppKit

extension AppKitChatComposerBodyView {
    func refreshAutocomplete(forceReload: Bool = false) {
        refreshAutocomplete(text: currentText, forceReload: forceReload)
    }

    func refreshAutocomplete(text: String?, forceReload: Bool = false) {
        guard let configuration,
              !presentation(for: configuration).isTextEditorDisabled else {
            dismissAutocomplete()
            return
        }
        let text = text ?? currentText
        guard let token = ChatInputFieldTextSupport.activeCompletionToken(
            text: text,
            selectedRange: selectedRange
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
            configureAutocompletePopup()
            loadAutocompleteSource(for: session, configuration: configuration)
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
                configureAutocompletePopup()
                loadAutocompleteSource(for: autocomplete, configuration: configuration)
            }
            return
        }
        configureAutocompletePopup()
        scheduleFiltering(for: autocomplete.sessionID, kind: autocomplete.kind, query: token.query, source: source)
    }

    func loadAutocompleteSource(
        for autocomplete: ComposerAutocompleteState,
        configuration: AppKitChatComposerBodyConfiguration
    ) {
        loadTask?.cancel()
        filterTask?.cancel()

        let loadFileCompletions = configuration.loadFileCompletions
        let loadSkillCompletions = configuration.loadSkillCompletions
        let workingDirectory = configuration.workingDirectory

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
                await MainActor.run { [weak self] in
                    guard let self,
                          self.activeAutocomplete?.sessionID == autocomplete.sessionID else {
                        return
                    }
                    self.skillArgumentHints = hints
                    self.hasLoadedSkillArgumentHints = true
                    self.refreshEditorConfiguration()
                }
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self,
                      var current = self.activeAutocomplete,
                      current.sessionID == autocomplete.sessionID else {
                    return
                }
                current.source = source
                current.isLoading = false
                self.activeAutocomplete = current
                self.loadTask = nil
                self.configureAutocompletePopup()
                self.scheduleFiltering(
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
        filterTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: Self.autocompleteDebounceNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            let matches = ComposerAutocompleteMatcher.matches(
                for: kind,
                query: query,
                source: source,
                limit: Self.maxAutocompleteResults
            )

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self,
                      var autocomplete = self.activeAutocomplete,
                      autocomplete.sessionID == sessionID else {
                    return
                }
                autocomplete.suggestions = matches.suggestions
                autocomplete.totalMatches = matches.totalMatches
                autocomplete.highlightedIndex = autocomplete.suggestions.isEmpty ?
                    0 :
                    min(autocomplete.highlightedIndex, autocomplete.suggestions.count - 1)
                self.activeAutocomplete = autocomplete
                self.filterTask = nil
                self.configureAutocompletePopup()
            }
        }
    }

    func dismissAutocomplete() {
        loadTask?.cancel()
        filterTask?.cancel()
        loadTask = nil
        filterTask = nil
        activeAutocomplete = nil
        configureAutocompletePopup()
    }

    func configureAutocompletePopup() {
        let visibleAutocomplete = activeAutocomplete
        autocompletePopupView.configure(
            autocomplete: visibleAutocomplete,
            onSelect: { [weak self] suggestion in
                self?.applyAutocompleteSuggestion(suggestion, autocomplete: visibleAutocomplete)
            },
            onHighlight: { [weak self] index in
                self?.highlightAutocompleteSuggestion(at: index)
            }
        )
        needsLayout = true
        onPreferredSizeInvalidated?()
        enclosingChatSurfaceView()?.refreshSurfaceAutocompletePopup()
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
            configureAutocompletePopup()
            return true
        case .downArrow:
            guard !autocomplete.suggestions.isEmpty else {
                return true
            }
            autocomplete.highlightedIndex = min(autocomplete.suggestions.count - 1, autocomplete.highlightedIndex + 1)
            activeAutocomplete = autocomplete
            configureAutocompletePopup()
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
            if Self.shouldSubmitExactSkillAutocomplete(text: currentText, autocomplete: autocomplete) {
                return false
            }
            return applyHighlightedAutocompleteSuggestion()
        }
    }

    func applyHighlightedAutocompleteSuggestion() -> Bool {
        guard let autocomplete = activeAutocomplete,
              let suggestion = autocomplete.suggestions[safe: autocomplete.highlightedIndex] else {
            return false
        }
        applyAutocompleteSuggestion(suggestion, autocomplete: autocomplete)
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
        configureAutocompletePopup()
    }

    func applyAutocompleteSuggestion(
        _ suggestion: ComposerAutocompleteSuggestion,
        autocomplete visibleAutocomplete: ComposerAutocompleteState? = nil
    ) {
        guard let configuration,
              let autocomplete = visibleAutocomplete ?? activeAutocomplete else {
            return
        }
        dismissAutocomplete()

        let (newText, insertionOffset) = ChatInputFieldTextSupport.replacingText(
            in: currentText,
            offsets: autocomplete.replacementOffsets,
            with: suggestion.replacementText,
            appendTrailingSpace: true
        )
        selectedRange = NSRange(location: insertionOffset, length: 0)
        currentText = newText
        configuration.onTextChange(newText)
        refreshEditorConfiguration()
        restoreEditorFocusAfterAutocompleteInsertion()
    }

    func inlineSlashCommandHint(for configuration: AppKitChatComposerBodyConfiguration) -> AppTextEditorInlineHint? {
        guard let hint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: currentText,
            selectedRange: selectedRange,
            isInputFocused: isComposerFirstResponder,
            commandHints: skillArgumentHints
        ) else {
            return nil
        }
        return AppTextEditorInlineHint(text: hint)
    }

    func loadSkillArgumentHintsIfNeeded() {
        guard !hasLoadedSkillArgumentHints,
              skillHintLoadTask == nil,
              let configuration else {
            return
        }
        let loadSkillCompletions = configuration.loadSkillCompletions
        skillHintLoadTask = Task.detached(priority: .userInitiated) {
            let skills = await loadSkillCompletions()
            let hints = Self.argumentHintsByCommandKey(from: skills)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                self?.skillArgumentHints = hints
                self?.hasLoadedSkillArgumentHints = true
                self?.skillHintLoadTask = nil
                self?.refreshEditorConfiguration()
            }
        }
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

    private func enclosingChatSurfaceView() -> AppKitChatSurfaceView? {
        var candidate = superview
        while let view = candidate {
            if let surface = view as? AppKitChatSurfaceView {
                return surface
            }
            candidate = view.superview
        }
        return nil
    }

    private func restoreEditorFocusAfterAutocompleteInsertion() {
        editorView.claimTextFocus()
        DispatchQueue.main.async { [weak editorView] in
            guard let editorView else {
                return
            }
            guard !editorView.hasTextFocus else {
                return
            }
            editorView.claimTextFocus()
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

        let lowerIndex = ChatInputFieldTextSupport.index(at: autocomplete.replacementOffsets.lowerBound, in: text)
        let upperIndex = ChatInputFieldTextSupport.index(at: autocomplete.replacementOffsets.upperBound, in: text)
        return String(text[lowerIndex..<upperIndex]) == suggestion.replacementText
    }
}
