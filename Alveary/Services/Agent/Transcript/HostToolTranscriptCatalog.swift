import AgentCLIKit
import Foundation

/// Describes how one Alveary host MCP tool renders as a transcript widget.
///
/// The catalog is the single extension point: a new `alveary_host` feature gets
/// custom transcript UI by appending a descriptor here, adding a
/// `HostToolWidgetContent` case, and adding an AppKit body view. Transcript
/// grouping, outcome markers, and row dispatch stay untouched.
struct HostToolTranscriptDescriptor: Sendable {
    /// Host-side tool name, such as `propose_scheduled_task`.
    let hostToolName: String
    /// Builds renderable content. Returning `nil` falls back to the generic tool row.
    let makeContent: @Sendable (_ toolInput: String?, _ toolOutput: String?, _ isError: Bool) -> HostToolWidgetContent?
    /// Correlation key linking a durable outcome marker to this call, derived from the tool result.
    let outcomeKey: @Sendable (_ toolOutput: String?) -> String?

    /// Fully qualified provider name, such as `mcp__alveary_host__propose_scheduled_task`.
    var qualifiedToolName: String {
        HostToolTranscriptCatalog.toolName(hostToolName)
    }

    /// Providers disagree on how they report a host MCP tool: Claude qualifies it with
    /// the server prefix while Codex reports the bare host name, and both shapes reach
    /// the transcript, so a descriptor has to answer to either.
    func matches(toolName: String) -> Bool {
        AlvearyHostToolCatalog.matches(reportedName: toolName, hostToolName: hostToolName)
    }
}

enum HostToolTranscriptCatalog {
    static func toolName(_ tool: String) -> String {
        AlvearyHostToolCatalog.qualifiedToolName(tool)
    }

    static let descriptors: [HostToolTranscriptDescriptor] = [
        scheduledTaskProposalDescriptor,
        pullRequestLinkDescriptor,
        pullRequestUnlinkDescriptor
    ] + threadActionDescriptors

    static func descriptor(forToolName toolName: String) -> HostToolTranscriptDescriptor? {
        descriptors.first { $0.matches(toolName: toolName) }
    }
}

private extension HostToolTranscriptCatalog {
    static var scheduledTaskProposalDescriptor: HostToolTranscriptDescriptor {
        HostToolTranscriptDescriptor(
            hostToolName: ScheduledTaskHostToolCatalog.proposeToolName,
            makeContent: { input, output, isError in
                guard let content = ScheduledTaskWidgetParsing.proposalContent(
                    input: input,
                    output: output,
                    isError: isError
                ) else {
                    return nil
                }
                return .scheduledTaskProposal(content)
            },
            outcomeKey: { output in
                ScheduledTaskWidgetParsing.proposalID(fromOutput: output)
            }
        )
    }

    static var pullRequestLinkDescriptor: HostToolTranscriptDescriptor {
        pullRequestDescriptor(
            hostToolName: ThreadHostToolCatalog.linkPullRequestToolName,
            action: .link
        )
    }

    static var pullRequestUnlinkDescriptor: HostToolTranscriptDescriptor {
        pullRequestDescriptor(
            hostToolName: ThreadHostToolCatalog.unlinkPullRequestToolName,
            action: .unlink
        )
    }

    /// Every thread mutation gets a card; the read-only lookups (`list_threads`,
    /// `list_projects`, `list_linked_prs`) stay ordinary tool rows.
    static var threadActionDescriptors: [HostToolTranscriptDescriptor] {
        [
            threadActionDescriptor(hostToolName: ThreadHostToolCatalog.createThreadToolName, action: .create),
            threadActionDescriptor(hostToolName: ThreadHostToolCatalog.pinThreadToolName, action: .pin),
            threadActionDescriptor(hostToolName: ThreadHostToolCatalog.unpinThreadToolName, action: .unpin),
            threadActionDescriptor(hostToolName: ThreadHostToolCatalog.archiveThreadToolName, action: .archive)
        ]
    }

    /// Like the link tools, these apply immediately, so the result is the whole outcome and
    /// none of them records a `host_tool_outcome` marker to correlate with.
    static func threadActionDescriptor(
        hostToolName: String,
        action: ThreadActionWidgetContent.Action
    ) -> HostToolTranscriptDescriptor {
        HostToolTranscriptDescriptor(
            hostToolName: hostToolName,
            makeContent: { input, output, isError in
                guard let content = ThreadActionWidgetParsing.content(
                    action: action,
                    input: input,
                    output: output,
                    isError: isError
                ) else {
                    return nil
                }
                return .threadAction(content)
            },
            outcomeKey: { _ in nil }
        )
    }

