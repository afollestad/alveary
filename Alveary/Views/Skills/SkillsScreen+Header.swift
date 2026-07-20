import SwiftUI

struct SkillsScreenHeader: View {
    @Binding var searchQuery: String
    let onRefresh: () -> Void
    let onCreate: () -> Void
    var createFocus: FocusState<String?>.Binding?
    var createFocusID = "skills-new"

    var body: some View {
        CompactSearchPaneHeader("Search skills", searchQuery: $searchQuery) {
            Button(action: onRefresh) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
            }
            .secondaryActionButtonStyle()
            .accessibilityLabel("Refresh")

            createButton
        }
    }

    @ViewBuilder
    private var createButton: some View {
        if let createFocus {
            createButtonContent
                .focused(createFocus, equals: createFocusID)
        } else {
            createButtonContent
        }
    }

    private var createButtonContent: some View {
        Button(action: onCreate) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("New Skill")
            }
        }
        .primaryActionButtonStyle()
        .accessibilityLabel("New Skill")
    }
}
