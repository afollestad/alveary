import AgentCLIKit
import Foundation

/// A `create_thread`, `pin_thread`, `unpin_thread`, or `archive_thread` call, as recorded
/// durably in the transcript.
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
    }

    enum Status: Equatable {
        /// The call has not returned yet.
        case running
        /// The thread was created, pinned, unpinned, or archived.
        case applied
        /// The thread was already in the requested state, so nothing changed.
        case unchanged
        /// The host tool refused the request outright.
        case failed
    }

    let action: Action
    /// Sole-main-conversation id of the thread the call names — the same handle every thread
    /// tool takes. Nil when a text-fallback `create_thread` result never named one.
    let threadID: String?
    let name: String?
    /// Project the created thread works in; nil for a Task thread and for the other actions.
    let projectPath: String?
    let message: String?
    let status: Status

    /// The call landed and its change — or its deliberate lack of one — is in effect, so the
    /// thread it names can be opened.
    var isSettled: Bool {
        status == .applied || status == .unchanged
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
            // `unpin_thread`, and `archive_thread` require the id in the request, so their cards
            // can name it while the call is still running; `create_thread` cannot, and for a
            // provider that emits only the text fallback its own message is the sole source. A
            // structured receipt never takes that fallback — its fields are the answer.
            threadID: receipt?.threadID
                ?? HostToolWidgetJSON.string(arguments["thread_id"])
                ?? (receipt == nil ? threadID(inMessage: message) : nil),
            name: receipt?.name ?? (receipt == nil ? quotedName(inMessage: message) : nil),
            projectPath: receipt?.projectPath,
            message: message,
            status: status(receipt: receipt, output: output, isError: isError)
        )
    }
}

private extension ThreadActionWidgetParsing {
    /// The `status` values `ThreadHostToolService` reports for a call that changed nothing.
    /// `create_thread` has no such status: it either creates a thread or fails.
    static let unchangedStatuses: Set<String> = [
        "already_pinned",
        "already_unpinned",
        "already_archived",
        "already_exists",
        "already_in_section"
    ]

    struct Receipt {
        let status: String?
        let threadID: String?
        let name: String?
        let projectPath: String?
        let message: String?

        init(object: [String: AgentCLIKit.JSONValue]) {
            status = HostToolWidgetJSON.string(object["status"])
            threadID = HostToolWidgetJSON.string(object["thread_id"])
            name = HostToolWidgetJSON.string(object["name"])
            // Only a created Project thread reports one; a Task thread works in its own
            // private workspace and names no path.
            projectPath = HostToolWidgetJSON.string(object["project_path"])
            message = HostToolWidgetJSON.string(object["message"])
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

    /// `create_thread` is the one action whose request cannot name its thread, and its message
    /// renders the new id as `(id: <id>)` — without this the card could never open it.
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
        receipt: Receipt?,
        output: String?,
        isError: Bool
    ) -> ThreadActionWidgetContent.Status {
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .running
        }
        guard !isError else {
            return .failed
        }
        guard let status = receipt?.status, unchangedStatuses.contains(status) else {
            // A provider that emits only the text fallback still reports refusal through
            // `isError`, so every other landed result took effect.
            return .applied
        }
        return .unchanged
    }
}
