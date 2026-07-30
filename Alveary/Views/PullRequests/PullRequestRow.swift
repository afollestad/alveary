import SwiftUI

struct PullRequestRow: View {
    let summary: PullRequestSummary
    let showsRepository: Bool
    let isSelected: Bool
    let referenceDate: Date
    let avatarLoader: GitHubAvatarLoader
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PullRequestStatusIcon(status: summary.status)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.headline)
                    .lineLimit(1)
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
        // which only renders inside a `List`.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardFill)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .appSelectableRow(
            isSelected: isSelected,
            identity: summary.id,
            action: onSelect
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var cardFill: Color {
        if isSelected {
            return AppAccentFill.primary
        }
        return Color.secondary.opacity(isHovered ? 0.12 : 0.08)
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
            summary.title,
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

struct PullRequestStatusIcon: View {
    let status: PullRequestStatus
    var isAccessibilityHidden = true

    var body: some View {
        Image(iconAssetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(tint)
            .frame(width: 18, height: 18)
            .accessibilityHidden(isAccessibilityHidden)
            .accessibilityLabel(isAccessibilityHidden ? "" : status.accessibilityName)
    }

    private var iconAssetName: String {
        switch status {
        case .open:
            return "PullRequestOcticon"
        case .draft:
            return "PullRequestDraftOcticon"
        case .merged:
            return "PullRequestMergeOcticon"
        case .closed:
            return "PullRequestClosedOcticon"
        }
    }

    /// GitHub's own status tinting; the accessibility name carries the state for
    /// anyone who cannot rely on color. Merged uses Primer's merged purple from the
    /// asset catalog — the system `.purple` reads neon against dark backgrounds.
    private var tint: Color {
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
