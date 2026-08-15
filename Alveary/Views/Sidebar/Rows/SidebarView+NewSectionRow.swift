import SwiftUI

/// The pending "New Section..." row: a section header whose title is a text field, appended at the
/// bottom because that is where the created section lands.
///
/// Unlike every other creation flow in the app this is inline rather than a dialog, matching the
/// Finder-style rename the sidebar already uses — the user is naming a row in place, and a modal
/// would hide the list the name has to fit into.
struct SidebarNewSectionRow: View {
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    /// Set the moment Enter or Escape resolves the row, so the focus loss that unmounting causes
    /// cannot re-commit — most damagingly after Escape, where a late blur-commit would create the
    /// very section the user just cancelled. The thread rename guards its blur the same way.
    @State private var hasFinished = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            TextField("Section name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(.subheadline, weight: .semibold))
                .focused($isFieldFocused)
                .onSubmit { finish(onCommit) }
                .onExitCommand { finish { _ in onCancel() } }
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .sidebarInlineSectionNameFieldChrome()
        .padding(.leading, SidebarSectionHeaderRow.titleInkLeadingPadding)
        .padding(.trailing, SidebarSectionHeaderRow.actionButtonCenterTrailingInset)
        .padding(.top, SidebarSectionHeaderRow.inlineHeaderTotalTopPadding)
        .onAppear { isFieldFocused = true }
        .onChange(of: isFieldFocused) { _, focused in
            // Clicking away commits whatever was typed, like the thread rename; an empty value
            // still reads as a cancel through `sidebarNewSectionNameCommitValue`.
            if !focused {
                finish(onCommit)
            }
        }
    }

    private func finish(_ resolve: (String) -> Void) {
        guard !hasFinished else {
            return
        }
        hasFinished = true
        resolve(name)
    }
}

extension View {
    /// The Finder inline-rename treatment, shared by the new-section row and the section-header
    /// rename so both read as one input rather than two differently-framed fields.
    func sidebarInlineSectionNameFieldChrome() -> some View {
        padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1)
            )
    }
}

/// The name a submitted new-section field commits, or nil to cancel. Mirrors
/// `sidebarThreadRenameCommitValue`: an empty or whitespace-only name is a cancel, never an error.
func sidebarNewSectionNameCommitValue(_ submittedValue: String) -> String? {
    let trimmed = submittedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// The name a submitted section rename commits, or nil to cancel. Unchanged names cancel too, so
/// a committed rename always means the user actually changed something.
func sidebarSectionRenameCommitValue(initialValue: String, submittedValue: String) -> String? {
    let trimmed = submittedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != initialValue else {
        return nil
    }
    return trimmed
}
