import SwiftUI

struct SidebarSectionHeaderRow: View {
    static let contentLeadingPadding: CGFloat = 8
    /// Leading padding that lands a plain row's ink under a header's title ink. It carries the
    /// plain-row correction because every consumer is a row rather than a `List` section header.
    static let titleInkLeadingPadding: CGFloat = contentLeadingPadding
        + titleLeadingOpticalOffset
        + SidebarProjectListMetrics.plainRowLeadingCorrection

    static let actionButtonSize: CGFloat = SidebarProjectRow.trailingActionButtonSize
    static let actionButtonCenterTrailingInset = SidebarProjectRow.trailingActionCenterTrailingInset
    // Center inline dividers within the same visual breathing room used by the native Projects boundary.
    static let inlineHeaderTopPaddingCorrection: CGFloat = 11
    /// Full leading padding above an inline header's title, including the divider's breathing room.
    /// Drag geometry excludes all of it so a section border hugs the visible header rather than
    /// floating above it.
    static let inlineHeaderTotalTopPadding = SidebarRowMetrics.pinnedThreadBoundarySpacing
        + inlineHeaderTopPaddingCorrection

    private static let actionIconSize: CGFloat = 11
    private static let inlineDividerYOffset: CGFloat = 1.5
    // Keep the trailing action column fixed while pulling title ink left of the row content inset.
    private static let titleLeadingOpticalOffset: CGFloat = -3
    private static let trailingPadding = actionButtonCenterTrailingInset - actionButtonSize / 2

    @State private var isHoveringAction = false
    @State private var isHoveringRow = false

    let title: String
    let actionSystemImage: String?
    let actionAccessibilityLabel: String?
    let actionHelp: String?
    let onAction: (() -> Void)?
    let showsTopDivider: Bool
    let isListSectionHeader: Bool
    let disclosure: SidebarSectionHeaderDisclosure?
    let suppressHoverAffordances: Bool

    init(
        title: String,
        showsTopDivider: Bool = false,
        isListSectionHeader: Bool = false,
        disclosure: SidebarSectionHeaderDisclosure? = nil,
        suppressHoverAffordances: Bool = false,
        initialRowHover: Bool = false,
        onAddProject: (() -> Void)? = nil
    ) {
        self.title = title
        actionSystemImage = onAddProject == nil ? nil : "folder.badge.plus"
        actionAccessibilityLabel = onAddProject == nil ? nil : "Add Project"
        actionHelp = onAddProject == nil ? nil : "Add Project... (\(KeyboardShortcut.addProject.displayString))"
        onAction = onAddProject
        self.showsTopDivider = showsTopDivider
        self.isListSectionHeader = isListSectionHeader
        self.disclosure = disclosure
        self.suppressHoverAffordances = suppressHoverAffordances
        _isHoveringRow = State(initialValue: initialRowHover)
    }

    init(
        title: String,
        showsTopDivider: Bool = false,
        actionSystemImage: String,
        actionAccessibilityLabel: String,
        actionHelp: String,
        disclosure: SidebarSectionHeaderDisclosure? = nil,
        suppressHoverAffordances: Bool = false,
        initialRowHover: Bool = false,
        onAction: @escaping () -> Void
    ) {
        self.title = title
        self.actionSystemImage = actionSystemImage
        self.actionAccessibilityLabel = actionAccessibilityLabel
        self.actionHelp = actionHelp
        self.onAction = onAction
        self.showsTopDivider = showsTopDivider
        isListSectionHeader = false
        self.disclosure = disclosure
        self.suppressHoverAffordances = suppressHoverAffordances
        _isHoveringRow = State(initialValue: initialRowHover)
    }

    /// Pulls a row-mounted header back to the leading inset a `List` section header gets for free.
    private var leadingCorrection: CGFloat {
        isListSectionHeader ? 0 : SidebarProjectListMetrics.plainRowLeadingCorrection
    }

    private var dividerLeadingInset: CGFloat {
        Self.contentLeadingPadding + Self.titleLeadingOpticalOffset + leadingCorrection
    }

    private var dividerYOffset: CGFloat {
        isListSectionHeader ? SidebarProjectListMetrics.listHeaderDividerYOffset : Self.inlineDividerYOffset
    }

