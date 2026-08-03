import AgentCLIKit
import Foundation

/// A `link_pr` or `unlink_pr` call, as recorded durably in the transcript.
///
/// Both tools apply immediately, so the tool result *is* the outcome: these widgets carry no
/// `host_tool_outcome` marker and never wait on a user decision.
struct PullRequestLinkWidgetContent: Equatable {
    enum Action: Equatable {
        case link
        case unlink
    }

    enum Status: Equatable {
        /// The call has not returned yet.
        case running
        /// The link was added or removed.
        case applied
        /// The thread was already in the requested state, so nothing changed.
        case unchanged
        /// The host tool refused the request outright.
        case failed
    }

    let action: Action
    /// The pull request the call named, or the one its result echoed. Nil when an omitted
    /// `unlink_pr` URL resolved against a thread carrying no links.
    let identifier: PullRequestIdentifier?
    /// The stored snapshot's title, when the result carried one.
    let title: String?
    let message: String?
    let status: Status

    /// The call landed and its change — or its deliberate lack of one — is in effect, so the
    /// pull request it names can be opened.
    var isSettled: Bool {
        status == .applied || status == .unchanged
    }
}

/// Pure parsing for the pull-request link tools' persisted input/output JSON.
enum PullRequestLinkWidgetParsing {
    static func content(
        action: PullRequestLinkWidgetContent.Action,
        input: String?,
        output: String?,
        isError: Bool
    ) -> PullRequestLinkWidgetContent? {
        guard let arguments = HostToolWidgetJSON.object(from: input) else {
            return nil
        }
        let receipt = HostToolWidgetJSON.object(from: output).map(Receipt.init(object:))
        let message = receipt?.message ?? HostToolWidgetJSON.plainText(from: output)
        return PullRequestLinkWidgetContent(
            action: action,
            // The result echoes Alveary's stored snapshot, which is canonical. The request's own
            // `url` is the only source while the call is still running, and it is optional on
            // `unlink_pr`; the message is the last resort for a provider that emits only the
            // text fallback, where an omitted URL would otherwise leave the card unable to name
            // the pull request it just unlinked. A structured receipt never takes that fallback:
            // its absent `pull_request` means there is genuinely nothing to name, and parsing its
            // message could only invent one (a thread name like "Fix x/y#1" quoted in the copy).
            identifier: receipt?.identifier
                ?? requestedIdentifier(in: arguments)
                ?? (receipt == nil ? identifier(inMessage: message) : nil),
            title: receipt?.title,
            message: message,
            status: status(receipt: receipt, output: output, isError: isError)
        )
    }
}

private extension PullRequestLinkWidgetParsing {
    /// The `status` values `ThreadHostToolService` reports for a landed call.
    enum ReceiptStatus {
        static let alreadyLinked = "already_linked"
        static let notLinked = "not_linked"
    }

    struct Receipt {
        let status: String?
        let identifier: PullRequestIdentifier?
        let title: String?
        let message: String?

        init(object: [String: AgentCLIKit.JSONValue]) {
            status = HostToolWidgetJSON.string(object["status"])
            message = HostToolWidgetJSON.string(object["message"])
            // `pull_request` is optional in the output schema: an `unlink_pr` that found
            // nothing to remove has no snapshot to echo.
            guard case let .object(pullRequest)? = object["pull_request"] else {
                identifier = nil
                title = nil
                return
            }
            title = HostToolWidgetJSON.string(pullRequest["title"])
            identifier = HostToolWidgetJSON.string(pullRequest["repository"]).flatMap { repository in
                HostToolWidgetJSON.integer(pullRequest["number"]).flatMap {
                    PullRequestIdentifier(nameWithOwner: repository, number: $0)
                }
            }
        }
    }

    static func requestedIdentifier(in arguments: [String: AgentCLIKit.JSONValue]) -> PullRequestIdentifier? {
        HostToolWidgetJSON.string(arguments["url"]).flatMap(PullRequestURLParser.identifier(from:))
    }

    /// Every landed result names the pull request it acted on in `owner/repo#number` form, so
    /// the message still identifies it when no structured snapshot arrived. The parser takes
    /// the whole token, hence the trailing sentence punctuation has to come off first.
    static func identifier(inMessage message: String?) -> PullRequestIdentifier? {
        guard let message else {
            return nil
        }
        return message
            .split(whereSeparator: \.isWhitespace)
            .lazy
            .compactMap { token in
                PullRequestURLParser.identifier(
                    from: token.trimmingCharacters(in: messagePunctuation)
                )
            }
            .first
    }

    static let messagePunctuation = CharacterSet(charactersIn: ".,;:!?\"'()[]“”‘’")

    static func status(
        receipt: Receipt?,
        output: String?,
        isError: Bool
    ) -> PullRequestLinkWidgetContent.Status {
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .running
        }
        guard !isError else {
            return .failed
        }
        switch receipt?.status {
        case ReceiptStatus.alreadyLinked, ReceiptStatus.notLinked:
            return .unchanged
        default:
            // A provider that emits only the text fallback still reports refusal through
            // `isError`, so every other landed result took effect.
            return .applied
        }
    }
}
