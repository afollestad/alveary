import SwiftData
import SwiftUI

/// The threads and projects that link the pull request being viewed.
///
/// The queries read local columns only, so the section renders in the same
/// frame as the rest of the detail content instead of popping in later, and it
/// adds nothing to the detail fetch. It draws nothing when the pull request is
/// unlinked.
struct PullRequestPaneLinkedOwners: View {
    let identifier: PullRequestIdentifier

    @Query(PullRequestLinkedOwnerLookup.linkHoldingThreads) private var threads: [AgentThread]
    @Query(PullRequestLinkedOwnerLookup.linkHoldingProjects) private var projects: [Project]
    @Environment(\.pullRequestLinkedOwnerOpenAction) private var openOwner

    var body: some View {
        // The lookup drops rows a delete already removed; this pass then reads each survivor's
        // name into a value while it is still known live, because a `ForEach` content closure runs
        // later and a model read deferred into one can trap (`PullRequestLinkedOwnerLookup.owners`
        // owns the liveness half).
        let owners = PullRequestLinkedOwnerLookup.owners(
            projects: projects,
            threads: threads,
            linking: identifier
        )
        if !owners.isEmpty {
            PullRequestOverviewSection(PullRequestLinkedOwnerLookup.title(for: owners)) {
                PullRequestOverviewSectionRows {
                    ForEach(owners.map(PullRequestLinkedOwnerPresentation.init)) { owner in
                        PullRequestLinkedOwnerRow(owner: owner) {
                            openOwner?(owner.linkOwner)
                        }
                    }
                }
            }
        }
    }
}

/// One linked owner as values, resolved while the row behind it is known live.
private struct PullRequestLinkedOwnerPresentation: Identifiable {
    let id: PersistentIdentifier
    let displayName: String
    let isProject: Bool
    let linkOwner: PullRequestLinkOwner

    init(_ owner: PullRequestLinkingOwner) {
        id = owner.id
        displayName = owner.displayName
        isProject = owner.isProject
        linkOwner = owner.linkOwner
    }
}

/// One linked thread or project. The glyph is the only thing separating the two
/// kinds visually, so it matches the icon each already wears elsewhere: the
/// sidebar's project row and the `list_threads` tool row.
private struct PullRequestLinkedOwnerRow: View {
    let owner: PullRequestLinkedOwnerPresentation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            rowContent
        }
        .buttonStyle(PullRequestPaneRowButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(owner.isProject ? "Shows the project in the sidebar" : "Shows the thread in the sidebar")
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Image(systemName: owner.isProject ? "folder" : "bubble.left.and.bubble.right")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
                .accessibilityHidden(true)

            Text(owner.displayName)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            // Decorative: the whole row is the hit target.
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .contextualPaneTrailingGlyphLane()
                .accessibilityHidden(true)
        }
    }

    /// The glyph carries the kind visually, so the label carries it in text.
    private var accessibilityLabel: String {
        owner.isProject ? "Project \(owner.displayName)" : "Thread \(owner.displayName)"
    }
}
