import Foundation
import SwiftUI

struct ComposerAutocompletePopup: View {
    let autocomplete: ComposerAutocompleteState
    let onSelect: (ComposerAutocompleteSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(autocomplete.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(autocomplete.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if autocomplete.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading suggestions...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if autocomplete.suggestions.isEmpty {
                Text("No matches yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(autocomplete.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            Button {
                                onSelect(suggestion)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: suggestion.symbolName)
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(highlightedText(suggestion.title, query: autocomplete.query))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)

                                        if let subtitle = suggestion.subtitle,
                                           !subtitle.isEmpty {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(index == autocomplete.highlightedIndex ? Color.accentColor.opacity(0.14) : .clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

private extension ComposerAutocompletePopup {
    func highlightedText(_ value: String, query: String) -> AttributedString {
        guard !query.isEmpty else {
            return AttributedString(value)
        }

        let normalizedQuery = query.lowercased()
        var queryIndex = normalizedQuery.startIndex
        var highlightedValue = AttributedString()

        for character in value {
            let characterString = String(character)
            let isMatch = queryIndex < normalizedQuery.endIndex &&
                characterString.lowercased() == String(normalizedQuery[queryIndex])

            var segment = AttributedString(characterString)

            if isMatch {
                segment.inlinePresentationIntent = .stronglyEmphasized
                queryIndex = normalizedQuery.index(after: queryIndex)
            }

            highlightedValue.append(segment)
        }

        return highlightedValue
    }
}

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

    var title: String {
        switch kind {
        case .file:
            return "Files"
        case .skill:
            return "Skills"
        }
    }

    var statusLabel: String {
        if isLoading {
            return "Loading"
        }
        guard totalMatches > 0 else {
            return "0 matches"
        }
        return "\(min(highlightedIndex + 1, totalMatches)) of \(totalMatches)"
    }
}

enum ComposerAutocompleteKind: Sendable, Equatable {
    case file
    case skill
}

enum ComposerAutocompleteSource: Sendable {
    case file([String])
    case skill([Skill])
}

struct ComposerAutocompleteSuggestion: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
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
        case (.file, .file(let files)):
            return fileMatches(query: query, files: files, limit: limit)
        case (.skill, .skill(let skills)):
            return skillMatches(query: query, skills: skills, limit: limit)
        default:
            return ComposerAutocompleteMatchResult(suggestions: [], totalMatches: 0)
        }
    }

    private static func fileMatches(
        query: String,
        files: [String],
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
                let fileName = (file as NSString).lastPathComponent
                let directory = (file as NSString).deletingLastPathComponent
                return ComposerAutocompleteSuggestion(
                    id: file,
                    title: fileName,
                    subtitle: directory == "." ? nil : directory,
                    replacementText: "@\(file)",
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
                    replacementText: "/\(skill.name)",
                    symbolName: "sparkles"
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
