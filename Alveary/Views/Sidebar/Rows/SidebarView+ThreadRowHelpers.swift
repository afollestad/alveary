import AppKit
import SwiftUI

extension SidebarThreadRow {
    @ViewBuilder
    var titleArea: some View {
        if isEditing {
            TextField("Thread name", text: $editText)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .onSubmit { commitRename() }
                .onExitCommand { cancelRename() }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)
        } else {
            ZStack(alignment: .leading) {
                Color.clear

                AppMarkdownInlineLabel(text: displayName)
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .allowsHitTesting(false)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)
            .contentShape(Rectangle())
        }
    }

    // Both branches take `.transition(.identity)` so the pill's width `withAnimation` cannot
    // govern their insertion or removal. Without it the outgoing branch stays painted for the
    // whole 0.18s width change and the incoming one draws over it.
    func cleanupButtonContent(showsConfirm: Bool, showsIcon: Bool) -> some View {
        ZStack(alignment: .trailing) {
            if showsConfirm {
                Text("Confirm")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.identity)
            }
            if showsIcon {
                Image(systemName: sidebarThreadCleanupSystemImage(
                    action: cleanupAction,
                    disabledReason: cleanupDisabledReason,
                    isCleanupButtonHovered: isHoveringCleanupButton
                ))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconForegroundColor)
                    .frame(width: Self.cleanupButtonSize, height: Self.cleanupButtonSize)
                    .transition(.identity)
            }
        }
    }
}

/// Which of the cleanup control's two mutually exclusive contents renders.
struct SidebarThreadCleanupButtonVisibility: Equatable {
    let showsConfirm: Bool
    let showsIcon: Bool
}

/// The archive/delete glyph and the `Confirm` label must never render together — they occupy the
/// same pill and overlap while its width animates. The icon therefore stays hidden for the whole
/// collapse and only returns once the width animation has settled.
func sidebarThreadCleanupButtonVisibility(
    isConfirmationChromeVisible: Bool,
    isCollapsing: Bool
) -> SidebarThreadCleanupButtonVisibility {
    SidebarThreadCleanupButtonVisibility(
        showsConfirm: isConfirmationChromeVisible,
        showsIcon: !isConfirmationChromeVisible && !isCollapsing
    )
}

/// Whether a dismissed confirmation collapses to zero width instead of landing back on the glyph.
/// Confirming always does, regardless of hover, because it always removes the row.
func sidebarThreadCleanupCollapsesToHidden(forCommit: Bool, isHovering: Bool) -> Bool {
    forCommit || !isHovering
}

func sidebarThreadCleanupSystemImage(
    action: ThreadCleanupAction,
    disabledReason: String?,
    isCleanupButtonHovered: Bool
) -> String {
    disabledReason != nil && isCleanupButtonHovered ? "nosign" : action.systemImage
}

/// Returns the trimmed name to commit, or `nil` when the submission is empty or unchanged from
/// the name shown when editing began. Skipping unchanged submissions matters because committing
/// sets `hasCustomName`, which would pin an auto-generated title (see `renameThread`).
func sidebarThreadRenameCommitValue(initialValue: String, submittedValue: String) -> String? {
    let trimmedInitial = initialValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedSubmitted = submittedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSubmitted.isEmpty, trimmedSubmitted != trimmedInitial else {
        return nil
    }
    return trimmedSubmitted
}

/// Resolves the display path on demand from `SidebarThreadRowPresentation.worktreePath`.
/// `CanonicalPath.normalize` stats every path component, so call this from the indicator that
/// shows the tooltip, never while building presentations — that put a filesystem syscall per
/// worktree-backed row into every sidebar body pass.
func sidebarThreadWorktreeTooltipText(worktreePath: String?) -> String {
    guard let worktreePath else {
        return "Worktree path not created yet"
    }
    return CanonicalPath.abbreviateHomeDirectory(CanonicalPath.normalize(worktreePath))
}
