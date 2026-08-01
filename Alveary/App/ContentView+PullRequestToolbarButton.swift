import SwiftUI

/// What the toolbar's pull-request button renders. Derived from the selected
/// thread's or project's stored links, so it needs no fetch and no network.
struct PullRequestLinksToolbarState: Equatable {
    let linkCount: Int
    /// The status of the only linked pull request. Nil for zero links and for
    /// two or more, because no single status describes the button then.
    let status: PullRequestStatus?

    init(linkCount: Int, status: PullRequestStatus?) {
        self.linkCount = linkCount
        self.status = status
    }

    init(links: [LinkedPullRequest]) {
        linkCount = links.count
        status = links.count == 1 ? links.first?.summary.status : nil
    }

    /// A single link opens its pane directly; anything else needs the popover to
    /// disambiguate or to collect a URL.
    var opensPaneDirectly: Bool {
        linkCount == 1
    }

    var accessibilityLabel: String {
        switch linkCount {
        case 0:
            return "Link a pull request"
        case 1:
            return "Open linked pull request"
        default:
            return "Linked pull requests"
        }
    }

    var accessibilityValue: String {
        switch linkCount {
        case 0:
            return "None linked"
        case 1:
            guard let status else {
                return "1 linked"
            }
            return "1 linked, \(status.accessibilityName)"
        default:
            return "\(linkCount) linked"
        }
    }

    var helpText: String {
        switch linkCount {
        case 0:
            return "Link a pull request"
        case 1:
            return "Open linked pull request"
        default:
            return "\(linkCount) linked pull requests"
        }
    }
}

struct PullRequestToolbarButton: View {
    let state: PullRequestLinksToolbarState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("Pull Requests")
            } icon: {
                glyph
            }
            .labelStyle(.iconOnly)
            .font(PrimaryToolbarMetrics.iconFont)
            .frame(
                width: PrimaryToolbarMetrics.iconButtonSize,
                height: PrimaryToolbarMetrics.iconButtonSize
            )
        }
    }

    /// With exactly one link the glyph carries that pull request's status, which
    /// needs an explicit tint. That is a deliberate departure from the toolbar's
    /// "no local `foregroundStyle`" rule — see `Alveary/App/AGENTS.md`.
    @ViewBuilder
    private var glyph: some View {
        // 16px artwork, matching the diff button's octicon weight — the 24px
        // variants the rows use render visibly thinner at this frame.
        if let status = state.status {
            OcticonImage(
                name: Self.assetName(for: status),
                size: PrimaryToolbarMetrics.octiconSize
            )
            .foregroundStyle(PullRequestStatusGlyph.tint(for: status))
        } else {
            OcticonImage(name: Self.plainAssetName, size: PrimaryToolbarMetrics.octiconSize)
        }
    }

    /// Draft is the one status that does not use its own artwork here. Primer draws
    /// it as two thin dashes around a void — at this size, 4.5pt of mark, a 6.0pt
    /// hole, then 4.5pt more — which reads as a gap in the row rather than a button
    /// beside the solid diff and settings glyphs. Its `.secondary` tint is already
    /// unique among the statuses, so color still says "draft" without the sparse
    /// shape. List rows keep the dashed artwork, where the glyph has room and a
    /// text label beside it.
    private static func assetName(for status: PullRequestStatus) -> String {
        status == .draft
            ? plainAssetName
            : PullRequestStatusGlyph.assetName16(for: status)
    }

    /// The status-neutral pull-request shape, drawn for no links and for draft.
    private static let plainAssetName = "PullRequestOcticon16"
}
