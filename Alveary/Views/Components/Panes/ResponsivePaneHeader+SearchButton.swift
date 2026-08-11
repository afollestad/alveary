import SwiftUI

/// The search field's stand-in once the header is too narrow to hold one. It renders in
/// whichever region the field occupied, so narrowing the pane swaps the control without
/// moving it across the row.
struct PaneHeaderSearchButton: View {
    let search: PaneHeaderSearch

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "magnifyingglass")
        }
        // The accent tint is the active-query cue. It is not the only one — the tooltip
        // and accessibility value both name the query — so it does not stand alone.
        .iconActionButtonStyle(foregroundColor: hasQuery ? Color.accentColor : .primary)
        .help(helpText)
        .accessibilityLabel(search.placeholder)
        .accessibilityValue(query)
        // An AppKit popover, not SwiftUI's: only a popover whose window we own can become
        // `NSApp.keyWindow`, which is what lets the field take typing and ⌘V. See
        // `AppKitAnchoredPopover`.
        .appKitPopover(isPresented: $isPresented, preferredEdge: .maxY) {
            AppTextField(
                search.placeholder,
                text: search.text,
                showsClearButton: true,
                focusesOnAppear: true
            )
            .frame(width: 240)
            .padding(12)
        }
    }

    private var query: String {
        search.text.wrappedValue
    }

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var helpText: String {
        hasQuery ? "\(search.placeholder) (filtering by “\(query)”)" : search.placeholder
    }
}
