import Foundation
import Observation
import SwiftData

struct TerminalSession: Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: Kind
    var title: String
    var threadID: PersistentIdentifier?
    var threadName: String?
    var currentDirectory: String?
    var status: Status
    let startedAt: Date
    var endedAt: Date?

    init(
        id: UUID = UUID(),
        kind: Kind = .projectAction,
        title: String,
        threadID: PersistentIdentifier? = nil,
        threadName: String? = nil,
        currentDirectory: String? = nil,
        status: Status = .running,
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.threadID = threadID
        self.threadName = threadName
        self.currentDirectory = currentDirectory
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    var isRunning: Bool {
        status == .running
    }

    var chipLabel: String {
        guard let threadName = normalizedThreadName else {
            return chipTitle
        }

        return "\(chipTitle) - \(Self.truncatePreservingInlineCode(threadName, toVisibleLength: Self.maxChipThreadNameLength))"
    }

    /// Truncates `markdown` so the visible (non-delimiter) grapheme-cluster count stays
    /// within `limit`. Iterates by `Character` so emoji and other multi-UTF-16 graphemes
    /// count as one and the cut never lands inside a surrogate pair. Backticks that
    /// delimit inline code don't count toward the visible budget, so labels like
    /// `"Test `code` Rendering"` aren't trimmed earlier than their plain equivalent. If
    /// the cut lands inside an inline code span, a closing delimiter of the same backtick
    /// length as the opening (so multi-backtick spans stay balanced too) is appended so
    /// the surviving markdown still renders a chip.
    static func truncatePreservingInlineCode(_ markdown: String, toVisibleLength limit: Int) -> String {
        let ranges = AppMarkdownCodeBlockParser.codeRanges(in: markdown)
        let delimiterUTF16Indices = Set(ranges.inlineDelimiterRanges.flatMap { Array($0.location..<NSMaxRange($0)) })

        var visibleCount = 0
        var cutIndex = markdown.endIndex
        var cutUTF16Offset = (markdown as NSString).length
        var utf16Offset = 0
        for index in markdown.indices {
            let character = markdown[index]
            if !delimiterUTF16Indices.contains(utf16Offset) {
                if visibleCount == limit {
                    cutIndex = index
                    cutUTF16Offset = utf16Offset
                    break
                }
                visibleCount += 1
            }
            utf16Offset += character.utf16.count
        }

        if cutIndex == markdown.endIndex {
            return markdown
        }

        // Pull the cut back past any dangling opening-delimiter backticks so the prefix
        // doesn't end with an unmatched `` ` `` that can't form a chip.
        while cutIndex > markdown.startIndex {
            let previous = markdown.index(before: cutIndex)
            let previousOffset = cutUTF16Offset - markdown[previous].utf16.count
            guard delimiterUTF16Indices.contains(previousOffset) else {
                break
            }
            cutIndex = previous
            cutUTF16Offset = previousOffset
        }

        var closingDelimiter = ""
        if let containingRange = ranges.inlineFullRanges.first(where: { range in
            cutUTF16Offset > range.location && cutUTF16Offset < NSMaxRange(range)
        }) {
            let delimiterLength = ranges.inlineDelimiterRanges
                .first { $0.location == containingRange.location }?.length ?? 1
            closingDelimiter = String(repeating: "`", count: delimiterLength)
        }

        return String(markdown[..<cutIndex]) + closingDelimiter + "…"
    }

    enum Kind: String, Sendable {
        case shell
        case projectAction
    }

    enum Status: String, Sendable {
        case running
        case succeeded
        case failed
        case cancelled
    }

    enum CompletionOutcome: Sendable, Equatable {
        case succeeded
        case failed
        case cancelled
    }

    private var normalizedThreadName: String? {
        guard let trimmedThreadName = threadName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedThreadName.isEmpty else {
            return nil
        }

        return trimmedThreadName
    }

    private var chipTitle: String {
        kind == .shell ? "Shell" : title
    }

    private static let maxChipThreadNameLength = 20
}

@MainActor
@Observable
final class TerminalManager {
    private(set) var sessions: [TerminalSession] = []
    var selectedSessionID: UUID?

    @ObservationIgnored private var controllers: [UUID: any TerminalSessionControlling] = [:]
    @ObservationIgnored private var terminatedControllerSessionIDs: Set<UUID> = []
    private let controllerFactory: any TerminalSessionControllerFactory

    init(controllerFactory: any TerminalSessionControllerFactory = SwiftTermTerminalControllerFactory()) {
        self.controllerFactory = controllerFactory
    }

    deinit {
        MainActor.assumeIsolated {
            terminateAllSessions()
        }
    }

    var selectedSession: TerminalSession? {
        guard !sessions.isEmpty else {
            return nil
        }

        guard let selectedSessionID else {
            return sessions.last
        }

        return sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.last
    }

    var runningProjectActionSessionIDs: Set<UUID> {
        Set(sessions.filter { $0.kind == .projectAction && $0.isRunning }.map(\.id))
    }

    func controller(for sessionID: UUID) -> (any TerminalSessionControlling)? {
        controllers[sessionID]
    }

