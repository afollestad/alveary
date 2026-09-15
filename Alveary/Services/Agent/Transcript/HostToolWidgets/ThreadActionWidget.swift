import AgentCLIKit
import Foundation

/// A thread mutation or review launch, recorded durably in the transcript.
///
/// Every thread mutation applies immediately, so the tool result *is* the outcome: these
/// widgets carry no `host_tool_outcome` marker and never wait on a user decision.
struct ThreadActionWidgetContent: Equatable {
    enum Action: Equatable {
        case create
        case pin
        case unpin
        case archive
        case createSection
        case moveSection
        case sendPrompt
        case startReview
    }

    enum Status: Equatable {
        /// The call has not returned yet.
        case running
        /// The thread was created, pinned, unpinned, archived, moved, or handed the prompt —
        /// a queued prompt included, since queueing is what the call set out to do.
        case applied
        /// The thread was already in the requested state, so nothing changed.
        case unchanged
        /// The requested action failed.
        case failed
    }

    let action: Action
    /// Sole-main-conversation id of the thread the call names — the same handle every thread
    /// tool takes. Nil when a text-fallback launch result never named one.
    let threadID: String?
    let name: String?
    /// Project the created thread works in; nil for a Task thread and for the other actions.
    let projectPath: String?
    let message: String?
    let status: Status
    var linkWarning: String?

    /// The call landed and its change — or its deliberate lack of one — is in effect, so the
    /// thread it names can be opened.
    var isSettled: Bool {
        status == .applied || status == .unchanged
    }

    /// A review launch can fail after creating its task; keep that task reachable for recovery.
    var canOpenThread: Bool {
        isSettled || (action == .startReview && status == .failed)
    }
}

/// Pure parsing for the thread mutation tools' persisted input/output JSON.
enum ThreadActionWidgetParsing {
    static func content(
        action: ThreadActionWidgetContent.Action,
        input: String?,
        output: String?,
        isError: Bool
    ) -> ThreadActionWidgetContent? {
        guard let arguments = HostToolWidgetJSON.object(from: input) else {
            return nil
        }
        let receipt = HostToolWidgetJSON.object(from: output).map(Receipt.init(object:))
        let message = receipt?.message ?? HostToolWidgetJSON.plainText(from: output)
        return ThreadActionWidgetContent(
            action: action,
            // The result echoes the thread Alveary acted on, which is canonical. `pin_thread`,
            // `unpin_thread`, `archive_thread`, and `send_prompt_to_thread` require the id in the
            // request, so their cards can name it while the call is still running. Launch tools
            // cannot, and for a harness that emits only the text fallback its own message is the
            // sole source. A structured receipt never takes that fallback — its fields are the answer.
            threadID: receipt?.threadID
                ?? HostToolWidgetJSON.string(arguments["thread_id"])
                ?? (receipt == nil ? threadID(inMessage: message) : nil),
            name: receipt?.name ?? (receipt == nil ? quotedName(inMessage: message) : nil),
            projectPath: receipt?.projectPath,
            message: message,
            status: status(action: action, receipt: receipt, output: output, isError: isError),
            linkWarning: receipt?.linkWarning ?? (action == .startReview && receipt == nil ? linkWarning(inMessage: message) : nil)
        )
    }
}

private extension ThreadActionWidgetParsing {
    /// The status values host tools report for a call that changed nothing.
    /// `create_thread` has no such status: it either creates a thread or fails.
    static let unchangedStatuses: Set<String> = [
        "already_pinned",
        "already_unpinned",
        "already_archived",
        "already_exists",
        "already_in_section",
        "existing"
    ]

    struct Receipt {
        let status: String?
        let threadID: String?
        let name: String?
        let projectPath: String?
        let message: String?
        let linkWarning: String?

        init(object: [String: AgentCLIKit.JSONValue]) {
            status = HostToolWidgetJSON.string(object["status"])
            threadID = HostToolWidgetJSON.string(object["thread_id"])
            name = HostToolWidgetJSON.string(object["name"])
            // Only a created Project thread reports one; a Task thread works in its own
            // private workspace and names no path.
            projectPath = HostToolWidgetJSON.string(object["project_path"])
            message = HostToolWidgetJSON.string(object["message"])
            linkWarning = HostToolWidgetJSON.string(object["link_warning"])
        }
    }

    /// Every landed result names its thread as `the thread "<name>"`, so a text-fallback card
    /// still has something to render beside the verb.
    static func quotedName(inMessage message: String?) -> String? {
        guard let message, let opening = message.firstIndex(of: "\"") else {
            return nil
        }
        let start = message.index(after: opening)
        guard let closing = message[start...].firstIndex(of: "\"") else {
            return nil
        }
        let name = String(message[start..<closing])
        return name.isEmpty ? nil : name
    }

    /// Launch results render their new id as `(id: <id>)`, since the request cannot name it yet.
    static func threadID(inMessage message: String?) -> String? {
        guard let message, let marker = message.range(of: "(id: ") else {
            return nil
        }
        let remainder = message[marker.upperBound...]
        guard let closing = remainder.firstIndex(of: ")") else {
            return nil
        }
        let identifier = remainder[..<closing].trimmingCharacters(in: .whitespaces)
        return identifier.isEmpty ? nil : identifier
    }

    static func status(
        action: ThreadActionWidgetContent.Action,
        receipt: Receipt?,
        output: String?,
        isError: Bool
    ) -> ThreadActionWidgetContent.Status {
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .running
        }
        guard !isError, receipt?.status != "error" else {
            return .failed
        }
        if action == .startReview, receipt == nil, output.hasPrefix("Review already exists in the thread ") {
            return .unchanged
        }
        guard let status = receipt?.status, unchangedStatuses.contains(status) else {
            // A harness that emits only the text fallback still reports refusal through
            // `isError`, so every other landed result took effect.
            return .applied
        }
        return .unchanged
    }

    /// The launch tool appends this label so text-only harnesses retain a nonfatal link failure.
    static func linkWarning(inMessage message: String?) -> String? {
        guard let message, let marker = message.range(of: "Link warning: ") else { return nil }
        let warning = message[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return warning.isEmpty ? nil : warning
    }
}
