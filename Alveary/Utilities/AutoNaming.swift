import AgentCLIKit
import Foundation

/// Turns raw provider and user strings into the labels Alveary shows for a thread or conversation.
///
/// These helpers derive a name; they never decide whether one may be stored. The `hasCustomName`
/// gate that protects a manual rename lives in the caller
/// (`ConversationViewModel+EventHandling.swift`), and `Alveary/Data/Threads/AGENTS.md` owns the
/// contract behind it.
extension ConversationViewModel {
    /// Stands in when an app-shot turn carries no visible text — the screenshot alone was the ask.
    static let appShotThreadPreviewFallback = "(App shot)"

    /// Collapses a blank or whitespace-only provider name to `nil` so it falls through to the next
    /// candidate, rather than blanking a thread that already has a usable title.
    static func normalizedProviderSessionName(_ name: String?) -> String? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedName, !trimmedName.isEmpty else {
            return nil
        }
        return trimmedName
    }

    /// The provider's title for a session, preferring `name` over `preview`.
    ///
    /// Both arrive together on `providerSessionMetadataChanged`. `name` is the title the provider
    /// chose to give the session, so it wins whenever it survives normalization; `preview` is the
    /// fallback excerpt. Both go through the app-shot unwrapping, because either can arrive
    /// carrying the generated screenshot preamble instead of what the user actually asked.
    static func providerSessionTitle(
        name: String?,
        preview: String?,
        appShotTitleFallback: String?
    ) -> String? {
        if let name = providerSessionTitleCandidate(name, appShotTitleFallback: appShotTitleFallback) {
            return name
        }
        return providerSessionTitleCandidate(preview, appShotTitleFallback: appShotTitleFallback)
    }

    /// A title built from what the user typed in an app-shot turn, not the preamble wrapped
    /// around it. Falls back to the trimmed input itself when the preview generator returns `nil`,
    /// so this always yields a usable title.
    static func appShotThreadPreviewTitle(fromVisibleUserInput userInput: String) -> String {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return appShotThreadPreviewFallback
        }
        return AgentSessionPreviewGenerator.preview(fromInitialPrompt: trimmedInput) ?? trimmedInput
    }

    /// The prompt answers as a message for the provider, phrased so the model reads them as the
    /// user's reply. Paired with `promptSummary`, which renders the same answers for the human.
    static func formatPromptAnswers(answers: [(question: String, answer: String)]) -> String {
        answers.map { question, answer in
            "For the question '\(question)': \(answer)"
        }
        .joined(separator: "\n")
    }

    /// The same answers as transcript text, which replaces the prompt row's content once answered.
    /// Kept distinct from `formatPromptAnswers` because the transcript wants scannable Q/A pairs
    /// while the provider wants prose.
    static func promptSummary(answers: [(question: String, answer: String)]) -> String {
        answers.map { question, answer in
            let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Q: \(trimmedQuestion)\nA: \(answer)"
        }
        .joined(separator: "\n\n")
    }
}

private extension ConversationViewModel {
    static func providerSessionTitleCandidate(
        _ candidate: String?,
        appShotTitleFallback: String?
    ) -> String? {
        guard let normalized = normalizedProviderSessionName(candidate) else {
            return nil
        }
        if let appShotTitle = appShotProviderSessionTitle(
            from: normalized,
            fallback: appShotTitleFallback
        ) {
            return appShotTitle
        }
        return normalized
    }

    /// Recovers the user's own request from an app-shot title, or `nil` if this is not one.
    ///
    /// An app-shot turn reaches the provider wrapped in a generated preamble, so the provider's
    /// `name` and `preview` both summarize the wrapper rather than the ask. Either of the two
    /// wrapper markers identifies one; `nil` leaves the caller's normalized title in place.
    static func appShotProviderSessionTitle(from providerTitle: String, fallback: String?) -> String? {
        guard providerTitle.hasPrefix("# Applications mentioned by the user:") ||
            providerTitle.contains("<appshot ") else {
            return nil
        }

        if let requestBody = appShotRequestBody(in: providerTitle),
           !requestBody.isEmpty {
            return appShotThreadPreviewTitle(fromVisibleUserInput: requestBody)
        }
        return fallback ?? appShotThreadPreviewFallback
    }

