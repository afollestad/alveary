import Foundation
import SwiftUI

private let composerAutocompletePopupCornerRadius: CGFloat = 18
private let composerAutocompleteRowCornerRadius: CGFloat = 14
private let composerAutocompleteRowSpacing: CGFloat = 12
private let composerAutocompleteListSpacing: CGFloat = 6
private let composerAutocompleteRowVerticalPadding: CGFloat = 10
private let composerAutocompleteMaxVisibleRows: CGFloat = 6
private let composerAutocompleteMaxHeight: CGFloat =
    composerAutocompleteMaxVisibleRows * 40 + (composerAutocompleteMaxVisibleRows - 1) * composerAutocompleteListSpacing

struct ComposerAutocompletePopup: View {
    let autocomplete: ComposerAutocompleteState
    let onSelect: (ComposerAutocompleteSuggestion) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: composerAutocompletePopupCornerRadius, style: .continuous)
                .fill(popupFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: composerAutocompletePopupCornerRadius, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }
}

private extension ComposerAutocompletePopup {
    @ViewBuilder
    var content: some View {
        if autocomplete.isLoading {
            HStack(spacing: composerAutocompleteRowSpacing) {
                ProgressView()
                    .controlSize(.small)

                Text("Loading suggestions…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if autocomplete.suggestions.isEmpty {
            HStack {
                Text("No matches yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: composerAutocompleteListSpacing) {
                        ForEach(Array(autocomplete.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            ComposerAutocompleteRow(
                                kind: autocomplete.kind,
                                suggestion: suggestion,
                                query: autocomplete.query,
                                isHighlighted: index == autocomplete.highlightedIndex,
                                onSelect: {
                                    onSelect(suggestion)
                                }
                            )
                            .id(suggestion.id)
                        }
                    }
                }
                .onAppear {
                    scrollToHighlightedSuggestion(using: proxy)
                }
                .onChange(of: autocomplete.highlightedIndex) {
                    scrollToHighlightedSuggestion(using: proxy)
                }
                .onChange(of: autocomplete.query) {
                    scrollToHighlightedSuggestion(using: proxy)
                }
                .frame(maxHeight: composerAutocompleteMaxHeight)
            }
        }
    }

    var popupFillColor: Color {
        Color(nsColor: .composerAutocompleteFillColor(for: colorScheme))
    }

    func scrollToHighlightedSuggestion(using proxy: ScrollViewProxy) {
        guard let highlightedSuggestionID = autocomplete.suggestions[safe: autocomplete.highlightedIndex]?.id else {
            return
        }

        proxy.scrollTo(highlightedSuggestionID, anchor: .center)
    }
}

private extension NSColor {
    static func composerAutocompleteFillColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
        @unknown default:
            return NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
        }
    }
}

private struct ComposerAutocompleteRow: View {
    let kind: ComposerAutocompleteKind
    let suggestion: ComposerAutocompleteSuggestion
    let query: String
    let isHighlighted: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Group {
                switch kind {
                case .file:
                    fileRow
                case .skill:
                    skillRow
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, composerAutocompleteRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: composerAutocompleteRowCornerRadius, style: .continuous)
                    .fill(isHighlighted ? Color.primary.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private extension ComposerAutocompleteRow {
    var fileRow: some View {
        HStack(spacing: composerAutocompleteRowSpacing) {
            Image(systemName: suggestion.symbolName)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(composerAutocompleteHighlightedText(suggestion.title, query: query))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    var skillRow: some View {
        HStack(spacing: composerAutocompleteRowSpacing) {
            Image(systemName: suggestion.symbolName)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(composerAutocompleteHighlightedText(suggestion.title, query: query))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(2)

            if let subtitle = suggestion.subtitle,
               !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }

            Spacer(minLength: 0)

            if let trailingText = suggestion.trailingText,
               !trailingText.isEmpty {
                Text(trailingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private func composerAutocompleteHighlightedText(_ value: String, query: String) -> AttributedString {
    guard !query.isEmpty else {
        return AttributedString(value)
    }

    if let matchingRange = value.range(
        of: query,
        options: [.caseInsensitive, .diacriticInsensitive]
    ) {
        var highlightedValue = AttributedString(String(value[..<matchingRange.lowerBound]))

        var matchedSegment = AttributedString(String(value[matchingRange]))
        matchedSegment.inlinePresentationIntent = .stronglyEmphasized
        highlightedValue.append(matchedSegment)

        highlightedValue.append(AttributedString(String(value[matchingRange.upperBound...])))
        return highlightedValue
    }

    return composerAutocompleteSubsequenceHighlightedText(value, query: query)
}

private func composerAutocompleteSubsequenceHighlightedText(_ value: String, query: String) -> AttributedString {
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
