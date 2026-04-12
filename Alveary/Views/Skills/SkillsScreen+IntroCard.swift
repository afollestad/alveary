import SwiftUI

struct SkillsIntroCard: View {
    let onCreate: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Extend your agents with skills")
                        .font(.headline)

                    Text("Skills are reusable modules that give agents new capabilities.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onCreate) {
                    Label("New Skill", systemImage: "plus")
                }
                .primaryActionButtonStyle()
            }
        }
    }
}
