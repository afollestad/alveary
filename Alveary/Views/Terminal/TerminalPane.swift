import SwiftUI
import SwiftData

struct TerminalPane: View {
    @Binding private var height: CGFloat
    let onHeightCommit: (CGFloat) -> Void
    let visibleThreadID: PersistentIdentifier?
    let canViewThread: (PersistentIdentifier) -> Bool
    let onViewThread: (PersistentIdentifier) -> Void
    let onClose: () -> Void

    @Environment(TerminalManager.self) private var terminalManager
    @Environment(\.colorScheme) private var colorScheme

    private let cornerRadius: CGFloat = 18
    private let maxVisibleSessionChips = 3

    init(
        height: Binding<CGFloat> = .constant(CGFloat(AppSettings.defaultTerminalPaneHeight)),
        onHeightCommit: @escaping (CGFloat) -> Void = { _ in },
        visibleThreadID: PersistentIdentifier? = nil,
        canViewThread: @escaping (PersistentIdentifier) -> Bool = { _ in false },
        onViewThread: @escaping (PersistentIdentifier) -> Void = { _ in },
        onClose: @escaping () -> Void
    ) {
        _height = height
        self.onHeightCommit = onHeightCommit
        self.visibleThreadID = visibleThreadID
        self.canViewThread = canViewThread
        self.onViewThread = onViewThread
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalPaneResizeHandle(
                height: $height,
                bounds: AppSettings.supportedTerminalPaneHeightRange,
                onCommit: onHeightCommit
            )

            VStack(alignment: .leading, spacing: terminalManager.sessions.isEmpty ? 0 : 12) {
                HStack(alignment: .center, spacing: 12) {
                    Label("Terminal", systemImage: "terminal")
                        .font(.headline)

                    Spacer()

                    ModalCloseButton("Hide terminal", action: onClose)
                }

                if !terminalManager.sessions.isEmpty {
                    HStack(spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(visibleSessions) { session in
                                    TerminalSessionChip(
                                        session: session,
                                        isSelected: session.id == terminalManager.selectedSession?.id,
                                        action: {
                                            handleSessionActivation(session)
                                        },
                                        onClose: {
                                            terminalManager.closeSession(id: session.id)
                                        }
                                    )
                                }
                            }
                        }

                        if !overflowSessions.isEmpty {
                            Menu {
                                ForEach(overflowSessions) { session in
                                    Button {
                                        terminalManager.selectSession(id: session.id)
                                    } label: {
                                        TerminalSessionMenuRow(session: session)
                                    }
                                }
                            } label: {
                                Label("More sessions", systemImage: "ellipsis.circle")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .accessibilityLabel("More terminal sessions")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .background(headerBackground)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let selectedSession {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(selectedSession.title)
                                    .font(.headline)

                                if let command = selectedSession.command, !command.isEmpty {
                                    Text(command)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

                                TerminalSessionContextRow(
                                    projectName: selectedSession.projectName,
                                    currentDirectory: selectedSession.currentDirectory
                                )
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 10) {
                                TerminalSessionStatusBadge(status: selectedSession.status)
                            }
                        }

                        if selectedSession.output.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(emptyOutputTitle(for: selectedSession))
                                    .font(.system(.body, design: .monospaced))

                                Text(emptyOutputDescription(for: selectedSession))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text(selectedSession.output)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Terminal sessions will appear here.")
                                .font(.system(.body, design: .monospaced))

                            Text(placeholderDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .background(bodyBackground)
        }
        .frame(maxWidth: .infinity)
        .frame(height: clampedHeight)
        .background(panelBackground)
        .clipShape(panelShape)
        .overlay(
            panelShape
                .strokeBorder(Color.black.opacity(borderOpacity), lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .accessibilityElement(children: .contain)
    }
}

private extension TerminalPane {
    var clampedHeight: CGFloat {
        min(
            max(height, CGFloat(AppSettings.supportedTerminalPaneHeightRange.lowerBound)),
            CGFloat(AppSettings.supportedTerminalPaneHeightRange.upperBound)
        )
    }

    var selectedSession: TerminalSession? {
        terminalManager.selectedSession
    }

    var visibleSessions: [TerminalSession] {
        var sessions = Array(terminalManager.sessions.prefix(maxVisibleSessionChips))

        guard let selectedSession,
              !sessions.contains(where: { $0.id == selectedSession.id }) else {
            return sessions
        }

        if sessions.count == maxVisibleSessionChips {
            sessions[sessions.count - 1] = selectedSession
        } else {
            sessions.append(selectedSession)
        }

        return sessions
    }

    var overflowSessions: [TerminalSession] {
        let visibleIDs = Set(visibleSessions.map(\.id))
        return terminalManager.sessions.filter { !visibleIDs.contains($0.id) }
    }

    func handleSessionActivation(_ session: TerminalSession) {
        if terminalManager.selectedSession?.id == session.id,
           let threadID = session.threadID,
           canViewThread(threadID) {
            onViewThread(threadID)
            return
        }

        terminalManager.selectSession(id: session.id)
    }

    var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var panelBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(red: 0.91, green: 0.91, blue: 0.92)
    }

    var headerBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(red: 0.86, green: 0.86, blue: 0.87)
    }

    var bodyBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: .textBackgroundColor)
            : Color(red: 0.97, green: 0.97, blue: 0.975)
    }

    var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12)
    }

    var shadowRadius: CGFloat {
        colorScheme == .dark ? 22 : 18
    }

    var shadowYOffset: CGFloat {
        colorScheme == .dark ? 10 : 6
    }

    var borderOpacity: Double {
        colorScheme == .dark ? 0.55 : 0.2
    }

    var placeholderDescription: String {
        "Project actions can open their own terminal sessions here, and you can switch between concurrent runs with the session chips above."
    }

    func emptyOutputTitle(for session: TerminalSession) -> String {
        switch session.status {
        case .running:
            return "Waiting for output..."
        case .succeeded:
            return "Command finished without captured output."
        case .failed:
            return "Command failed without captured output."
        case .cancelled:
            return "Command was cancelled before output was captured."
        }
    }

    func emptyOutputDescription(for session: TerminalSession) -> String {
        if let currentDirectory = session.currentDirectory, !currentDirectory.isEmpty {
            return "This session is scoped to \(currentDirectory). Captured output will appear here as the command finishes or reports errors."
        }

        return "Captured output will appear here as the command finishes or reports errors."
    }
}
