import SwiftUI

struct SkillCard: View, Equatable {
    let skill: Skill
    let isSelected: Bool
    let onOpen: () -> Void
    let onPrimaryAction: () -> Void
    let cardFocus: FocusState<String?>.Binding
    let cardFocusID: String

    /// The actions and the focus binding are excluded: the actions close over the `skill`
    /// compared here plus the screen's view-model reference and its `@State` confirmation
    /// box, and the binding reads the screen's `@FocusState` storage — none of which a
    /// captured copy can serve staler than a fresh one. `isSelected` is compared because
    /// it drives the card's fill.
    nonisolated static func == (lhs: SkillCard, rhs: SkillCard) -> Bool {
        lhs.skill == rhs.skill
            && lhs.isSelected == rhs.isSelected
            && lhs.cardFocusID == rhs.cardFocusID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(skill.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                trailingControls
            }

            SkillCardMetaLine(skill: skill)

            Text(skill.description.isEmpty ? "No description available." : skill.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        // Height is content-driven — every text run here is line-limited, so there is no
        // fixed height to pick. `maxHeight` fills the `LazyVGrid` row instead, which is
        // what keeps a one-line description card level with a two-line one beside it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appSelectableCard(
            isSelected: isSelected,
            cornerRadius: 18,
            focus: cardFocus,
            focusID: cardFocusID,
            action: onOpen
        )
        // `.contain` rather than `PullRequestRow`'s `.ignore`: this card holds its own
        // controls, and collapsing it into one element would hide them from VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(skill.name)
    }

    /// Install stays a visible one-click affordance while Uninstall hides in the menu:
    /// installing is the point of a browsed catalog, uninstalling is a rare correction.
    @ViewBuilder
    private var trailingControls: some View {
        if skill.isInstalled {
            AppOverflowMenu(name: "Skill actions") {
                AppOverflowMenuRow(
                    title: "Uninstall",
                    systemImage: "trash",
                    role: .destructive,
                    action: onPrimaryAction
                )
            }
        } else {
            Button(action: onPrimaryAction) {
                // `.inline` leaves the glyph font to the caller, so this matches the MCP
                // recommended card's add button — same glyph, same size, same meaning.
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .iconActionButtonStyle(.inline)
            .fixedSize()
            .help("Install")
            .accessibilityLabel("Install \(skill.name)")
        }
    }
}

/// Source, origin, and reach on one line. Collapsed from three stacked rows because the
/// card's height was the whole complaint, and `lineLimit(1)` keeps a long `owner/repo`
/// from reflowing the card at the narrow one-column width.
private struct SkillCardMetaLine: View {
    let skill: Skill

    var body: some View {
        HStack(spacing: 6) {
            // Fixed so a long owner or sync list truncates instead of squeezing the
            // capsule, whose background makes compression read as a rendering fault.
            Text(sourceLabel)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.14)))
                .fixedSize()

            // No "Local" fallback here: the capsule beside it already says so, and the
            // two together printed the word twice.
            if let origin {
                Text(origin)
            }

            if let reach {
                Text("·")
                    .accessibilityHidden(true)
                Text(reach)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var sourceLabel: String {
        skill.source == .skillsSh ? "skills.sh" : skill.source.rawValue.capitalized
    }

    private var origin: String? {
        guard let owner = skill.owner else {
            return nil
        }
        guard let repo = skill.repo else {
            return owner
        }
        return "\(owner)/\(repo)"
    }

    private var reach: String? {
        if skill.isInstalled, !skill.syncedAgentIDs.isEmpty {
            return "Synced: \(skill.syncedAgentIDs.joined(separator: ", "))"
        }
        if let installs = skill.installs {
            return "\(installs.formatted()) installs"
        }
        return nil
    }
}
