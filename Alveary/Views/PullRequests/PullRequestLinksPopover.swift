import SwiftUI

/// The toolbar button's popover: the selected thread's or project's linked pull
/// requests, each removable, above a field for linking another. One component
/// covers every count — with nothing linked it is just the field. A project's
/// rows include links stored on its child threads, labeled with their thread.
struct PullRequestLinksPopover: View {
    let links: [OwnedPullRequestLink]
    let isLinking: Bool
    let errorMessage: String?
    let showsGitSettingsAction: Bool
    let onOpen: (OwnedPullRequestLink) -> Void
    let onRemove: (OwnedPullRequestLink) -> Void
    let onLink: (String) -> Void
    let onOpenGitSettings: () -> Void
    let onEditURL: () -> Void

    /// Sibling surfaces release the composer before claiming the keyboard; see
    /// "Focus And Keyboard Coordination" in `Alveary/Views/AGENTS.md`. Without
    /// it the composer's focus retry keeps first responder in the presenting
    /// window, so ⌘V lands there instead of in this popover's field.
    @FocusedValue(\.chatComposerFocus) private var chatComposerFocus

    @State private var urlText = ""

    private let contentWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !links.isEmpty {
                linkedSection

                Divider()
            }

            linkField

            if let errorMessage {
                errorSection(errorMessage)
            }
        }
        .padding(14)
        .frame(width: contentWidth)
        // The field clears only when the link lands, not at submit time, so a
        // failed validation leaves the pasted URL in place for a retry.
        .onChange(of: links.count) { previousCount, newCount in
            if newCount > previousCount {
                urlText = ""
            }
        }
        // Release before the field claims. `release()` resigns the *presenting*
        // window's first responder, so it must run while that window is still
        // key — the field's own mount focus then restores this popover's.
        .task {
            chatComposerFocus?.release()
        }
    }

    private var linkedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Linked pull requests")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)

            ForEach(links) { row in
                PullRequestLinkRow(
                    row: row,
                    onOpen: { onOpen(row) },
                    onRemove: { onRemove(row) }
                )
            }
        }
    }

    private var linkField: some View {
        HStack(spacing: 8) {
            // Focus on mount: the popover exists to take a paste, so the field
            // must be ready the moment it opens, without a click first.
            AppTextField("Paste a pull request URL", text: $urlText, focusesOnAppear: true)
                .onChange(of: urlText) { _, _ in
                    onEditURL()
                }
                .onSubmit(submit)

            // Return submits from anywhere in the popover; the field's own
            // `onSubmit` covers it while focused. A double fire is safe — the
            // second call trips the link store's `isLinking` guard.
            Button(action: submit) {
                ActionButtonLabel(title: isLinking ? "Linking..." : "Link", icon: .system("link"))
            }
            .primaryActionButtonStyle()
            .keyboardShortcut(.defaultAction)
            .disabled(isLinking || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

            // A missing or signed-out `gh` is fixed in settings, not by retyping.
            if showsGitSettingsAction {
                Button(action: onOpenGitSettings) {
                    ActionButtonLabel(title: "Open Git Settings", icon: .system("gearshape"))
                }
                .secondaryActionButtonStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLinking, !trimmed.isEmpty else {
            return
        }
        onLink(trimmed)
    }
}

private struct PullRequestLinkRow: View {
    let row: OwnedPullRequestLink
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        rowContent
            // `appSelectableRow` publishes its fill through `listRowBackground`,
            // which only renders inside a `List`, so the row draws its own hover
            // surface here — the same split `PullRequestRow` uses on the screen.
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
            .appSelectableRow(isSelected: false, identity: row.id, action: onOpen)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(row.link.summary.status.accessibilityName)
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            PullRequestStatusIcon(status: row.link.summary.status)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.link.summary.title)
                    .lineLimit(1)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
            }
            .destructiveIconActionButtonStyle()
            .help("Unlink \(row.id.displayKey)")
            .accessibilityLabel("Unlink \(row.id.displayKey)")
        }
    }

    /// A child-thread row names its thread so a project's aggregate reads as
    /// "where did this come from" without opening anything.
    private var detailText: String {
        guard let sourceLabel = row.sourceLabel else {
            return row.id.displayKey
        }
        return "\(row.id.displayKey) · \(sourceLabel)"
    }

    private var accessibilityLabel: String {
        let base = "\(row.link.summary.title), \(row.id.displayKey)"
        guard let sourceLabel = row.sourceLabel else {
            return base
        }
        return "\(base), linked on thread \(sourceLabel)"
    }
}
