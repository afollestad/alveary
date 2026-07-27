import SwiftUI

/// One agent's relationship to the shared instructions file, with opt-in
/// migration actions for agents that still have their own file.
struct AgentInstructionsLinkRow: View {
    let agent: AgentDefinition
    let state: AgentInstructionsLinkState
    let onCopyIntoShared: () -> Void
    let onLink: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(agent.name)

            Text(stateDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 16)

            actions
        }
    }
}

private extension AgentInstructionsLinkRow {
    var stateDescription: String {
        switch state {
        case .linked:
            return "Uses the shared file"
        case .linkedElsewhere(let target):
            return "Linked to \(target)"
        case .hasOwnFile:
            return "Has its own instructions"
        case .absent:
            return "Not linked"
        }
    }

    @ViewBuilder
    var actions: some View {
        switch state {
        case .linked, .linkedElsewhere:
            EmptyView()
        case .hasOwnFile:
            Button("Copy into shared…", action: onCopyIntoShared)
                .secondaryActionButtonStyle()
            Button("Link…", action: onLink)
                .secondaryActionButtonStyle()
        case .absent:
            Button("Link", action: onLink)
                .secondaryActionButtonStyle()
        }
    }
}
