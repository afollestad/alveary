import SwiftUI

struct SidebarSectionHeaderRow: View {
    static let contentLeadingPadding: CGFloat = 8
    static let titleInkLeadingPadding: CGFloat = contentLeadingPadding + titleLeadingOpticalOffset

    static let actionButtonSize: CGFloat = SidebarProjectRow.trailingActionButtonSize
    static let actionButtonCenterTrailingInset = SidebarProjectRow.trailingActionCenterTrailingInset
    // Center inline dividers within the same visual breathing room used by the native Projects boundary.
    static let inlineHeaderTopPaddingCorrection: CGFloat = 11

    private static let actionIconSize: CGFloat = 11
    private static let inlineDividerYOffset: CGFloat = 1.5
    // Keep the trailing action column fixed while aligning title ink with top-level icons.
    private static let titleLeadingOpticalOffset: CGFloat = -3
    private static let trailingPadding = actionButtonCenterTrailingInset - actionButtonSize / 2

    @State private var isHoveringAction = false

    let title: String
    let actionSystemImage: String?
    let actionAccessibilityLabel: String?
    let actionHelp: String?
    let onAction: (() -> Void)?
    let showsTopDivider: Bool
    let isListSectionHeader: Bool

    init(
        title: String,
        showsTopDivider: Bool = false,
        isListSectionHeader: Bool = false,
        onAddProject: (() -> Void)? = nil
    ) {
        self.title = title
        actionSystemImage = onAddProject == nil ? nil : "folder.badge.plus"
        actionAccessibilityLabel = onAddProject == nil ? nil : "Add Project"
        actionHelp = onAddProject == nil ? nil : "Add Project... (\(KeyboardShortcut.addProject.displayString))"
        onAction = onAddProject
        self.showsTopDivider = showsTopDivider
        self.isListSectionHeader = isListSectionHeader
    }

    init(
        title: String,
        showsTopDivider: Bool = false,
        actionSystemImage: String,
        actionAccessibilityLabel: String,
        actionHelp: String,
        onAction: @escaping () -> Void
    ) {
        self.title = title
        self.actionSystemImage = actionSystemImage
        self.actionAccessibilityLabel = actionAccessibilityLabel
        self.actionHelp = actionHelp
        self.onAction = onAction
        self.showsTopDivider = showsTopDivider
        isListSectionHeader = false
    }

    private var dividerLeadingInset: CGFloat {
        Self.contentLeadingPadding + Self.titleLeadingOpticalOffset
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
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.tertiary)
                .offset(x: Self.titleLeadingOpticalOffset)
                .accessibilityAddTraits(.isHeader)

            Spacer()

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Self.contentLeadingPadding)
        .padding(.trailing, Self.trailingPadding)
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
}
