import BlockInputKit
import Foundation

final class BlockInputComposerCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private let state: LockedState<CompletionProviderState>
    private let limit: Int

    init(
        location: BlockInputComposerLocation,
        localCommands: ComposerLocalCommandAvailability = ComposerLocalCommandAvailability(),
        passthroughSlashCommands: [ComposerPassthroughSlashCommand] = [],
        limit: Int = 50,
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill]
    ) {
        self.limit = limit
        state = LockedState(CompletionProviderState(
            location: location,
            localCommands: localCommands,
            passthroughSlashCommands: passthroughSlashCommands,
            loadFileCompletions: loadFileCompletions,
            loadSkillCompletions: loadSkillCompletions
        ))
    }

    var location: BlockInputComposerLocation {
        stateSnapshot().location
    }

    func update(
        location: BlockInputComposerLocation,
        localCommands: ComposerLocalCommandAvailability = ComposerLocalCommandAvailability(),
        passthroughSlashCommands: [ComposerPassthroughSlashCommand] = [],
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill]
    ) {
        state.withLock { state in
            state.location = location
            state.localCommands = localCommands
            state.passthroughSlashCommands = passthroughSlashCommands
            state.loadFileCompletions = loadFileCompletions
            state.loadSkillCompletions = loadSkillCompletions
        }
    }

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        let state = stateSnapshot()
        switch context.trigger {
        case .mention:
            let files = await state.loadFileCompletions()
            return fileSuggestions(for: context, location: state.location, files: files)
        case .slashCommand:
            let skills = await state.loadSkillCompletions()
            updateArgumentHints(
                localCommands: state.localCommands,
                passthroughCommands: state.passthroughSlashCommands,
                skills: skills
            )
            return slashCommandSuggestions(
                for: context,
                localCommands: state.localCommands,
                passthroughCommands: state.passthroughSlashCommands,
                skills: skills
            )
        }
    }

    func inlineHint(for context: BlockInputInlineHintContext) -> BlockInputInlineHint? {
        stateSnapshot().skillArgumentHints.inlineHint(for: context)
    }

    private func stateSnapshot() -> CompletionProviderState {
        state.withLock { $0 }
    }

    private func updateArgumentHints(
        localCommands: ComposerLocalCommandAvailability,
        passthroughCommands: [ComposerPassthroughSlashCommand],
        skills: [Skill]
    ) {
        let skillArgumentHints = Self.argumentHints(
            localCommands: localCommands,
            passthroughCommands: passthroughCommands,
            skills: skills
        )
        state.withLock { state in
            state.skillArgumentHints = skillArgumentHints
        }
    }

    private static func argumentHints(
        localCommands: ComposerLocalCommandAvailability,
        passthroughCommands: [ComposerPassthroughSlashCommand],
        skills: [Skill]
    ) -> BlockInputSlashCommandArgumentHints {
        let localHints = localCommands.supportsSessionHandoff
            ? [(command: ComposerLocalCommandKind.handoff.command, hint: "Optional steering prompt")]
            : []
        let passthroughHints = passthroughCommands.compactMap { command -> (command: String, hint: String)? in
            guard let hint = command.argumentHint?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !hint.isEmpty else {
                return nil
            }
            return (command: command.command, hint: hint)
        }
        let skillHints = skills.flatMap { skill in
            guard let argumentHint = skill.argumentHint?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !argumentHint.isEmpty else {
                return [(command: String, hint: String)]()
            }
            return [
                (command: skill.name, hint: argumentHint),
                (command: skill.id, hint: argumentHint)
            ]
        }
        return BlockInputSlashCommandArgumentHints(commandHints: localHints + passthroughHints + skillHints)
    }

    private func fileSuggestions(
        for context: BlockInputCompletionContext,
        location: BlockInputComposerLocation,
        files: [String]
    ) -> [BlockInputCompletionSuggestion] {
        guard let effectiveDirectory = location.effectiveProjectDirectory else {
            return []
        }

        let scope = completionScope(for: context, effectiveDirectory: effectiveDirectory)
        let query = scope.query.lowercased()
        let candidates = files
            .map { fileURL(for: $0, relativeTo: effectiveDirectory) }
            .filter { isFileURL($0, under: scope.baseDirectory) }
            .compactMap { url -> ComposerFileCompletionCandidate? in
                let labelRelativePath = relativePath(for: url, under: scope.baseDirectory)
                guard !labelRelativePath.isEmpty else {
                    return nil
                }
                let insertionDestination = markdownDestination(for: url, relativeTo: effectiveDirectory)
                let candidate = ComposerFileCompletionCandidate(
                    url: url,
                    labelRelativePath: labelRelativePath,
                    insertionDestination: insertionDestination
                )
                return candidate
            }

        let matches = scoredMatches(candidates: candidates, query: query) { candidate, normalizedQuery in
            let fileName = candidate.url.lastPathComponent
            let directory = (candidate.labelRelativePath as NSString).deletingLastPathComponent

            return bestScore(
                matchScore(candidate: fileName, query: normalizedQuery, base: 0),
                matchScore(candidate: candidate.labelRelativePath, query: normalizedQuery, base: 150),
                matchScore(candidate: candidate.insertionDestination, query: normalizedQuery, base: 150),
                matchScore(candidate: directory, query: normalizedQuery, base: 300)
            )
        }

        return matches
            .prefix(limit)
            .map { candidate in
                let label = label(for: candidate, scope: scope)
                return BlockInputCompletionSuggestion(
                    id: candidate.url.path,
                    title: label,
                    subtitle: candidate.url.deletingLastPathComponent().path,
                    insertionText: fileCompletionInsertionText(label: label, destination: candidate.insertionDestination),
                    trigger: .mention,
                    iconSystemName: "doc.text"
                )
            }
    }

    private func slashCommandSuggestions(
        for context: BlockInputCompletionContext,
        localCommands: ComposerLocalCommandAvailability,
        passthroughCommands: [ComposerPassthroughSlashCommand],
        skills: [Skill]
    ) -> [BlockInputCompletionSuggestion] {
        let query = slashCommandQuery(for: context)
        let localSuggestions = localCommandSuggestions(query: query, localCommands: localCommands)
        let passthroughSuggestions = passthroughCommandSuggestions(query: query, commands: passthroughCommands)
        let reservedCommands = Set((localCommands.enabledKinds.map(\.command) + passthroughCommands.map(\.command)).map {
            $0.lowercased()
        })
        let skillSuggestions = scoredMatches(candidates: skills, query: query) { skill, normalizedQuery in
            bestScore(
                matchScore(candidate: skill.name, query: normalizedQuery, base: 0),
                matchScore(candidate: skill.description, query: normalizedQuery, base: 220)
            )
        }
            .filter { !reservedCommands.contains($0.name.lowercased()) && !reservedCommands.contains($0.id.lowercased()) }
            .prefix(limit)
            .map { skill in
                BlockInputCompletionSuggestion.slashCommand(
                    id: skill.id,
                    title: skill.name,
                    subtitle: skill.description,
                    uri: "alveary://skills/\(skill.id)",
                    label: skill.name,
                    insertionStyle: .rawToken,
                    detailText: skill.autocompleteScopeLabel
                )
            }
        return Array((localSuggestions + passthroughSuggestions + skillSuggestions).prefix(limit))
    }

    private func localCommandSuggestions(
        query: String,
        localCommands: ComposerLocalCommandAvailability
    ) -> [BlockInputCompletionSuggestion] {
        scoredMatches(candidates: localCommands.enabledKinds, query: query) { kind, normalizedQuery in
            bestScore(
                matchScore(candidate: kind.command, query: normalizedQuery, base: 0),
                matchScore(candidate: localCommandDescription(kind), query: normalizedQuery, base: 220)
            )
        }
        .map { kind in
            BlockInputCompletionSuggestion.slashCommand(
                id: "alveary://commands/\(kind.command)",
                title: kind.command,
                subtitle: localCommandDescription(kind),
                uri: "alveary://commands/\(kind.command)",
                label: kind.displayName,
                insertionStyle: .rawToken,
                detailText: "Alveary"
            )
        }
    }

    private func slashCommandQuery(for context: BlockInputCompletionContext) -> String {
        let query = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.hasPrefix("/") {
            return String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return query.lowercased()
    }

    private func localCommandDescription(_ kind: ComposerLocalCommandKind) -> String {
        switch kind {
        case .plan:
            "Toggle plan mode"
        case .fast:
            "Enable fast mode"
        case .handoff:
            "Start session handoff"
        }
    }

    private func completionScope(
        for context: BlockInputCompletionContext,
        effectiveDirectory: String
    ) -> ComposerFileCompletionScope {
        if context.rawQuery.hasPrefix("/") {
            let rawURL = URL(fileURLWithPath: context.rawQuery)
            let baseDirectory = context.rawQuery.hasSuffix("/") ? rawURL : rawURL.deletingLastPathComponent()
            let query = context.rawQuery.hasSuffix("/") ? "" : rawURL.lastPathComponent
            return ComposerFileCompletionScope(
                baseDirectory: baseDirectory.standardizedFileURL,
                query: query,
                fileQuery: nil,
                usesAbsoluteLabels: true
            )
        }

        var baseDirectory = URL(fileURLWithPath: effectiveDirectory, isDirectory: true).standardizedFileURL
        for _ in 0..<(context.fileQuery?.levelsUp ?? 0) {
            baseDirectory.deleteLastPathComponent()
        }
        return ComposerFileCompletionScope(
            baseDirectory: baseDirectory,
            query: context.fileQuery?.remainder ?? context.query,
            fileQuery: context.fileQuery,
            usesAbsoluteLabels: false
        )
    }

    private func fileURL(for path: String, relativeTo directory: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent(path)
            .standardizedFileURL
    }

    private func label(
        for candidate: ComposerFileCompletionCandidate,
        scope: ComposerFileCompletionScope
    ) -> String {
        if scope.usesAbsoluteLabels {
            return candidate.url.path
        }
        guard let reference = scope.fileQuery?.directoryReference else {
            return candidate.insertionDestination
        }
        switch reference {
        case .current:
            return "./\(candidate.labelRelativePath)"
        case .parent:
            return "../\(candidate.labelRelativePath)"
        case .grandparent:
            return ".../\(candidate.labelRelativePath)"
        }
    }

    private func isFileURL(_ url: URL, under baseDirectory: URL) -> Bool {
        let basePath = baseDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if basePath == "/" {
            return path.hasPrefix("/")
        }
        return path == basePath || path.hasPrefix(basePath + "/")
    }

    private func relativePath(for url: URL, under baseDirectory: URL) -> String {
        let basePath = baseDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if basePath == "/" {
            return path.replacingPrefix("/", with: "")
        }
        return path.replacingPrefix(basePath + "/", with: "")
    }

    private func markdownDestination(for url: URL, relativeTo directory: String) -> String {
        let basePath = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path != basePath else {
            return "."
        }
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return url.path
    }

    private func markdownLink(label: String, destination: String) -> String {
        "[\(escapedMarkdownLinkLabel(label))](\(escapedMarkdownLinkDestination(destination)))"
    }

    private func fileCompletionInsertionText(label: String, destination: String) -> String {
        "\(markdownLink(label: label, destination: destination)) "
    }

    private func escapedMarkdownLinkLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private func escapedMarkdownLinkDestination(_ destination: String) -> String {
        destination
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    private func scoredMatches<Candidate>(
        candidates: [Candidate],
        query: String,
        score: (Candidate, String) -> Int?
    ) -> [Candidate] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedQuery.isEmpty {
            return candidates
        }

        return candidates
            .compactMap { candidate -> (Candidate, Int)? in
                guard let value = score(candidate, normalizedQuery) else {
                    return nil
                }
                return (candidate, value)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 < rhs.1
                }
                return String(describing: lhs.0) < String(describing: rhs.0)
            }
            .map(\.0)
    }

    private func bestScore(_ scores: Int?...) -> Int? {
        scores.compactMap { $0 }.min()
    }

    private func matchScore(candidate: String, query: String, base: Int) -> Int? {
        let normalizedCandidate = candidate.lowercased()

        if let directRange = normalizedCandidate.range(of: query) {
            let start = normalizedCandidate.distance(from: normalizedCandidate.startIndex, to: directRange.lowerBound)
            return base + start
        }

        return subsequenceScore(candidate: normalizedCandidate, query: query).map {
            base + 500 + $0
        }
    }

    private func subsequenceScore(candidate: String, query: String) -> Int? {
        var queryIndex = query.startIndex
        var candidateIndex = candidate.startIndex
        var lastMatchOffset: Int?
        var gapPenalty = 0

        while queryIndex < query.endIndex, candidateIndex < candidate.endIndex {
            if candidate[candidateIndex] == query[queryIndex] {
                let currentOffset = candidate.distance(from: candidate.startIndex, to: candidateIndex)
                if let lastMatchOffset {
                    gapPenalty += max(0, currentOffset - lastMatchOffset - 1)
                } else {
                    gapPenalty += currentOffset
                }

                lastMatchOffset = currentOffset
                queryIndex = query.index(after: queryIndex)
            }

            candidateIndex = candidate.index(after: candidateIndex)
        }

        guard queryIndex == query.endIndex else {
            return nil
        }

        return gapPenalty
    }
}

