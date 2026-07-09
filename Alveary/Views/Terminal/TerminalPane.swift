import SwiftUI
import SwiftData

struct TerminalPane: View {
    @Binding private var height: CGFloat
    let onHeightCommit: (CGFloat) -> Void
    let visibleThreadID: PersistentIdentifier?
    let canViewThread: (PersistentIdentifier) -> Bool
    let onViewThread: (PersistentIdentifier) -> Void
    let onNewShell: () -> Void
    let onClose: () -> Void

    @Environment(TerminalManager.self) private var terminalManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var tabsScrollGeometry = TerminalTabsScrollGeometry()

    private let cornerRadius: CGFloat = 18

    init(
        height: Binding<CGFloat> = .constant(CGFloat(AppSettings.defaultTerminalPaneHeight)),
        onHeightCommit: @escaping (CGFloat) -> Void = { _ in },
        visibleThreadID: PersistentIdentifier? = nil,
        canViewThread: @escaping (PersistentIdentifier) -> Bool = { _ in false },
        onViewThread: @escaping (PersistentIdentifier) -> Void = { _ in },
        onNewShell: @escaping () -> Void = {},
        onClose: @escaping () -> Void
    ) {
        _height = height
        self.onHeightCommit = onHeightCommit
        self.visibleThreadID = visibleThreadID
        self.canViewThread = canViewThread
        self.onViewThread = onViewThread
        self.onNewShell = onNewShell
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalPaneResizeHandle(
                height: $height,
                bounds: AppSettings.supportedTerminalPaneHeightRange,
                onCommit: onHeightCommit
            )

            HStack(alignment: .center, spacing: 0) {
                Image(systemName: "terminal")
                    .font(.headline)
                    .accessibilityLabel("Terminal")

                if !terminalManager.sessions.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(terminalManager.sessions) { session in
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
                                    .id(session.id)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .onScrollGeometryChange(for: TerminalTabsScrollGeometry.self) { geometry in
                            TerminalTabsScrollGeometry(
                                contentWidth: geometry.contentSize.width,
                                containerWidth: geometry.containerSize.width,
                                contentOffset: geometry.contentOffset.x
                            )
                        } action: { _, newValue in
                            tabsScrollGeometry = newValue
                        }
                        .overlay(alignment: .leading) {
                            if hasTabsBehindLeadingEdge {
                                Rectangle()
                                    .fill(tabsDividerColor)
                                    .frame(width: 1, height: 18)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if hasTabsBehindTrailingEdge {
                                Rectangle()
                                    .fill(tabsDividerColor)
                                    .frame(width: 1, height: 18)
                            }
                        }
                        // Minimum-scroll-to-visible on selection change. `nil` anchor
                        // means already-visible chips don't jump, while off-screen
                        // chips (e.g. selected session after opening a dense pane)
                        // scroll into view with just enough delta.
                        .onChange(of: terminalManager.selectedSession?.id, initial: true) { _, newID in
                            guard let newID else { return }
                            proxy.scrollTo(newID)
                        }
                        // Programmatically-added sessions (e.g. a tool run spawning a
                        // terminal) append to the end of the list. When the count grows
                        // we scroll to the new trailing session so it surfaces, even
                        // when it didn't become the selected session.
                        .onChange(of: terminalManager.sessions.count) { oldCount, newCount in
                            guard newCount > oldCount,
                                  let lastID = terminalManager.sessions.last?.id else {
                                return
                            }
                            proxy.scrollTo(lastID)
                        }
                    }
                    .padding(.leading, 8)
                } else {
                    Spacer(minLength: 0)
                }

                Button(action: onNewShell) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("New shell")
                .accessibilityLabel("New shell")
                .padding(.leading, 8)

                ModalCloseButton("Hide terminal", action: onClose)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)

            Divider()

            terminalBody
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

    /// Maximum distance the tab row can scroll given current content / container width.
    var tabsMaxScrollableDistance: CGFloat {
        max(0, tabsScrollGeometry.contentWidth - tabsScrollGeometry.containerWidth)
    }

    /// `true` when a tab chip is clipped by, or sitting under, the leading edge of the
    /// scroll area — i.e. the user has scrolled forward from the start. Gates the
    /// left-edge divider so it only appears when there is content to indicate.
    var hasTabsBehindLeadingEdge: Bool {
        tabsScrollGeometry.contentOffset > 0.5
    }

    /// `true` when a tab chip extends beyond the trailing edge of the scroll area,
    /// i.e. there is still more content further to the right. Gates the right-edge
    /// divider so it only appears when there is content to indicate.
    var hasTabsBehindTrailingEdge: Bool {
        tabsMaxScrollableDistance > 0.5
            && tabsScrollGeometry.contentOffset < tabsMaxScrollableDistance - 0.5
    }

    func handleSessionActivation(_ session: TerminalSession) {
        if terminalManager.selectedSession?.id == session.id,
           let threadID = session.threadID,
           canViewThread(threadID) {
            onViewThread(threadID)
            return
        }

        terminalManager.selectSession(id: session.id)
        terminalManager.requestFocus(id: session.id)
    }

    @ViewBuilder
    var terminalBody: some View {
        if let selectedSession {
            VStack(spacing: 0) {
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

                    TerminalSessionStatusBadge(status: selectedSession.status)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                Divider()

                if let controller = terminalManager.controller(for: selectedSession.id) {
                    TerminalSessionHostView(controller: controller)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    unavailableTerminalBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No terminal sessions.")
                    .font(.system(.body, design: .monospaced))

                Text(placeholderDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
        }
    }

    var unavailableTerminalBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terminal view unavailable.")
                .font(.system(.body, design: .monospaced))

            Text("This session has metadata but no mounted PTY view.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
    }

    var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Single background for the pane chrome — drag handle, header, and metadata strip
    /// share this color so the regions can't drift apart in light or dark themes. The
    /// embedded terminal viewport applies its own `TerminalThemePalette`.
    var panelBackground: Color {
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

    /// Tab-scroll divider — intentionally darker than the default `Divider` separator so
    /// it reads as an edge between the fixed terminal icon and the scrolling tabs.
    var tabsDividerColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.35 : 0.3)
    }

    var placeholderDescription: String {
        "Open a shell with the plus button or run a project action to create a terminal tab."
    }
}

/// Snapshot of the tab row's scroll state. Populated by
/// `onScrollGeometryChange(for:of:action:)` so the view can gate the leading / trailing
/// edge dividers on whether there is off-screen content in that direction, instead of
/// cobbling the same signals together from GeometryReader-based preference keys.
private struct TerminalTabsScrollGeometry: Equatable {
    var contentWidth: CGFloat = 0
    var containerWidth: CGFloat = 0
    var contentOffset: CGFloat = 0
}
