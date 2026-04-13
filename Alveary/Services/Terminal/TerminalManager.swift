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

    enum Status: String, Sendable {
        case running
        case succeeded
        case failed
        case cancelled
    }
}

@MainActor
@Observable
final class TerminalManager {
    private(set) var sessions: [TerminalSession] = []
    var selectedSessionID: UUID?

    private let maxRetainedOutputCharacters = 120_000

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

    func markSessionFinished(id: UUID, exitCode: Int32) {
        updateSession(id: id) { session in
            session.status = exitCode == 0 ? .succeeded : .failed
            session.endedAt = Date()
        }
    }

    func cancelSession(id: UUID) {
        updateSession(id: id) { session in
            session.status = .cancelled
            session.endedAt = Date()
        }
    }

    func closeSession(id: UUID) {
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
