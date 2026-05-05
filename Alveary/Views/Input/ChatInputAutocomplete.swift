import Foundation

struct ComposerCompletionToken {
    let kind: ComposerAutocompleteKind
    let replacementOffsets: Range<Int>
    let query: String
}

struct ComposerAutocompleteState {
    let sessionID: UUID
    let kind: ComposerAutocompleteKind
    var replacementOffsets: Range<Int>
    var query: String
    var source: ComposerAutocompleteSource?
    var suggestions: [ComposerAutocompleteSuggestion] = []
    var totalMatches = 0
    var highlightedIndex = 0
    var isLoading: Bool
}

enum ComposerAutocompleteKind: Sendable, Equatable {
    case file
    case skill
}

enum ComposerAutocompleteSource: Sendable {
    case file([String], workingDirectory: String?)
    case skill([Skill])
}

struct ComposerAutocompleteSuggestion: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let trailingText: String?
    let replacementText: String
    let symbolName: String
}

struct ComposerAutocompleteMatchResult: Sendable {
    let suggestions: [ComposerAutocompleteSuggestion]
    let totalMatches: Int
}

enum ComposerAutocompleteMatcher {
    static func matches(
        for kind: ComposerAutocompleteKind,
        query: String,
        source: ComposerAutocompleteSource,
        limit: Int
    ) -> ComposerAutocompleteMatchResult {
        switch (kind, source) {
        case (.file, .file(let files, let workingDirectory)):
            return fileMatches(query: query, files: files, workingDirectory: workingDirectory, limit: limit)
        case (.skill, .skill(let skills)):
            return skillMatches(query: query, skills: skills, limit: limit)
        default:
            return ComposerAutocompleteMatchResult(suggestions: [], totalMatches: 0)
        }
    }

    private static func fileMatches(
        query: String,
        files: [String],
        workingDirectory: String?,
        limit: Int
    ) -> ComposerAutocompleteMatchResult {
        let matches = scoredMatches(candidates: files, query: query) { file, normalizedQuery in
            let fileName = (file as NSString).lastPathComponent
            let directory = (file as NSString).deletingLastPathComponent

            return bestScore(
                matchScore(candidate: fileName, query: normalizedQuery, base: 0),
                matchScore(candidate: file, query: normalizedQuery, base: 150),
                matchScore(candidate: directory, query: normalizedQuery, base: 300)
            )
        }

        return ComposerAutocompleteMatchResult(
            suggestions: matches.prefix(limit).map { file in
                return ComposerAutocompleteSuggestion(
                    id: file,
                    title: CanonicalPath.displayMentionPath(file, relativeTo: workingDirectory),
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@\(CanonicalPath.encodeStoredMentionPath(file))",
                    symbolName: "doc.text"
                )
            },
            totalMatches: matches.count
        )
    }

    private static func skillMatches(
        query: String,
        skills: [Skill],
        limit: Int
    ) -> ComposerAutocompleteMatchResult {
        let matches = scoredMatches(candidates: skills, query: query) { skill, normalizedQuery in
            bestScore(
                matchScore(candidate: skill.name, query: normalizedQuery, base: 0),
                matchScore(candidate: skill.description, query: normalizedQuery, base: 220)
            )
        }

        return ComposerAutocompleteMatchResult(
            suggestions: matches.prefix(limit).map { skill in
                ComposerAutocompleteSuggestion(
                    id: skill.id,
                    title: skill.name,
                    subtitle: skill.description,
                    trailingText: skill.autocompleteScopeLabel,
                    replacementText: "/\(skill.name)",
                    symbolName: "shippingbox"
                )
            },
            totalMatches: matches.count
        )
    }

    private static func scoredMatches<Candidate>(
        candidates: [Candidate],
        query: String,
        score: (Candidate, String) -> Int?
    ) -> [Candidate] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedQuery.isEmpty {
            return candidates
        }

        return candidates
            .compactMap { candidate in
                guard let value = score(candidate, normalizedQuery) else {
                    return nil
                }
                return (candidate, value)
            }
            .sorted { (lhs: (Candidate, Int), rhs: (Candidate, Int)) in
                if lhs.1 != rhs.1 {
                    return lhs.1 < rhs.1
                }
                return String(describing: lhs.0) < String(describing: rhs.0)
            }
            .map { $0.0 }
    }

    private static func bestScore(_ scores: Int?...) -> Int? {
        scores.compactMap { $0 }.min()
    }

    private static func matchScore(candidate: String, query: String, base: Int) -> Int? {
        let normalizedCandidate = candidate.lowercased()

        if let directRange = normalizedCandidate.range(of: query) {
            let start = normalizedCandidate.distance(from: normalizedCandidate.startIndex, to: directRange.lowerBound)
            return base + start
        }

        return subsequenceScore(candidate: normalizedCandidate, query: query).map {
            base + 500 + $0
        }
    }

    private static func subsequenceScore(candidate: String, query: String) -> Int? {
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

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
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
