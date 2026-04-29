import SwiftUI

enum TerminalToolbarDisplayState: Equatable {
    case idle
    case running
    case completed(TerminalSession.CompletionOutcome)
}

enum TerminalToolbarCompletionOutcome {
    @MainActor
    static func outcome(
        completedSessionIDs: Set<UUID>,
        terminalManager: TerminalManager
    ) -> TerminalSession.CompletionOutcome? {
        // Keep failure visible while any failed tab remains open.
        let failedSessionIDs = Set(terminalManager.sessions.filter { $0.status == .failed }.map(\.id))
        return terminalManager.completionOutcome(for: completedSessionIDs.union(failedSessionIDs))
    }
}

struct TerminalToolbarButton: View {
    let title: String
    let displayState: TerminalToolbarDisplayState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "terminal")
                    .opacity(displayState == .idle ? 1 : 0)
                    .frame(
                        width: PrimaryToolbarMetrics.iconButtonSize,
                        height: PrimaryToolbarMetrics.iconButtonSize
                    )
            }
                .overlay {
                    TerminalToolbarStatusOverlay(displayState: displayState)
                }
                .labelStyle(.iconOnly)
                .animation(Self.iconAnimation, value: displayState)
        }
    }

    private static let iconAnimation = PrimaryToolbarMetrics.statusAnimation
}

private struct TerminalToolbarStatusOverlay: View {
    let displayState: TerminalToolbarDisplayState

    var body: some View {
        ZStack {
            if isRunning {
                PrimaryToolbarProgressSlot()
            }

            if let completedOutcome {
                Image(systemName: systemImage(for: completedOutcome))
                    .foregroundStyle(color(for: completedOutcome))
                    .transition(.symbolEffect(.drawOn))
            }
        }
        .frame(
            width: PrimaryToolbarMetrics.iconButtonSize,
            height: PrimaryToolbarMetrics.iconButtonSize
        )
    }

    private var isRunning: Bool {
        displayState == .running
    }

    private var completedOutcome: TerminalSession.CompletionOutcome? {
        if case .completed(let outcome) = displayState {
            return outcome
        }
        return nil
    }

    private func systemImage(for outcome: TerminalSession.CompletionOutcome) -> String {
        switch outcome {
        case .succeeded:
            return "checkmark"
        case .failed:
            return "xmark"
        case .cancelled:
            return "slash.circle"
        }
    }

    private func color(for outcome: TerminalSession.CompletionOutcome) -> Color {
        switch outcome {
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }
}
