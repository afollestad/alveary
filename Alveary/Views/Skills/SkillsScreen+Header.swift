import SwiftUI

struct SkillsScreenHeader: View {
    @Binding var searchQuery: String
    let onRefresh: () -> Void
    let onCreate: () -> Void

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
}