    /// Both link tools apply immediately, so their result is the whole outcome and neither
    /// records a `host_tool_outcome` marker to correlate with.
    static func pullRequestDescriptor(
        hostToolName: String,
        action: PullRequestLinkWidgetContent.Action
    ) -> HostToolTranscriptDescriptor {
        HostToolTranscriptDescriptor(
            hostToolName: hostToolName,
            makeContent: { input, output, isError in
                guard let content = PullRequestLinkWidgetParsing.content(
                    action: action,
                    input: input,
                    output: output,
                    isError: isError
                ) else {
                    return nil
                }
                return .pullRequestLink(content)
            },
            outcomeKey: { _ in nil }
        )
    }
}

/// Pure parsing for the scheduled-task host tools' persisted input/output JSON, decoded
/// through `HostToolWidgetJSON`.
enum ScheduledTaskWidgetParsing {
    static func proposalContent(
        input: String?,
        output: String?,
        isError: Bool
    ) -> ScheduledTaskProposalWidgetContent? {
        guard let arguments = HostToolWidgetJSON.object(from: input) else {
            return nil
        }
        let request = try? ScheduledTaskHostToolRequestParser().parse(arguments: arguments).request
        guard let action = request?.action ?? rawAction(in: arguments) else {
            return nil
        }

        let details = ProposalDetails(request: request, arguments: arguments)
        let receipt = HostToolWidgetJSON.object(from: output).map(ProposalReceipt.init(object:))
        return ScheduledTaskProposalWidgetContent(
            action: action,
            proposedTitle: details.title ?? receipt?.title,
            recurrence: details.schedule?.recurrence,
            timeZoneIdentifier: details.schedule?.timeZoneIdentifier,
            targetDefinitionID: details.definitionID,
            proposalID: receipt?.proposalID,
            message: receipt?.message ?? HostToolWidgetJSON.plainText(from: output),
            status: status(receipt: receipt, output: output, isError: isError, action: action)
        )
    }

    static func proposalID(fromOutput output: String?) -> String? {
        guard let object = HostToolWidgetJSON.object(from: output) else {
            return nil
        }
        return ProposalReceipt(object: object).proposalID
    }
}

private extension ScheduledTaskWidgetParsing {
    struct ProposalReceipt {
        let status: String?
        let proposalID: String?
        let title: String?
        let message: String?

        init(object: [String: AgentCLIKit.JSONValue]) {
            status = HostToolWidgetJSON.string(object["status"])
            proposalID = HostToolWidgetJSON.string(object["proposal_id"])
            title = HostToolWidgetJSON.string(object["title"])
            message = HostToolWidgetJSON.string(object["message"])
        }
    }

    struct ProposalDetails {
        let title: String?
        let schedule: ScheduledTaskProposalSchedule?
        let definitionID: String?

        init(request: ScheduledTaskProposalRequest?, arguments: [String: AgentCLIKit.JSONValue]) {
            switch request {
            case let .create(title, _, schedule, _):
                self.title = title
                self.schedule = schedule
                definitionID = nil
            case let .edit(definitionID, _, changes):
                title = changes.title
                schedule = changes.schedule
                self.definitionID = definitionID
            case let .pause(definitionID, _),
                 let .resume(definitionID, _),
                 let .delete(definitionID, _),
                 let .runNow(definitionID, _):
                title = nil
                schedule = nil
                self.definitionID = definitionID
            case nil:
                // Strict parsing failed; keep whatever the raw arguments can offer so the
                // widget still names what the model asked for.
                title = HostToolWidgetJSON.string(arguments["title"])
                schedule = nil
                definitionID = HostToolWidgetJSON.string(arguments["task_id"])
            }
        }
    }

    /// Providers surface a host tool's result differently: Claude emits
    /// `JSON.stringify(structuredContent)` while Codex emits the plain text fallback.
    /// Only an explicit error means failure — a result we cannot parse still opened a
    /// proposal, and the transcript resolves it by conversation instead.
    static func status(
        receipt: ProposalReceipt?,
        output: String?,
        isError: Bool,
        action: ScheduledTaskProposalAction
    ) -> ScheduledTaskProposalWidgetContent.Status {
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .running
        }
        if isError || receipt?.status == "error" {
            return .failed
        }
        if receipt?.status == ScheduledTaskHostToolService.appliedStatus {
            return .applied
        }
        // The host never opens a proposal for these actions, so a fallback result that
        // carries no parseable status is still a success that already took effect —
        // without this the widget reads as pending until its outcome marker lands at
        // the turn-end rebuild. A parsed receipt keeps its own status: historical rows
        // predate the immediate path and really did open proposals.
        if receipt?.status == nil, ScheduledTaskHostToolService.appliesWithoutConfirmation(action) {
            return .applied
        }
        return .pendingConfirmation
    }

    static func rawAction(in arguments: [String: AgentCLIKit.JSONValue]) -> ScheduledTaskProposalAction? {
        HostToolWidgetJSON.string(arguments["action"]).flatMap(ScheduledTaskProposalAction.init(rawValue:))
    }
}
