import SwiftUI

struct SkillsSection: View {
    let title: String
    let skills: [Skill]
    let columns: [GridItem]
    /// Resolved once per `SkillsScreen` body pass rather than read per card, so a pane
    /// opening does not make every section observe `activePaneTarget` on its own.
    let activeDetailSkillID: String?
    let focusedPaneTrigger: FocusState<String?>.Binding
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
                        isSelected: skill.id == activeDetailSkillID,
                        onOpen: {
                            onOpen(skill)
                        },
                        onPrimaryAction: {
                            onPrimaryAction(skill)
                        },
                        cardFocus: focusedPaneTrigger,
                        cardFocusID: SkillsPaneTarget.details(skill.id).defaultFocusRestorationID
                    )
                    .equatable()
                }
            }
            .adaptiveCardGridReflow(columnCount: columns.count)
        }
    }
}
