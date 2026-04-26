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
            // Keep ProgressView outside the icon slot; AppKit gives direct
            // control-based icon content its own toolbar chrome.
            Label {
                Text(title)
            } icon: {
                Image(systemName: "terminal")
                    .opacity(displayState == .idle ? 1 : 0)
            }
                .overlay {
                    TerminalToolbarStatusOverlay(displayState: displayState)
                }
                .animation(Self.iconAnimation, value: displayState)
        }
    }

    private static let iconAnimation = Animation.easeInOut(duration: 0.18)
}

private struct TerminalToolbarStatusOverlay: View {
    let displayState: TerminalToolbarDisplayState

    var body: some View {
        ZStack {
            if isRunning {
                TerminalToolbarProgressView()
            }

            if let completedOutcome {
                Image(systemName: systemImage(for: completedOutcome))
                    .foregroundStyle(color(for: completedOutcome))
                    .transition(.symbolEffect(.drawOn))
            }
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
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

    private static let iconSize: CGFloat = 16
}

private struct TerminalToolbarProgressView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .tint(.blue)
            .scaleEffect(0.95)
    }
}
