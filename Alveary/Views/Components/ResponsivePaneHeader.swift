import SwiftUI

struct PaneHeaderSearch {
    let placeholder: String
    let text: Binding<String>
    /// The field never grows past this. It flexes down to
    /// `PaneHeaderLayout.searchMinimumWidth` before the header trades it for a button.
    var maximumWidth: CGFloat = 360
}

/// Shared chrome for the middle pane's screen headers, which the right pane can squeeze well
/// below `RightPaneWidthPolicy.minimumMainPaneWidth`.
///
/// The header degrades along a fixed ladder — action labels, then the filter chips, then the
/// search field — and `ViewThatFits` takes the first rung the pane can actually hold. Screens
/// supply their own action labels, choosing between text and icon through the `isCompact`
/// argument.
struct ResponsivePaneHeader<Actions: View>: View {
    private let filter: PaneHeaderFilter?
    private let search: PaneHeaderSearch?
    private let actionSpacing: CGFloat
    private let actions: (Bool) -> Actions

    init(
        filter: PaneHeaderFilter? = nil,
        search: PaneHeaderSearch? = nil,
        actionSpacing: CGFloat = PaneHeaderLayout.actionSpacing,
        @ViewBuilder actions: @escaping (_ isCompact: Bool) -> Actions
    ) {
        self.filter = filter
        self.search = search
        self.actionSpacing = actionSpacing
        self.actions = actions
    }

    var body: some View {
        // A width threshold cannot answer this. The five screens mix these parts
        // differently — Scheduled carries chips and no search, MCP a search and no chips —
        // so any single number is wrong for most of them, collapsing controls that had room
        // to spare. Asking the layout which rung fits measures the parts actually present.
        ViewThatFits(in: .horizontal) {
            row(.full)

            row(.iconActions)

            row(.filterDropdown)

            row(.searchButton)
        }
        // Anchor the row's leading edge. A pane narrower than even the last rung would
        // otherwise centre the overflow and let the enclosing pane clip both ends, cutting
        // the leading filter control in half; spilling trailing-only keeps the control the
        // user navigates with intact.
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: PaneHeaderLayout.height)
        .background(.bar)
        .overlay(alignment: .bottom) {
            AppSeparatorHairline(surface: .paneHeader)
        }
    }

    private func row(_ arrangement: PaneHeaderArrangement) -> some View {
        HStack(spacing: 0) {
            leadingRegion(arrangement)

            Spacer(minLength: PaneHeaderLayout.regionSpacing)

            trailingRegion(arrangement)
        }
        .padding(.leading, PaneHeaderLayout.leadingInset)
        .padding(.trailing, PaneHeaderLayout.trailingInset)
        .padding(.vertical, PaneHeaderLayout.verticalPadding)
    }

    @ViewBuilder
    private func leadingRegion(_ arrangement: PaneHeaderArrangement) -> some View {
        if let filter {
            if arrangement.usesFilterDropdown {
                PaneHeaderFilterDropdown(filter: filter)
            } else {
                PaneHeaderFilterChipRow(filter: filter)
            }
        } else if let search {
            searchSlot(search, arrangement)
        }
    }

    /// The search slot trails the filter when both are present, so the chips keep the leading
    /// edge and the field sits beside the actions it filters. It never changes regions —
    /// collapsing is a change of control, not of position.
    private func trailingRegion(_ arrangement: PaneHeaderArrangement) -> some View {
        HStack(spacing: PaneHeaderLayout.searchFieldSpacing) {
            if filter != nil, let search, !arrangement.collapsesSearch {
                searchField(search)
            }

            HStack(spacing: actionSpacing) {
                // Collapsed, the search is just another 30pt icon, so it takes the cluster's
                // own glyph-to-glyph spacing rather than sitting a region gap away and
                // reading as wider-spaced than the actions are from each other. Only from
                // this region: a header whose leading edge is the search would otherwise
                // send the control across the row on the way down.
                if filter != nil, let search, arrangement.collapsesSearch {
                    PaneHeaderSearchButton(search: search)
                }

                actions(arrangement.usesIconActions)
            }
            // Every rung but the last sizes its actions to content, because a rung that
            // does not fit is rejected. The last one has nothing left to trade, so an
            // action whose label has no bounded length — a project name, say — must
            // truncate there instead of pushing the row past the pane.
            .fixedSize(horizontal: !arrangement.isLast, vertical: false)
        }
    }

    @ViewBuilder
    private func searchSlot(_ search: PaneHeaderSearch, _ arrangement: PaneHeaderArrangement) -> some View {
        if arrangement.collapsesSearch {
            PaneHeaderSearchButton(search: search)
        } else {
            searchField(search)
        }
    }

    private func searchField(_ search: PaneHeaderSearch) -> some View {
        AppTextField(search.placeholder, text: search.text, showsClearButton: true)
            // The ideal is pinned to the minimum because `ViewThatFits` chooses rungs by
            // ideal size and a text field's natural ideal follows its content — typing a
            // long query would otherwise flip the arrangement mid-keystroke, in the worst
            // case unmounting the field under the cursor. Pinned, a rung fits exactly when
            // the narrowest usable field does; placement still stretches it to the cap.
            .frame(
                minWidth: PaneHeaderLayout.searchMinimumWidth,
                idealWidth: PaneHeaderLayout.searchMinimumWidth,
                maxWidth: search.maximumWidth
            )
    }
}

/// One rung of the header's degradation ladder, ordered by what costs the user least.
private enum PaneHeaderArrangement {
    case full
    /// Action labels drop to their icons — the cheapest loss, since `.help` and the
    /// accessibility label still name each one.
    case iconActions
    /// The filter chips fold into a dropdown naming the selection. Dearer than the labels:
    /// the other options stop being visible.
    case filterDropdown
    /// The search field becomes a button that opens it in a popover.
    case searchButton

    var usesIconActions: Bool {
        self != .full
    }

    var usesFilterDropdown: Bool {
        self == .filterDropdown || self == .searchButton
    }

    var collapsesSearch: Bool {
        self == .searchButton
    }

    var isLast: Bool {
        self == .searchButton
    }
}
