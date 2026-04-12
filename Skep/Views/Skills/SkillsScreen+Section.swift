import SwiftUI

struct SkillsSection: View {
    let title: String
    let skills: [Skill]
    let columns: [GridItem]
    let onOpen: (Skill) -> Void
    let onPrimaryAction: (Skill) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(skills) { skill in
                    SkillCard(
                        skill: skill,
                        onOpen: {
                            onOpen(skill)
                        },
                        onPrimaryAction: {
                            onPrimaryAction(skill)
                        }
                    )
                }
            }
        }
    }
}
