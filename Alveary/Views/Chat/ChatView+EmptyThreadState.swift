import SwiftUI

struct EmptyThreadState: View {
    let setupPhase: SetupPhase?
    let isCancellingInitialSetup: Bool

    var body: some View {
        Group {
            if isCancellingInitialSetup {
                VStack(spacing: 18) {
                    ProgressView()
                        .controlSize(.large)

                    Text("Cancelling setup")
                        .font(.title3.weight(.semibold))

                    Text("Cleaning up the partial worktree and rollback branch.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let setupPhase {
                VStack(spacing: 18) {
                    ProgressView()
                        .controlSize(.large)

                    Text(title(for: setupPhase))
                        .font(.title3.weight(.semibold))

                    Text(message(for: setupPhase))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    icon: "sparkles",
                    heading: "Let’s build",
                    subtext: "Ask your agent to explore the project, make changes, or explain what it finds. " +
                        "Your first message will start the session.",
                    actions: []
                )
            }
        }
    }
}

private extension EmptyThreadState {
    func title(for phase: SetupPhase) -> String {
        switch phase {
        case .creatingWorktree:
            return "Creating worktree"
        case .startingAgent:
            return "Starting agent"
        }
    }

    func message(for phase: SetupPhase) -> String {
        switch phase {
        case .creatingWorktree:
            return "Preparing an isolated working directory for this thread."
        case .startingAgent:
            return "Launching the conversation runtime and preparing the first turn."
        }
    }
}