    func completionOutcome(for sessionIDs: Set<UUID>) -> TerminalSession.CompletionOutcome? {
        guard !sessionIDs.isEmpty else {
            return nil
        }

        var statuses: [TerminalSession.Status] = []
        for sessionID in sessionIDs {
            guard let session = sessions.first(where: { $0.id == sessionID }),
                  !session.isRunning else {
                return nil
            }
            statuses.append(session.status)
        }

        if statuses.contains(.failed) {
            return .failed
        }
        if statuses.contains(.cancelled) {
            return .cancelled
        }
        return .succeeded
    }

    func ensureSelection() {
        if let selectedSessionID,
           sessions.contains(where: { $0.id == selectedSessionID }) {
            return
        }

        selectedSessionID = sessions.last?.id
    }

    @discardableResult
    func createSession(
        kind: TerminalSession.Kind = .projectAction,
        title: String,
        threadID: PersistentIdentifier? = nil,
        threadName: String? = nil,
        currentDirectory: String? = nil,
        status: TerminalSession.Status = .running,
        startedAt: Date = Date(),
        select: Bool = true,
        focus: Bool = false,
        maxSessions: Int = AppSettings.defaultMaxTerminalSessions,
        launchConfiguration: TerminalLaunchConfiguration? = nil
    ) -> UUID {
        let session = TerminalSession(
            kind: kind,
            title: title,
            threadID: threadID,
            threadName: threadName,
            currentDirectory: currentDirectory,
            status: status,
            startedAt: startedAt,
            endedAt: status == .running ? nil : Date()
        )
        sessions.append(session)

        if let launchConfiguration {
            terminatedControllerSessionIDs.remove(session.id)
            let controller = controllerFactory.makeController(
                sessionID: session.id,
                configuration: launchConfiguration,
                delegate: self
            )
            controllers[session.id] = controller
            controller.start()
            if focus {
                controller.requestFocus()
            }
        }

        if select || selectedSessionID == nil {
            selectedSessionID = session.id
        }

        pruneSessions(to: maxSessions)
        return session.id
    }

    func selectSession(id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else {
            return
        }

        selectedSessionID = id
    }

    func requestFocus(id: UUID) {
        controllers[id]?.requestFocus()
    }

    func markSessionFinished(id: UUID, exitCode: Int32?) {
        updateRunningSession(id: id) { session in
            session.status = exitCode == 0 ? .succeeded : .failed
            session.endedAt = Date()
        }
    }

    func cancelSession(id: UUID) {
        updateRunningSession(id: id) { session in
            session.status = .cancelled
            session.endedAt = Date()
        }
        terminatedControllerSessionIDs.insert(id)
        controllers[id]?.terminate()
    }

    func closeSession(id: UUID) {
        if let index = sessions.firstIndex(where: { $0.id == id }),
           sessions[index].isRunning {
            sessions[index].status = .cancelled
            sessions[index].endedAt = Date()
        }
        controllers[id]?.terminate()
        controllers[id] = nil
        terminatedControllerSessionIDs.remove(id)

        // Close-adjacent: if the closing session was selected, pick the next (same index
        // after shift) session, falling back to the previous when the last tab is
        // closed. Mirrors `ThreadDetailView.selectNeighborIfClosingSelected`'s
        // "next, else previous" behavior so terminal-tab close UX matches the
        // conversation-tab UX.
        let closingIndex = sessions.firstIndex(where: { $0.id == id })
        let wasSelected = selectedSessionID == id
        sessions.removeAll { $0.id == id }

        guard wasSelected else {
            ensureSelection()
            return
        }

        if let closingIndex, closingIndex < sessions.count {
            selectedSessionID = sessions[closingIndex].id
        } else {
            selectedSessionID = sessions.last?.id
        }
    }

    func terminateAllSessions() {
        for controller in controllers.values {
            controller.terminate()
        }
        controllers.removeAll()
    }

    private func updateRunningSession(id: UUID, mutation: (inout TerminalSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].isRunning else {
            return
        }

        mutation(&sessions[index])
        ensureSelection()
    }

    private func pruneSessions(to maxSessions: Int) {
        let supportedLimit = max(maxSessions, 1)
        // Prune by launch time, not tab position or current selection.
        while sessions.count > supportedLimit,
              let oldestSessionID = sessions.min(by: { $0.startedAt < $1.startedAt })?.id {
            closeSession(id: oldestSessionID)
        }
    }
}

extension TerminalManager: TerminalSessionControllerDelegate {
    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didTerminateSession id: UUID,
        exitCode: Int32?
    ) {
        guard sessions.contains(where: { $0.id == id }) else {
            return
        }
        terminatedControllerSessionIDs.insert(id)
        markSessionFinished(id: id, exitCode: exitCode)
    }

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didCompleteProjectAction id: UUID,
        exitCode: Int32
    ) {
        guard sessions.first(where: { $0.id == id })?.kind == .projectAction else {
            return
        }
        markSessionFinished(id: id, exitCode: exitCode)
    }

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didUpdateTitle title: String,
        forSession id: UUID
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              !terminatedControllerSessionIDs.contains(id),
              sessions[index].kind == .shell else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        sessions[index].title = trimmedTitle
    }

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didUpdateCurrentDirectory currentDirectory: String,
        forSession id: UUID
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              !terminatedControllerSessionIDs.contains(id),
              !currentDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        sessions[index].currentDirectory = currentDirectory
    }
}
