import SwiftUI

/// `Equatable` so a selection change repaints the two rows whose highlight moved rather
/// than every visible row. `onSelect` is deliberately excluded: it is a fresh closure on
/// every pass, and what it captures is a function of `summary`.
struct PullRequestRow: View, Equatable {
    let summary: PullRequestSummary
    let showsRepository: Bool
    let isSelected: Bool
    let referenceDate: Date
    let avatarLoader: GitHubAvatarLoader
    let onSelect: () -> Void

    // `nonisolated` because `View` puts the row on the main actor while `Equatable` is not;
    // every property compared is an immutable `Sendable` one, so the read is safe anywhere.
    nonisolated static func == (lhs: PullRequestRow, rhs: PullRequestRow) -> Bool {
        lhs.summary == rhs.summary
            && lhs.showsRepository == rhs.showsRepository
            && lhs.isSelected == rhs.isSelected
            && lhs.referenceDate == rhs.referenceDate
            && lhs.avatarLoader === rhs.avatarLoader
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PullRequestStatusIcon(status: summary.status)

            VStack(alignment: .leading, spacing: 4) {
                AppMarkdownInlineLabel(
                    text: summary.title,
                    textStyle: .headline,
                    detectsFileMentions: false
                )
                .truncationMode(.tail)

                attributionLine
            }

            Spacer(minLength: 12)

            trailingCluster
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // These rows live in a `ScrollView`, so the card draws its own fill:
        // `.appSelectableRow` publishes selection chrome via `listRowBackground`,
        // which only renders inside a `List`. It reaches press, pending-selection,
        // and hover through `AppSelectableRowState` instead.
        .background(AppSelectableCardBackground(isSelected: isSelected, cornerRadius: 16))
        .appSelectableRow(
            isSelected: isSelected,
            identity: summary.id,
            action: onSelect
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var attributionLine: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                PullRequestAvatarView(
                    login: summary.authorLogin,
                    url: summary.authorAvatarURL,
                    loader: avatarLoader
                )
                Text(summary.authorLogin)
                    .lineLimit(1)
            }

            if showsRepository {
                Text(summary.repositoryNameWithOwner)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(summary.headRefName)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var trailingCluster: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(compactRelativeAge(from: summary.updatedAt, relativeTo: referenceDate))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            diffStats
        }
        .font(.subheadline)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var diffStats: some View {
        HStack(spacing: 4) {
            Text("+\(summary.additions)")
                .foregroundStyle(.green)
            Text("-\(summary.deletions)")
                .foregroundStyle(.red)
        }
        .font(.subheadline.weight(.medium))
        .monospacedDigit()
    }

    private var accessibilityLabel: String {
        let age = compactRelativeAge(from: summary.updatedAt, relativeTo: referenceDate)
        var parts = [
            summary.status.accessibilityName,
            AppMarkdownInlineLabel.plainText(from: summary.title, detectingFileMentions: false),
            "by \(summary.authorLogin)"
        ]
        if showsRepository {
            parts.append("in \(summary.repositoryNameWithOwner)")
        }
        parts.append("branch \(summary.headRefName)")
        parts.append("updated \(age) ago")
        parts.append("\(summary.additions) added, \(summary.deletions) deleted")
        return parts.joined(separator: ", ")
    }
}

/// Glyph and tint for a pull request's status, shared by every surface that
/// draws it at its own size — list rows here, and the thread toolbar button in
/// `ContentView+PullRequestToolbarButton.swift`.
enum PullRequestStatusGlyph {
    /// The 24px artwork, for the larger row icons (18pt frames).
    static func octicon(for status: PullRequestStatus) -> Octicon {
        switch status {
        case .open:
            return .pullRequest24
        case .draft:
            return .pullRequestDraft24
        case .merged:
            return .pullRequestMerge24
        case .closed:
            return .pullRequestClosed24
        }
    }

    /// The 16px artwork, for small frames beside SF Symbols — the toolbar. Its
    /// strokes are drawn bolder for small sizes; the 24px variant renders
    /// visibly thinner (reads lighter) at the same frame. See `OcticonImage`.
    static func octicon16(for status: PullRequestStatus) -> Octicon {
        switch status {
        case .open:
            return .pullRequest16
        case .draft:
            return .pullRequestDraft16
        case .merged:
            return .pullRequestMerge16
        case .closed:
            return .pullRequestClosed16
        }
    }

    /// GitHub's own status tinting; the accessibility name carries the state for
    /// anyone who cannot rely on color. Merged uses Primer's merged purple from the
    /// asset catalog — the system `.purple` reads neon against dark backgrounds.
    /// The AppKit half of `tint(for:)`, for the transcript's native rows. Kept beside it so the
    /// two cannot drift into different colors for the same state.
    static func nsTint(for status: PullRequestStatus) -> NSColor {
        switch status {
        case .open:
            return .systemGreen
        case .draft:
            return .secondaryLabelColor
        case .merged:
            return NSColor(named: "PullRequestMergedColor") ?? .systemPurple
        case .closed:
            return .systemRed
        }
    }

    static func tint(for status: PullRequestStatus) -> Color {
        switch status {
        case .open:
            return .green
        case .draft:
            return .secondary
        case .merged:
            return Color("PullRequestMergedColor")
        case .closed:
            return .red
        }
    }
}

struct PullRequestStatusIcon: View {
    let status: PullRequestStatus
    var isAccessibilityHidden = true

    var body: some View {
        OcticonImage(octicon: PullRequestStatusGlyph.octicon(for: status), size: 18)
            .foregroundStyle(PullRequestStatusGlyph.tint(for: status))
            .accessibilityHidden(isAccessibilityHidden)
            .accessibilityLabel(isAccessibilityHidden ? "" : status.accessibilityName)
    }
}

extension PullRequestStatus {
    var accessibilityName: String {
        switch self {
        case .open:
            return "Open pull request"
        case .draft:
            return "Draft pull request"
        case .merged:
            return "Merged pull request"
        case .closed:
            return "Closed pull request"
        }
    }
}