    static func appShotRequestBody(in providerTitle: String) -> String? {
        let lines = providerTitle.components(separatedBy: .newlines)
        guard let requestHeaderIndex = lines.firstIndex(where: {
            $0.hasPrefix("## My request for ") && $0.hasSuffix(":")
        }) else {
            return nil
        }

        let bodyLines = lines.dropFirst(requestHeaderIndex + 1)
        return visibleRequestBody(from: Array(bodyLines))
    }

    /// Strips the blank lines and screenshot image link that lead the request body — chrome the
    /// user did not type, which would otherwise become the title.
    static func visibleRequestBody(from requestBodyLines: [String]) -> String {
        var lines = requestBodyLines
        while let firstLine = lines.first {
            let trimmedLine = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.isEmpty || trimmedLine.hasPrefix("![Appshot screenshot](") else {
                break
            }
            lines.removeFirst()
        }
        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Thread display naming. The single default label lives here so no caller invents its own.
extension AgentThread {
    static let untitledName = "New thread"

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the thread still carries the untouched default. Requires `!hasCustomName` as well
    /// as the matching text, so a user who deliberately typed "New thread" does not read as
    /// unnamed.
    var isEffectivelyUntitled: Bool {
        !hasCustomName && trimmedName == Self.untitledName
    }

    /// The trimmed name to persist for an edit, or `nil` when the user submitted only whitespace.
    /// The caller decides what `nil` means; this never substitutes `untitledName` for a blank.
    static func persistedName(from editedName: String) -> String? {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        return trimmedName
    }

    func displayName() -> String {
        let resolvedName = trimmedName
        return resolvedName.isEmpty ? Self.untitledName : resolvedName
    }
}

/// Conversation display naming, which follows the thread's rather than duplicating it.
extension Conversation {
    /// The user's own title, or `nil` while the conversation is still showing a derived label.
    /// This nil-ness is the flag the rename cascade reads, so nothing may store the default here.
    var customTitle: String? {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedTitle, !trimmedTitle.isEmpty else {
            return nil
        }

        return trimmedTitle
    }

    /// The label for a conversation with no title of its own. The main conversation borrows the
    /// thread's default rather than a word like "Main", so a sole conversation and its thread read
    /// as one thing; secondaries are numbered from their display order.
    func defaultDisplayName() -> String {
        if isMain {
            return AgentThread.untitledName
        }

        return "Conversation (\(displayOrder + 1))"
    }

    /// The title to persist for an edit, or `nil` to leave the conversation untitled.
    ///
    /// An edit that submits the displayed default unchanged, on a conversation that has no title
    /// of its own yet, returns `nil` rather than storing it. Storing it would make `customTitle`
    /// non-nil and freeze today's thread name into the row, so the next thread rename would stop
    /// cascading — see `shouldFollowThreadRename(previousThreadDisplayName:)`.
    static func persistedTitle(
        from editedTitle: String,
        fallbackName: String,
        hasCustomTitle: Bool
    ) -> String? {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return nil
        }

        if !hasCustomTitle, trimmedTitle == fallbackName {
            return nil
        }

        return trimmedTitle
    }

    func persistedTitle(from editedTitle: String) -> String? {
        Self.persistedTitle(
            from: editedTitle,
            fallbackName: defaultDisplayName(),
            hasCustomTitle: customTitle != nil
        )
    }

    func displayName() -> String {
        customTitle ?? defaultDisplayName()
    }

    /// Whether a thread rename should carry into this conversation's title.
    ///
    /// True while the user has not explicitly diverged it — either it still uses its default
    /// fallback, or its visible name still matches the thread's previous visible name. The second
    /// clause is what keeps repeated renames in sync: once the first cascade populates `title`,
    /// `customTitle` is no longer nil, so only the name comparison can recognize the conversation
    /// as still following. `Alveary/Data/Threads/AGENTS.md` owns why the cascade exists at all.
    func shouldFollowThreadRename(previousThreadDisplayName: String) -> Bool {
        customTitle == nil || displayName() == previousThreadDisplayName
    }
}
