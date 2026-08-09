#if DEBUG
import Foundation
import SwiftData

/// Builds one conversation's `ConversationEventRecord`s in reading order.
///
/// Records go through the raw initializer rather than `ConversationEvent.toRecord(conversation:)`
/// because the seeder needs fields that path never sets — `timestamp` above all. `toRecord` leaves
/// every record defaulting to `.now`, and transcript ordering sorts on `(conversationId,
/// timestamp)`, so identical values order nondeterministically. `commit(endingAt:)` stamps a
/// strictly increasing sequence instead.
@MainActor
final class DemoTranscriptBuilder {
    /// Seconds between consecutive rows. Wide enough that relative timestamps read plausibly,
    /// narrow enough that a long transcript still ends near its thread's `modifiedAt`.
    private static let step: TimeInterval = 9

    private let conversation: Conversation
    private var records: [ConversationEventRecord] = []

    init(conversation: Conversation) {
        self.conversation = conversation
    }

    // MARK: Messages

    @discardableResult
    func user(_ text: String) -> ConversationEventRecord {
        append(make(type: ConversationEventRecord.messageType, role: ConversationEventRecord.userRole, content: text))
    }

    @discardableResult
    func assistant(_ text: String) -> ConversationEventRecord {
        append(
            make(
                type: ConversationEventRecord.messageType,
                role: ConversationEventRecord.assistantRole,
                content: text
            )
        )
    }

    // MARK: Tools

    /// A call and its result, the ordinary shape. Omit `output` to leave the tool in flight, which
    /// is what renders the transcript's loading spinner.
    func tool(
        id: String,
        name: String,
        input: String,
        output: String? = nil,
        stderr: String? = nil,
        isError: Bool = false,
        parentToolUseID: String? = nil
    ) {
        toolCall(id: id, name: name, input: input, parentToolUseID: parentToolUseID)
        guard let output else {
            return
        }
        toolResult(id: id, output: output, stderr: stderr, isError: isError, parentToolUseID: parentToolUseID)
    }

    /// Split from `tool(…)` for a parent whose children have to land between its call and its
    /// result, which is the order a sub-agent block reads best in.
    func toolCall(id: String, name: String, input: String, parentToolUseID: String? = nil) {
        let call = make(type: ConversationEventRecord.toolCallType, toolId: id, toolName: name, toolInput: input)
        call.parentToolUseId = parentToolUseID
        append(call)
    }

    func toolResult(
        id: String,
        output: String,
        stderr: String? = nil,
        isError: Bool = false,
        parentToolUseID: String? = nil
    ) {
        let result = make(type: ConversationEventRecord.toolResultType, toolId: id)
        result.toolOutput = output
        result.toolOutputStderr = stderr
        result.isError = isError
        result.parentToolUseId = parentToolUseID
        append(result)
    }

    /// An `AskUserQuestion` prompt. The answer lives on the *call*'s `content`, which is what the
    /// grouper reads as `submittedSummary`; leaving `answeredSummary` nil renders the live,
    /// unanswered card.
    func question(id: String, input: String, answeredSummary: String? = nil) {
        let call = make(type: ConversationEventRecord.toolCallType, toolId: id, toolName: "AskUserQuestion", toolInput: input)
        call.content = answeredSummary
        append(call)
        guard let answeredSummary else {
            return
        }
        toolResult(id: id, output: answeredSummary)
    }

    /// A permission prompt. `sessionID` lands in `content`: consecutive approvals that share it,
    /// a status, and a batchable tool name render as one batch card. `status` must be the literal
    /// `"pending"` for a live prompt — `nil` renders the same layout but disabled.
    func approval(
        id: String,
        name: String,
        input: String,
        sessionID: String,
        status: String?
    ) {
        let record = make(type: ConversationEventRecord.toolApprovalType, toolId: id, toolName: name, toolInput: input)
        record.content = sessionID
        record.toolApprovalStatus = status
        append(record)
    }

    /// The hidden marker that terminalizes a sub-agent's visible row.
    func subAgentCompleted(id: String, toolUses: Int, totalTokens: Int, durationMs: Int) {
        let record = make(type: ConversationEventRecord.subAgentCompletedType, toolId: id)
        record.content = #"{"status":"completed","toolUses":\#(toolUses),"totalTokens":\#(totalTokens)}"#
        record.durationMs = durationMs
        append(record)
    }

    /// The hidden marker a host-tool widget resolves its confirmation against.
    func hostToolOutcome(toolName: String, key: String, payload: String) {
        let record = make(type: ConversationEventRecord.hostToolOutcomeType, toolId: key, toolName: toolName)
        record.content = payload
        append(record)
    }

    // MARK: Notes and errors

    func note(type: String, content: String? = nil) {
        let record = make(type: type)
        record.content = content
        append(record)
    }

    func error(_ message: String) {
        let record = make(type: ConversationEventRecord.errorType, content: message)
        record.isError = true
        append(record)
    }

    /// The usage/cost/context chip's source. `stopReason` matters beyond display: a later token
    /// row whose reason is neither `tool_deferred` nor `usage_update` marks every earlier
    /// approval resolved, which would grey out a live prompt.
    func tokens(
        input: Int,
        output: Int,
        cacheRead: Int = 0,
        costUsd: Double,
        model: String,
        stopReason: String = "end_turn",
        durationMs: Int = 0
    ) {
        let record = make(type: ConversationEventRecord.tokensType)
        record.tokenInput = input
        record.tokenOutput = output
        record.tokenCacheRead = cacheRead
        record.costUsd = costUsd
        record.costUsdReported = true
        record.providerModelId = model
        record.contextWindowSize = 200_000
        record.stopReason = stopReason
        record.durationMs = durationMs
        append(record)
    }

    // MARK: Commit

    /// Stamps every record with a strictly increasing timestamp ending at `endingAt`, then
    /// inserts them. Returns the records so callers can key follow-up state off a specific id.
    @discardableResult
    func commit(into context: ModelContext, endingAt: Date) -> [ConversationEventRecord] {
        for (index, record) in records.enumerated() {
            let stepsFromEnd = Double(records.count - 1 - index)
            record.timestamp = endingAt.addingTimeInterval(-stepsFromEnd * Self.step)
            context.insert(record)
        }
        return records
    }

    private func make(
        type: String,
        role: String? = nil,
        content: String? = nil,
        toolId: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            type: type,
            role: role,
            content: content,
            toolId: toolId,
            toolName: toolName,
            toolInput: toolInput,
            conversation: conversation
        )
    }

    @discardableResult
    private func append(_ record: ConversationEventRecord) -> ConversationEventRecord {
        records.append(record)
        return record
    }
}
#endif
