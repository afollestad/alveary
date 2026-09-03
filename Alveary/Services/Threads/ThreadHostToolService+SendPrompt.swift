import AgentCLIKit
import Foundation
import SwiftData

extension ThreadHostToolService {
    /// How many times a conversation may send one exact prompt to the same thread, with no
    /// message from its own user in between, before the next copy is refused as a loop. Threads
    /// are meant to talk unattended, so nothing here counts rounds; a loop shows itself as
    /// degenerate content — the same prompt over and over, or a relayed prompt echoed straight
    /// back — and only that is refused. The transport header already says not to echo, but a
    /// model that ignores it must hit a wall. Three allows a coordinator to poll a worker with
    /// the same question a couple of times before the repetition reads as a loop.
    static let identicalRelayLimit = 3

    /// Posts a prompt into another thread through the ordinary send path, so the target creates
    /// its workspace, spawns, and gets host-tool exposure exactly as if its user had typed there.
    ///
    /// Unlike `create_thread`'s fire-and-forget initial prompt, this awaits the target's
    /// queue-or-send decision: `sent` and `queued` are different answers for the model, and a
    /// refusal at the target — a pending question, a handoff in progress — has to reach it as an
    /// error rather than a claimed delivery. It still claims dispatch, never the turn's outcome.
    func sendPromptToThread(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        let requestID = try requireRequestID(context)
        try flushPendingChanges()
        let requestDate = requestDate()
        let source = try resolveSource(context: context)
        let parsed = try parseSendPrompt(arguments: arguments)
        let deduplicationKey = HostToolDeduplication.key(
            sourceConversationID: context.conversationId.rawValue,
            processToken: context.processToken,
            requestID: requestID,
            canonicalPayloadHash: parsed.canonicalPayloadHash
        )

        // An exact retry replays its receipt rather than posting the prompt a second time.
        if let receipt = try replayedReceipt(
            on: source.conversation,
            deduplicationKey: deduplicationKey,
            processToken: context.processToken,
            at: requestDate
        ) {
            return replayedSendPromptResult(receipt: receipt)
        }

        let target = try resolveSendPromptTarget(parsed, source: source, callerID: context.conversationId.rawValue)
        let relayed = ThreadHostToolRelayedPrompt(
            prompt: parsed.prompt,
            senderName: source.thread.displayName(),
            senderThreadID: source.conversation.id
        )

        // Only plain values cross the delivery's suspension; the source is re-resolved after it.
        let delivery: RelayedPromptDelivery
        do {
            delivery = try await deliverPrompt(target.conversation, relayed.outbound)
        } catch {
            throw ThreadHostToolServiceError.promptDeliveryFailed(
                threadName: target.name,
                reason: error.localizedDescription
            )
        }
        let outcome = ThreadHostToolSendPromptOutcome(delivery: delivery, threadID: target.threadID, name: target.name)
        try persistSendPromptReceipt(
            ThreadHostToolReceipt(
                deduplicationKey: deduplicationKey,
                threadID: target.threadID,
                name: target.name,
                status: outcome.status,
                message: outcome.message,
                sourceProcessToken: context.processToken.uuidString.lowercased(),
                createdAt: requestDate
            ),
            sourceConversationID: context.conversationId.rawValue
        )
        return outcome.result
    }
}

private extension ThreadHostToolService {
    /// The prompt is already on its way by now, so a source conversation that vanished across the
    /// delivery loses only its retry ledger; failing the call would tell the model to send again.
    func persistSendPromptReceipt(_ receipt: ThreadHostToolReceipt, sourceConversationID: String) throws {
        guard let sourceConversation = modelContext.resolveConversation(conversationID: sourceConversationID) else {
            return
        }
        try persistReceipt(receipt, on: sourceConversation)
    }

    /// The thread `thread_id` names, if a prompt may be posted into it. Applies the same
    /// listability rule as `list_threads`, so a thread the model could not have listed — forked,
    /// draft, pending a fork bootstrap — reads as missing rather than revealing that it exists.
    /// An archived thread is named as such instead, because the user can restore it and the
    /// model should say so. A prompt that would only continue a loop is refused last, after every
    /// cheaper check.
    func resolveSendPromptTarget(
        _ parsed: ThreadHostToolParsedSendPromptRequest,
        source: HostToolCallSource,
        callerID: String
    ) throws -> ThreadHostToolSendPromptTarget {
        let threadID = parsed.threadID
        guard let conversation = modelContext.resolveConversation(conversationID: threadID),
              let thread = conversation.thread,
              !thread.isDraft else {
            throw ThreadHostToolServiceError.threadNotFound
        }
        let name = thread.displayName()
        guard thread.archivedAt == nil else {
            throw ThreadHostToolServiceError.threadArchived(name: name)
        }
        guard thread.isListableHostToolThread,
              thread.soleMainConversation?.id == threadID else {
            throw ThreadHostToolServiceError.threadNotFound
        }
        // Sending to the calling thread would only queue the prompt behind the turn making this
        // call, and a model that answers itself never stops.
        guard thread.persistentModelID != source.thread.persistentModelID else {
            throw ThreadHostToolServiceError.cannotSendToOwnThread
        }
        switch try relayLoopCheck(prompt: parsed.prompt, with: threadID, in: callerID) {
        case .none:
            break
        case .echo:
            throw ThreadHostToolServiceError.relayEchoesPrompt(threadName: name)
        case .repeated(let count):
            throw ThreadHostToolServiceError.relayRepeatsPrompt(threadName: name, count: count)
        }
        return ThreadHostToolSendPromptTarget(conversation: conversation, threadID: threadID, name: name)
    }

