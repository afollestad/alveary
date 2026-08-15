import AgentCLIKit
import Foundation
import SwiftData

extension ThreadHostToolService {
    /// Creates a sidebar section. Idempotent by name and trivially undone by the user from the
    /// sidebar, so there is no confirmation step and no receipt ledger — the section's existence
    /// is its own record, exactly as the pin state is for `pin_thread`.
    func createSection(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> AgentCLIKit.AgentHostToolResult {
        try flushPendingChanges()
        _ = try resolveSource(context: context)
        let name = try parseCreateSection(arguments: arguments)

        switch try sectionService.createSection(name: name) {
        case .created(let descriptor):
            return sectionResult(
                status: "created",
                section: descriptor.name,
                message: "Added the sidebar section \"\(descriptor.name)\" below the existing ones."
            )
        case .alreadyExists(let descriptor):
            return sectionResult(
                status: "already_exists",
                section: descriptor.name,
                message: "The sidebar already has a section named \"\(descriptor.name)\". Nothing changed."
            )
        }
    }

    /// Moves a task thread between sidebar sections. Like pinning, this changes only where the
    /// thread appears, so it applies immediately and keeps no receipt.
    func moveThreadToSection(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> AgentCLIKit.AgentHostToolResult {
        try flushPendingChanges()
        _ = try resolveSource(context: context)
        let request = try parseMoveThreadToSection(arguments: arguments)

        guard let conversation = modelContext.resolveConversation(conversationID: request.threadID),
              let thread = conversation.thread,
              !thread.isDraft,
              thread.archivedAt == nil else {
            throw ThreadHostToolServiceError.threadNotFound
        }
        let (target, sectionName) = try moveTarget(named: request.sectionName)
        let name = thread.displayName()

        let outcome = try sectionService.moveThread(threadID: thread.persistentModelID, to: target)
        guard outcome == .moved else {
            return sectionMoveResult(
                status: "already_in_section",
                threadID: request.threadID,
                name: name,
                section: sectionName,
                message: "The thread \"\(name)\" was already in \(sectionName). Nothing changed."
            )
        }
        return sectionMoveResult(
            status: "moved",
            threadID: request.threadID,
            name: name,
            section: sectionName,
            message: "Moved the thread \"\(name)\" to \(sectionName). Only its sidebar placement changed."
        )
    }
}

extension ThreadHostToolService {
    /// The section a request named, resolved case-insensitively against the live rows. An unknown
    /// name is refused with the real ones — minus `Pinned` and `Projects`, which no thread tool
    /// may name — so the model can act on the rejection. `create_thread` and
    /// `move_thread_to_section` share this so their refusals cannot drift apart.
    func sectionMatch(named sectionName: String) throws -> SidebarSectionDescriptor {
        let sections = try sectionService.orderedSections()
        guard let match = sections.first(where: {
            $0.name.caseInsensitiveCompare(sectionName) == .orderedSame
        }) else {
            throw ThreadHostToolServiceError.sectionUnknown(
                name: sectionName,
                existing: sections.filter { $0.id != .pinned && $0.id != .projects }.map(\.name)
            )
        }
        return match
    }
}

private extension ThreadHostToolService {
    /// Resolves a section name to a move target plus the section's own spelling for the report.
    /// `Tasks` is how a thread leaves a custom section; `Pinned` and `Projects` are refused by
    /// name, because `pin_thread` and a Project placement are the tools that put a thread in
    /// either.
    func moveTarget(named sectionName: String) throws -> (SidebarSectionService.MoveTarget, String) {
        let match = try sectionMatch(named: sectionName)
        switch match.id {
        case .tasks:
            return (.tasks, match.name)
        case .custom(let sectionID):
            return (.custom(sectionID: sectionID), match.name)
        case .pinned, .projects:
            throw ThreadHostToolServiceError.sectionNotCustom(name: match.name)
        }
    }

    func sectionResult(status: String, section: String, message: String) -> AgentCLIKit.AgentHostToolResult {
        AgentCLIKit.AgentHostToolResult(
            text: message,
            structuredContent: .object([
                "status": .string(status),
                "section": .string(section),
                "message": .string(message)
            ])
        )
    }

    func sectionMoveResult(
        status: String,
        threadID: String,
        name: String,
        section: String,
        message: String
    ) -> AgentCLIKit.AgentHostToolResult {
        AgentCLIKit.AgentHostToolResult(
            text: message,
            structuredContent: .object([
                "status": .string(status),
                "thread_id": .string(threadID),
                "name": .string(name),
                "section": .string(section),
                "message": .string(message)
            ])
        )
    }
}
