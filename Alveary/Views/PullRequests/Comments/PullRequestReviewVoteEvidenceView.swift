import SwiftUI

/// A local-only disclosure shared by both PR-pane comment surfaces.
struct PullRequestReviewVoteEvidenceView: View, Equatable {
    let presentation: PullRequestReviewVotePresentation

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.presentation == rhs.presentation }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppHeaderToggle(fillsWidth: false) {
                isExpanded.toggle()
            } label: {
                Label(presentation.summary, systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 24)
            }
            .accessibilityLabel(presentation.disclosureLabel(isExpanded: isExpanded))

            if isExpanded {
                ForEach(presentation.reviewers) { reviewer in
                    reviewerSection(reviewer)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
        .onChange(of: presentation.findingID) { _, _ in isExpanded = false }
    }

    @State private var isExpanded = false

    private func reviewerSection(_ reviewer: PullRequestReviewVotePresentation.Reviewer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(reviewer.title).font(.callout.weight(.semibold))
                Spacer(minLength: 0)
                Text(reviewer.status).font(.caption.weight(.semibold))
            }
            Text(reviewer.requestedModel).font(.caption).foregroundStyle(.secondary)
            if !reviewer.rationale.isEmpty {
                AppMarkdownInlineParagraph(text: reviewer.rationale, textStyle: .callout)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(reviewer.accessibilityLabel)
    }
}
