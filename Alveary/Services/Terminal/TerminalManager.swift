import Foundation
import Observation
import SwiftData

struct TerminalSession: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var projectName: String?
    var threadID: PersistentIdentifier?
    var threadName: String?
    var currentDirectory: String?
    var command: String?
    var output: String
    var status: Status
    let startedAt: Date
    var endedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        projectName: String? = nil,
        threadID: PersistentIdentifier? = nil,
        threadName: String? = nil,
        currentDirectory: String? = nil,
        command: String? = nil,
        output: String = "",
        status: Status = .running,
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.projectName = projectName
        self.threadID = threadID
        self.threadName = threadName
        self.currentDirectory = currentDirectory
        self.command = command
        self.output = output
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    var isRunning: Bool {
        status == .running
    }

    var chipLabel: String {
        guard let threadName = normalizedThreadName else {
            return title
        }

        return "\(title) - \(Self.truncatePreservingInlineCode(threadName, toVisibleLength: Self.maxChipThreadNameLength))"
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

    enum Status: String, Sendable {
        case running
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

    private static let maxChipThreadNameLength = 20
}

@MainActor
@Observable
final class TerminalManager {
    private(set) var sessions: [TerminalSession] = []
    var selectedSessionID: UUID?

    private let maxRetainedOutputCharacters = 120_000
    private var sessionTasks: [UUID: Task<Void, Never>] = [:]

    var selectedSession: TerminalSession? {
        guard !sessions.isEmpty else {
            return nil
        }

        guard let selectedSessionID else {
            return sessions.first
        }

        return sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.first
    }

    func ensureSelection() {
        if let selectedSessionID,
           sessions.contains(where: { $0.id == selectedSessionID }) {
            return
        }

        selectedSessionID = sessions.first?.id
    }

    @discardableResult
    func createSession(
        title: String,
        projectName: String? = nil,
        threadID: PersistentIdentifier? = nil,
        threadName: String? = nil,
        currentDirectory: String? = nil,
        command: String? = nil,
        output: String = "",
        status: TerminalSession.Status = .running,
        select: Bool = true
    ) -> UUID {
        let session = TerminalSession(
            title: title,
            projectName: projectName,
            threadID: threadID,
            threadName: threadName,
            currentDirectory: currentDirectory,
            command: command,
            output: trimOutput(output),
            status: status,
            endedAt: status == .running ? nil : Date()
        )
        sessions.insert(session, at: 0)

        if select || selectedSessionID == nil {
            selectedSessionID = session.id
        }

        return session.id
    }

    func selectSession(id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else {
            return
        }

        selectedSessionID = id
    }

    func appendOutput(_ output: String, to id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              !output.isEmpty else {
            return
        }

        sessions[index].output = trimOutput(sessions[index].output + output)
    }

    func registerTask(_ task: Task<Void, Never>, forSessionID id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else {
            task.cancel()
            return
        }

        sessionTasks[id]?.cancel()
        sessionTasks[id] = task
    }

    func markSessionFinished(id: UUID, exitCode: Int32) {
        sessionTasks[id] = nil
        updateSession(id: id) { session in
            session.status = exitCode == 0 ? .succeeded : .failed
            session.endedAt = Date()
        }
    }

    func cancelSession(id: UUID) {
        sessionTasks[id]?.cancel()
        sessionTasks[id] = nil
        updateSession(id: id) { session in
            session.status = .cancelled
            session.endedAt = Date()
        }
    }

    func closeSession(id: UUID) {
        sessionTasks[id]?.cancel()
        sessionTasks[id] = nil
        sessions.removeAll { $0.id == id }
        ensureSelection()
    }

    private func updateSession(id: UUID, mutation: (inout TerminalSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutation(&sessions[index])
        ensureSelection()
    }

    private func trimOutput(_ output: String) -> String {
        guard output.count > maxRetainedOutputCharacters else {
            return output
        }

        return String(output.suffix(maxRetainedOutputCharacters))
    }
}