    /// Whether `prompt` would only continue a loop with `counterpartID`, judged from the caller's
    /// own transcript newest first over the stretch since its user last typed: an echo repeats the
    /// latest prompt that thread relayed here, and a repeat sends the same prompt there for the
    /// `identicalRelayLimit`th time. A typed message ends the stretch; rows about other threads
    /// are skipped rather than ending it. Only sends that already have a result count, because
    /// the call being handled may or may not have its own row persisted yet.
    func relayLoopCheck(prompt: String, with counterpartID: String, in conversationID: String) throws -> RelayLoopCheck {
        let descriptor = FetchDescriptor<ConversationEventRecord>(
            predicate: #Predicate { $0.conversationId == conversationID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.id, order: .reverse)]
        )
        let rows: [ConversationEventRecord]
        do {
            rows = try modelContext.fetch(descriptor)
        } catch {
            throw ThreadHostToolServiceError.persistenceFailure
        }
        let candidate = Self.comparableRelayText(prompt)
        var latestReceived: String?
        var identicalSends = 0
        // Newest first, so a call's result row is seen before the call it answers.
        var answeredToolIDs = Set<String>()
        for row in rows {
            if row.type == ConversationEventRecord.messageType, row.role == ConversationEventRecord.userRole {
                guard let sender = row.relayedFromConversationId else {
                    break
                }
                if sender == counterpartID, latestReceived == nil {
                    latestReceived = Self.comparableRelayText(row.content ?? "")
                }
            } else if row.type == ConversationEventRecord.toolResultType, let toolID = row.toolId {
                answeredToolIDs.insert(toolID)
            } else if let sent = Self.sentPrompt(in: row, to: counterpartID),
                      Self.comparableRelayText(sent) == candidate,
                      answeredToolIDs.contains(row.toolId ?? "") {
                identicalSends += 1
            }
        }
        if latestReceived == candidate {
            return .echo
        }
        if identicalSends + 1 >= Self.identicalRelayLimit {
            return .repeated(count: identicalSends)
        }
        return .none
    }

    /// The prompt a persisted `send_prompt_to_thread` call aimed at `counterpartID`, under either
    /// reported name shape; `Alveary/Services/HostMCP/AGENTS.md` owns why there are two.
    static func sentPrompt(in row: ConversationEventRecord, to counterpartID: String) -> String? {
        guard row.type == ConversationEventRecord.toolCallType,
              let toolName = row.toolName,
              AlvearyHostToolCatalog.matches(
                  reportedName: toolName,
                  hostToolName: ThreadHostToolCatalog.sendPromptToThreadToolName
              ),
              let arguments = HostToolWidgetJSON.object(from: row.toolInput),
              HostToolWidgetJSON.string(arguments["thread_id"]) == counterpartID else {
            return nil
        }
        return HostToolWidgetJSON.string(arguments["prompt"])
    }

    /// Surrounding whitespace is the one variation a looping model produces without meaning it.
    static func comparableRelayText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func replayedSendPromptResult(receipt: ThreadHostToolReceipt) -> AgentCLIKit.AgentHostToolResult {
        ThreadHostToolSendPromptOutcome.result(
            status: receipt.status ?? "sent",
            threadID: receipt.threadID,
            name: receipt.name,
            message: receipt.message
        )
    }
}

/// What `relayLoopCheck` saw in the caller's transcript.
enum RelayLoopCheck: Equatable {
    case none
    /// The prompt is the latest one the counterpart relayed here.
    case echo
    /// The prompt has already gone to the counterpart `count` times since the user last typed.
    case repeated(count: Int)
}

/// The resolved target's live conversation plus the plain values the result names, snapshotted
/// before delivery suspends.
private struct ThreadHostToolSendPromptTarget {
    let conversation: Conversation
    let threadID: String
    let name: String
}

/// What `send_prompt_to_thread` did, rendered into both result shapes from one place.
private struct ThreadHostToolSendPromptOutcome {
    let delivery: RelayedPromptDelivery
    let threadID: String
    let name: String

    var status: String {
        switch delivery {
        case .sent:
            "sent"
        case .queued:
            "queued"
        }
    }

    var message: String {
        switch delivery {
        case .sent:
            "Sent the prompt to the thread \"\(name)\" (id: \(threadID)). It is running there now; its results " +
                "appear in that thread, not here."
        case .queued:
            "Queued the prompt for the thread \"\(name)\" (id: \(threadID)) behind its current turn. It sends when " +
                "that turn ends; its results appear in that thread, not here."
        }
    }

    var result: AgentCLIKit.AgentHostToolResult {
        Self.result(status: status, threadID: threadID, name: name, message: message)
    }

    static func result(
        status: String,
        threadID: String,
        name: String?,
        message: String
    ) -> AgentCLIKit.AgentHostToolResult {
        var content: [String: AgentCLIKit.JSONValue] = [
            "status": .string(status),
            "thread_id": .string(threadID),
            "message": .string(message)
        ]
        if let name {
            content["name"] = .string(name)
        }
        return AgentCLIKit.AgentHostToolResult(text: message, structuredContent: .object(content))
    }
}
