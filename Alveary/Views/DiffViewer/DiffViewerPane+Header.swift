import SwiftUI

struct DiffViewerPaneHeader: View {
    let activeDirectory: String?
    /// Nil on a detached HEAD, a non-Git directory, or before the first refresh
    /// resolves — the label is simply absent rather than showing a placeholder.
    var branchName: String?
    let mode: DiffViewerMode
    let selectedFiles: [FileStatus]
    let showsFileListDivider: Bool
    let showsFileActions: Bool
    let onModeSelected: (DiffViewerMode) -> Void
    let onStageSelectedFiles: () -> Void
    let onUnstageSelectedFiles: () -> Void
    let onDiscardSelectedFiles: () -> Void
    /// Nil omits the close button, which keeps the existing header previews and
    /// the minimum-width guard measuring the action row on its own.
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            modeTabs

            if let branchName {
                // Priority over the `Spacer`, which is otherwise just as
                // flexible and takes the whole slack, collapsing the label to
                // nothing. The action container's fixed frame is unaffected.
                DiffViewerHeaderBranchLabel(branchName: branchName)
                    .layoutPriority(1)
            }

            Spacer(minLength: 0)

            DiffViewerHeaderActionContainer(actions: headerActions)
        }
        // The close button is *reserved* space plus a pinned overlay, not an
        // `HStack` sibling. This header clips its trailing content rather than
        // compressing, and at the 320pt minimum pane width the chip row plus
        // every action already overflows — as a sibling the button would be the
        // element clipped away. An unreachable action is still reachable from
        // the toolbar and menu; an unreachable close button is not.
        .padding(.trailing, onClose == nil ? 0 : DiffViewerPaneMetrics.headerCloseButtonReservedWidth)
        .overlay(alignment: .trailing) {
            // Matches the contextual panes' trailing close affordance; those use
            // `ContextualPaneHeader`, which this header cannot because it owns a
            // mode chip row instead of a title.
            if let onClose {
                ModalCloseButton("Hide Diff Viewer", action: onClose)
            }
        }
        .animation(diffViewerHeaderActionAnimation, value: headerActionLayoutID)
        .padding(.top, 14)
        .padding(.leading, DiffViewerPaneMetrics.headerLeadingInset)
        .padding(.trailing, DiffViewerPaneMetrics.headerTrailingInset)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(showsFileListDivider ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: showsFileListDivider)
                .allowsHitTesting(false)
        }
    }

    // Commit moved to the pane footer's action ladder; the header keeps only
    // the selection-scoped file actions, which is what lets the chip row and
    // close button fit the 320pt minimum width without clipping.
    private var headerActions: [DiffViewerHeaderAction] {
        var actions: [DiffViewerHeaderAction] = []

        if showsFileActions && hasUnstagedSelection {
            actions.append(DiffViewerHeaderAction(
                id: "stage",
                title: "Stage",
                icon: .octicon("PlusOcticon"),
                isEnabled: true,
                action: onStageSelectedFiles
            ))
        }

        if showsFileActions && hasStagedSelection {
            actions.append(DiffViewerHeaderAction(
                id: "unstage",
                title: "Unstage",
                icon: .octicon("DashOcticon"),
                isEnabled: true,
                action: onUnstageSelectedFiles
            ))
        }

        if showsFileActions && !selectedFiles.isEmpty {
            actions.append(DiffViewerHeaderAction(
                id: "discard",
                title: "Discard",
                icon: .system("arrow.uturn.backward"),
                role: .destructive,
                isEnabled: true,
                action: onDiscardSelectedFiles
            ))
        }

        return actions
    }

    private var headerActionLayoutID: String {
        headerActions.map { "\($0.id):\($0.isEnabled)" }.joined(separator: "|")
    }

    /// Matches the pull-request pane's tab chips so both panes switch sections
    /// the same way; the chips size to the header's own control height instead
    /// of the pane's vertical padding so the row reads as one band.
    private var modeTabs: some View {
        HStack(spacing: diffViewerHeaderActionSpacing) {
            ForEach(DiffViewerMode.allCases, id: \.self) { candidate in
                Button {
                    onModeSelected(candidate)
                } label: {
                    Text(candidate.title)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .frame(height: diffViewerHeaderChipHeight)
                }
                .buttonStyle(TabChipButtonStyle(isSelected: mode == candidate))
                .accessibilityAddTraits(mode == candidate ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Diff viewer mode")
        .accessibilityValue("\(mode.title), \(displayDirectory)")
        // See the pull request pane's tab row: `TabChipButtonStyle`'s rendered output
        // survives a switch that changes nothing structural, which keeping both modes
        // mounted made true, leaving the highlight a selection behind.
        .id(mode)
    }

    private var displayDirectory: String {
        guard let activeDirectory else {
            return "No project selected"
        }

        return CanonicalPath.abbreviateHomeDirectory(activeDirectory)
    }

    private var hasStagedSelection: Bool {
        selectedFiles.contains(where: \.isStaged)
    }

    private var hasUnstagedSelection: Bool {
        selectedFiles.contains { !$0.isStaged }
    }
}

private let diffViewerHeaderChipHeight: CGFloat = 36
private let diffViewerHeaderActionSpacing: CGFloat = 6
/// Caps the branch label so a long name cannot eat the whole header on a wide
/// pane. Deliberately a maximum only: a `minWidth` would make the label
/// inflexible and it would compete with the action container's fixed frame
/// instead of yielding to it, clipping the close button away.
private let diffViewerHeaderBranchLabelMaxWidth: CGFloat = 180
private let diffViewerHeaderBranchLeadingSpacing: CGFloat = 10
private let diffViewerHeaderActionAnimation = Animation.easeInOut(duration: 0.18)
/// Octicons are fixed artwork rather than font-sized symbols, so header glyphs
/// state their own box inside the shared icon button's footprint.
private let diffViewerHeaderOcticonSize: CGFloat = 20

/// Names the checked-out branch beside the mode chips, and is the header's only
/// flexible child — the chips are `fixedSize` and the action container is a
/// fixed reserved width — so it is what SwiftUI shrinks first. Its own type
/// rather than an inline modifier chain so the chain stays off the header
/// `body`'s type-check budget. `.help` keeps the full name discoverable once
/// truncated, matching the file list's `.help(file.path)` convention; tail
/// truncation is right here because branch names disambiguate on their prefix.
private struct DiffViewerHeaderBranchLabel: View {
    let branchName: String

    var body: some View {
        Text(branchName)
            .font(.subheadline.weight(.medium))
            // The concrete dynamic color, not the hierarchical `.secondary`
            // style: this label sits on the header's `.bar` material, and inside
            // that vibrancy a hierarchical style composites against the material
            // rather than painting, which renders the glyphs invisible wherever
            // the backdrop is absent — as in the snapshot host. The chips escape
            // it only because their capsule fill is opaque.
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: diffViewerHeaderBranchLabelMaxWidth, alignment: .leading)
            .clipped()
            .padding(.leading, diffViewerHeaderBranchLeadingSpacing)
            .help(branchName)
            .accessibilityLabel("Current branch")
            .accessibilityValue(branchName)
    }
}

private struct DiffViewerHeaderAction {
    let id: String
    let title: String
    let icon: ActionIcon
    var role: ButtonRole?
    let isEnabled: Bool
    let action: () -> Void
}

private struct DiffViewerHeaderActionContainer: View {
    let actions: [DiffViewerHeaderAction]

    var body: some View {
        HStack(spacing: diffViewerHeaderActionSpacing) {
            ForEach(actions, id: \.id) { action in
                DiffViewerHeaderActionButton(action: action)
                    .help(action.title)
                    .accessibilityLabel(action.title)
                    .disabled(!action.isEnabled)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(.leading, actions.isEmpty ? 0 : diffViewerHeaderActionSpacing)
        .frame(width: reservedWidth, alignment: .trailing)
        .clipped()
        .animation(diffViewerHeaderActionAnimation, value: layoutID)
    }

    private var reservedWidth: CGFloat {
        guard !actions.isEmpty else {
            return 0
        }

        return CGFloat(actions.count) * ActionButtonMetrics.iconButtonDiameter
            + CGFloat(actions.count) * diffViewerHeaderActionSpacing
    }

    private var layoutID: String {
        actions.map { "\($0.id):\($0.isEnabled)" }.joined(separator: "|")
    }
}

/// Header actions wear the shared chromeless icon treatment; only Discard
/// differs, keeping the destructive tint on its glyph rather than a red fill.
private struct DiffViewerHeaderActionButton: View {
    let action: DiffViewerHeaderAction

    var body: some View {
        if action.role == .destructive {
            button.destructiveIconActionButtonStyle()
        } else {
            button.iconActionButtonStyle()
        }
    }

    private var button: some View {
        Button(role: action.role, action: action.action) {
            ActionIconImage(icon: action.icon, octiconSize: diffViewerHeaderOcticonSize)
        }
    }
}