    private var headerTopPadding: CGFloat {
        SidebarRowMetrics.pinnedThreadBoundarySpacing
            + headerTopPaddingCorrection
    }

    private var headerTopPaddingCorrection: CGFloat {
        if isListSectionHeader {
            return SidebarProjectListMetrics.listHeaderTopPaddingCorrection
        }
        return showsTopDivider ? Self.inlineHeaderTopPaddingCorrection : 0
    }

    private var trailingCorrection: CGFloat {
        isListSectionHeader ? SidebarProjectListMetrics.listSectionHeaderTrailingCorrection : 0
    }

    var body: some View {
        HStack {
            titleCluster

            Spacer()

            actionControl
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Self.contentLeadingPadding + leadingCorrection)
        .padding(.trailing, Self.trailingPadding)
        // Shaping the title row rather than the padded whole keeps the toggle on the header itself,
        // so a click in the section gap above it does nothing. This has to be the row's own content
        // shape, not a backing rectangle: `Text` hit-tests its own frame, so a background layer
        // never saw a click that landed on the title.
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleFromRow)
        .onHover { isHovering in
            withAnimation(SidebarDisclosureCaretMetrics.toggleAnimation) {
                isHoveringRow = isHovering
            }
        }
        .padding(.top, headerTopPadding)
        .padding(.bottom, 0)
        .padding(.trailing, trailingCorrection)
        .overlay(alignment: .top) {
            if showsTopDivider {
                Divider()
                    .opacity(0.5)
                    .padding(.leading, dividerLeadingInset)
                    .padding(.trailing, Self.trailingPadding + trailingCorrection)
                    .padding(.top, SidebarRowMetrics.pinnedThreadBoundarySpacing / 2)
                    .offset(y: dividerYOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var titleCluster: some View {
        HStack(spacing: SidebarDisclosureCaretMetrics.spacing) {
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.tertiary)

            if let disclosure {
                SidebarDisclosureCaret(
                    isExpanded: disclosure.isExpanded,
                    isRowHovering: isHoveringRow,
                    suppressHoverAffordances: suppressHoverAffordances,
                    toggle: SidebarDisclosureCaretToggle(
                        label: toggleLabel(isExpanded: disclosure.isExpanded),
                        action: disclosure.onToggle
                    )
                )
            }
        }
        // Offsetting the cluster rather than the title keeps the caret's gap measured from the
        // title's ink, which is what aligns it with the project rows below.
        .offset(x: Self.titleLeadingOpticalOffset)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(disclosure == nil ? .isHeader : [.isHeader, .isButton])
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var actionControl: some View {
        if let onAction, let actionSystemImage, let actionAccessibilityLabel, let actionHelp {
            Button(action: onAction) {
                Image(systemName: actionSystemImage)
                    .font(.system(size: Self.actionIconSize, weight: .semibold))
                    .foregroundStyle(.primary.opacity(isHoveringAction ? 0.9 : 0.68))
                    .frame(width: Self.actionButtonSize, height: Self.actionButtonSize)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isHoveringAction ? 0.12 : 0))
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { isHovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHoveringAction = isHovering
                }
            }
            .accessibilityLabel(actionAccessibilityLabel)
            .help(actionHelp)
        } else {
            Color.clear
                .frame(width: Self.actionButtonSize, height: Self.actionButtonSize)
                .accessibilityHidden(true)
        }
    }

    /// The whole header row toggles its section. The caret and the trailing action button are
    /// children with gestures of their own, so hit testing reaches them first and each keeps taking
    /// its own clicks. A header without a disclosure has nothing to toggle and absorbs the tap.
    private func toggleFromRow() {
        guard let disclosure else {
            return
        }

        withAnimation(SidebarDisclosureCaretMetrics.toggleAnimation) {
            disclosure.onToggle()
        }
    }

    private var accessibilityLabel: String {
        guard let disclosure else {
            return title
        }
        return toggleLabel(isExpanded: disclosure.isExpanded)
    }

    private func toggleLabel(isExpanded: Bool) -> String {
        isExpanded ? "Collapse \(title)" : "Expand \(title)"
    }
}

/// The collapse affordance a section header shows. Absent on `Pinned`, which heads a group the user
/// does not choose to hide.
struct SidebarSectionHeaderDisclosure {
    let isExpanded: Bool
    let onToggle: () -> Void
}
