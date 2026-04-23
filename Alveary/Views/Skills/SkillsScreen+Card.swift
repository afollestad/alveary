import SwiftUI

struct SkillCard: View {
    let skill: Skill
    let onOpen: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(skill.name)
                        .font(.headline)
                        .lineLimit(2)

                    Text(skill.owner.map { owner in
                        guard let repo = skill.repo else { return owner }
                        return "\(owner)/\(repo)"
                    } ?? "Local")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                Text(skill.source == .skillsSh ? "skills.sh" : skill.source.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.14)))
            }

            Text(skill.description.isEmpty ? "No description available." : skill.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if skill.isInstalled, !skill.syncedAgentIDs.isEmpty {
                Text("Synced: \(skill.syncedAgentIDs.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let installs = skill.installs {
                Text("\(installs.formatted()) installs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Details", action: onOpen)
                    .secondaryActionButtonStyle()
                Spacer()
                if skill.isInstalled {
                    Button("Uninstall", role: .destructive, action: onPrimaryAction)
                        .destructiveActionButtonStyle()
                } else {
                    Button("Install", action: onPrimaryAction)
                        .primaryActionButtonStyle()
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
