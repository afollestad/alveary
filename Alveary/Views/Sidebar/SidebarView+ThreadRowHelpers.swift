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

    func cleanupButtonContent(showsConfirm: Bool, showsIcon: Bool) -> some View {
        ZStack(alignment: .trailing) {
            if showsConfirm {
                Text("Confirm")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            }
        }
    }
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

func sidebarThreadWorktreeTooltipText(for thread: AgentThread) -> String {
    if let path = thread.worktreePath,
       !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let canonicalPath = CanonicalPath.normalize(path.trimmingCharacters(in: .whitespacesAndNewlines))
        return CanonicalPath.abbreviateHomeDirectory(canonicalPath)
    }

    return "Worktree path not created yet"
}
