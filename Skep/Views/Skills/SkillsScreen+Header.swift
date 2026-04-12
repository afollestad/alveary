import SwiftUI

struct SkillsScreenHeader: View {
    @Binding var searchQuery: String
    let onRefresh: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Skills")
                        .font(.largeTitle.weight(.semibold))

                    Text("Give your agents superpowers.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .secondaryActionButtonStyle()

                Button(action: onCreate) {
                    Label("New Skill", systemImage: "plus")
                }
                .primaryActionButtonStyle()
            }

            AppTextField("Search skills", text: $searchQuery)
        }
    }
}