private extension BlockInputComposerCompletionProvider {
    func passthroughCommandSuggestions(
        query: String,
        commands: [ComposerPassthroughSlashCommand]
    ) -> [BlockInputCompletionSuggestion] {
        scoredMatches(candidates: commands, query: query) { command, normalizedQuery in
            bestScore(
                matchScore(candidate: command.command, query: normalizedQuery, base: 0),
                matchScore(candidate: command.subtitle, query: normalizedQuery, base: 220)
            )
        }
        .map { command in
            BlockInputCompletionSuggestion.slashCommand(
                id: command.uri,
                title: command.command,
                subtitle: command.subtitle,
                uri: command.uri,
                label: command.displayName,
                insertionStyle: .rawToken,
                detailText: command.detailText
            )
        }
    }
}

private struct CompletionProviderState {
    var location: BlockInputComposerLocation
    var localCommands: ComposerLocalCommandAvailability
    var passthroughSlashCommands: [ComposerPassthroughSlashCommand]
    var loadFileCompletions: @Sendable () async -> [String]
    var loadSkillCompletions: @Sendable () async -> [Skill]
    var skillArgumentHints = BlockInputSlashCommandArgumentHints(commandHints: [])
}

private struct ComposerFileCompletionScope {
    var baseDirectory: URL
    var query: String
    var fileQuery: BlockInputCompletionFileQuery?
    var usesAbsoluteLabels: Bool
}

private struct ComposerFileCompletionCandidate {
    var url: URL
    var labelRelativePath: String
    var insertionDestination: String
}

private extension Skill {
    var autocompleteScopeLabel: String {
        if let repo, !repo.isEmpty {
            return repo
        }
        if let owner, !owner.isEmpty {
            return owner
        }
        return "Personal"
    }
}

private extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }
        return replacement + String(dropFirst(prefix.count))
    }
}
